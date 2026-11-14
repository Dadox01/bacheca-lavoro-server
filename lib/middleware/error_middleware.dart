import 'dart:convert';

import 'dart:io';
import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

/// Risposta JSON standard.
Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

/// Risposta di errore del contratto: {"error": "messaggio"}.
Response jsonError(int status, String message) =>
    jsonResponse({'error': message}, status: status);

/// Middleware che traduce le eccezioni nel contratto di errore JSON.
Middleware errorMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on ApiException catch (e) {
        return jsonError(e.status, e.message);
      } on FormatException {
        return jsonError(400, 'Richiesta non valida');
      } catch (e, st) {
        // Si registra solo il tipo e lo stack: mai il corpo della richiesta.
        stderr.writeln('Errore interno (${e.runtimeType}): $st');
        return jsonError(500, 'Errore interno del server');
      }
    };
  };
}

/// CORS permissivo: serve solo alla demo su Flutter web (stesso backend).
Middleware corsMiddleware() {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
  };
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };
  };
}
