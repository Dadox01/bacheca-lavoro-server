import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dao/company_dao.dart';
import '../errors/api_exception.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/error_middleware.dart';
import '../services/password_service.dart';
import '../services/token_service.dart';
import '../utils/validators.dart';

class AuthController {
  final CompanyDao companies;
  final TokenService tokens;

  AuthController(this.companies, this.tokens);

  Router get router {
    final r = Router();
    r.post('/api/auth/register', _register);
    r.post('/api/auth/login', _login);
    r.post('/api/auth/logout', guard(_logout));
    r.get('/api/auth/me', guard(_me));
    return r;
  }

  /// R1 - Registrazione azienda.
  Future<Response> _register(Request req) async {
    final input = validateRegister(await readJsonObject(req));

    if (companies.findByEmail(input.email) != null) {
      throw const ApiException(409, 'Esiste già un account con questa email');
    }

    final salt = PasswordService.generateSalt();
    final company = await companies.create(
      name: input.name,
      email: input.email,
      passwordHash: PasswordService.hash(input.password, salt),
      salt: salt,
      createdAt: formatIsoUtc(DateTime.now()),
    );
    final token = tokens.issue(company.id);
    return jsonResponse({'token': token, 'company': company.toPublicJson()},
        status: 201);
  }

  /// R2 - Login azienda.
  Future<Response> _login(Request req) async {
    final input = validateLogin(await readJsonObject(req));
    final company = companies.findByEmail(input.email);
    final ok = company != null &&
        PasswordService.verify(
            input.password, company.salt, company.passwordHash);
    if (!ok) throw const ApiException(401, 'Email o password non corretti');
    final token = tokens.issue(company.id);
    return jsonResponse({'token': token, 'company': company.toPublicJson()});
  }

  /// R3 - Logout azienda: il token viene revocato lato server.
  Response _logout(Request req) {
    final token = currentToken(req);
    if (token != null) tokens.revoke(token);
    return Response(204);
  }

  /// Ripristino della sessione salvata sul client.
  Response _me(Request req) =>
      jsonResponse(currentCompany(req)!.toPublicJson());
}
