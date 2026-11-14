import 'dart:convert';
import 'dart:math';

/// Token opachi in memoria: token -> companyId.
/// Un riavvio del server invalida le sessioni: il client torna all'area pubblica.
class TokenService {
  final Map<String, int> _tokens = {};
  final Random _rng = Random.secure();

  String issue(int companyId) {
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    _tokens[token] = companyId;
    return token;
  }

  int? companyIdFor(String token) => _tokens[token];

  void revoke(String token) => _tokens.remove(token);
}
