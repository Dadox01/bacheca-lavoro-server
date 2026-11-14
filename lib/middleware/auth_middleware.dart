import 'package:shelf/shelf.dart';

import '../dao/company_dao.dart';
import '../errors/api_exception.dart';
import '../models/company.dart';
import '../services/token_service.dart';
import 'error_middleware.dart';

const String _companyKey = 'bacheca.company';
const String _tokenKey = 'bacheca.token';

/// Azienda autenticata della richiesta (null se ospite).
Company? currentCompany(Request request) =>
    request.context[_companyKey] as Company?;

/// Token Bearer valido della richiesta (null se assente/non valido).
String? currentToken(Request request) => request.context[_tokenKey] as String?;

/// Legge "Authorization: Bearer xxx" e mette azienda e token nel context.
///
/// Per il download del curriculum (aperto dal browser del sistema, che non
/// può inviare header) è accettato anche il parametro ?token=xxx.
Middleware authMiddleware(TokenService tokens, CompanyDao companies) {
  return (Handler inner) {
    return (Request request) {
      var req = request;
      final header = request.headers['authorization'];
      var token = header != null && header.toLowerCase().startsWith('bearer ')
          ? header.substring(7).trim()
          : null;
      token ??= request.url.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        final companyId = tokens.companyIdFor(token);
        if (companyId != null) {
          final company = companies.findById(companyId);
          if (company != null) {
            req = request.change(context: {
              _companyKey: company,
              _tokenKey: token,
            });
          }
        }
      }
      return Future.sync(() => inner(req));
    };
  };
}

/// Come [guard] ma per handler con parametri di percorso: lancia 401 se ospite.
Company requireCompany(Request request) {
  final company = currentCompany(request);
  if (company == null) {
    throw const ApiException(401, 'Autenticazione richiesta');
  }
  return company;
}

/// Protegge un handler: 401 senza token valido.
Handler guard(Handler handler) {
  return (Request request) {
    if (currentCompany(request) == null) {
      return jsonError(401, 'Autenticazione richiesta');
    }
    return handler(request);
  };
}
