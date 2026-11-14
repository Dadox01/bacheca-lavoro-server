import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../errors/api_exception.dart';
import '../models/application.dart';
import '../utils/validators.dart';

/// Salvataggio dei curriculum su disco.
///
/// I file finiscono in [dir] con un nome casuale: il nome originale arriva dal
/// client e non viene mai usato come percorso (niente path traversal).
class CvStorage {
  static const int maxBytes = 5 * 1024 * 1024;

  final String dir;
  final Random _rng = Random.secure();

  CvStorage(this.dir);

  Future<void> init() => Directory(dir).create(recursive: true);

  String _randomName() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<CvFile> save({
    required String originalName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    if (bytes.isEmpty) {
      throw const ApiException(422, 'Il curriculum è vuoto');
    }
    if (bytes.length > maxBytes) {
      throw const ApiException(422, 'Il curriculum supera il limite di 5 MB');
    }
    if (!looksLikePdf(bytes)) {
      throw const ApiException(422, 'Il curriculum deve essere un file PDF');
    }
    final clean = sanitizeFileName(originalName);
    final stored = '${_randomName()}.pdf';
    await Directory(dir).create(recursive: true);
    final file = File('$dir/$stored');
    await file.writeAsBytes(bytes, flush: true);
    return CvFile(
      originalName: clean,
      storedName: stored,
      size: bytes.length,
      uploadedAt: formatIsoUtc(DateTime.now()),
    );
  }

  File? fileFor(String storedName) {
    // Solo nomi generati da noi: niente separatori di percorso.
    if (!RegExp(r'^[a-f0-9]{32}\.pdf$').hasMatch(storedName)) return null;
    final file = File('$dir/$storedName');
    return file;
  }
}
