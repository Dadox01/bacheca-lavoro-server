import 'dart:convert';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';

class UploadedFile {
  final String filename;
  final String? contentType;
  final Uint8List bytes;

  const UploadedFile({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });
}

class MultipartForm {
  final Map<String, String> fields = {};
  final Map<String, UploadedFile> files = {};

  bool get isEmpty => fields.isEmpty && files.isEmpty;
}

/// Parser minimale di multipart/form-data basato su package:mime.
/// Applica un limite complessivo al corpo per non caricare in memoria file enormi.
Future<MultipartForm> readMultipartForm(
  Request request, {
  int maxBytes = 6 * 1024 * 1024,
}) async {
  final header = request.headers['content-type'] ?? '';
  if (!header.toLowerCase().startsWith('multipart/form-data')) {
    throw const ApiException(
        400, 'Richiesta non valida: atteso multipart/form-data');
  }
  final boundary = _boundary(header);
  if (boundary == null) {
    throw const ApiException(400, 'Richiesta non valida: boundary mancante');
  }

  final declared = request.contentLength;
  if (declared != null && declared > maxBytes) {
    throw const ApiException(413, 'Il file allegato supera il limite di 5 MB');
  }

  final form = MultipartForm();
  var total = 0;

  // shelf restituisce Stream<Uint8List>: il cast lo rende compatibile con il
  // transformer di package:mime, tipizzato su Stream<List<int>>.
  final parts = request
      .read()
      .cast<List<int>>()
      .transform(MimeMultipartTransformer(boundary));
  await for (final part in parts) {
    final disposition = part.headers['content-disposition'] ?? '';
    final fieldName = _param(disposition, 'name');
    if (fieldName == null) {
      await part.drain<void>();
      continue;
    }

    final rawFilename = _param(disposition, 'filename') ??
        _extendedParam(disposition, 'filename');
    final chunks = <List<int>>[];
    await for (final chunk in part) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const ApiException(
            413, 'Il file allegato supera il limite di 5 MB');
      }
      chunks.add(chunk);
    }
    final bytes = Uint8List.fromList([for (final c in chunks) ...c]);

    if (rawFilename == null) {
      form.fields[fieldName] = utf8.decode(bytes, allowMalformed: true).trim();
    } else {
      form.files[fieldName] = UploadedFile(
        filename: _decodeFilename(rawFilename),
        contentType: part.headers['content-type'],
        bytes: bytes,
      );
    }
  }

  if (form.isEmpty) {
    throw const ApiException(400, 'Richiesta non valida: modulo vuoto');
  }
  return form;
}

String? _boundary(String header) {
  final m = RegExp(r'boundary=(?:"([^"]+)"|([^;\s]+))', caseSensitive: false)
      .firstMatch(header);
  return m?.group(1) ?? m?.group(2);
}

/// Estrae il valore di un parametro tipo name="cv" (o name=cv).
String? _param(String header, String key) {
  final quoted = RegExp('(?:^|;)\\s*$key="([^"]*)"', caseSensitive: false)
      .firstMatch(header);
  if (quoted != null) return quoted.group(1);
  final bare = RegExp('(?:^|;)\\s*$key=([^;]*)', caseSensitive: false)
      .firstMatch(header);
  return bare?.group(1)?.trim();
}

/// filename*=UTF-8''nome%20file.pdf (RFC 5987)
String? _extendedParam(String header, String key) {
  final m = RegExp("(?:^|;)\\s*$key\\*=([^;]*)", caseSensitive: false)
      .firstMatch(header);
  if (m == null) return null;
  final value = m.group(1)!.trim();
  final quote = value.indexOf("''");
  return quote >= 0 ? Uri.decodeComponent(value.substring(quote + 2)) : value;
}

String _decodeFilename(String raw) {
  if (!raw.contains('%')) return raw;
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}
