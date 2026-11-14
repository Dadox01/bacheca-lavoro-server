import 'dart:io';

import 'package:bacheca_server/controllers/application_controller.dart';
import 'package:bacheca_server/controllers/auth_controller.dart';
import 'package:bacheca_server/controllers/job_controller.dart';
import 'package:bacheca_server/dao/application_dao.dart';
import 'package:bacheca_server/dao/company_dao.dart';
import 'package:bacheca_server/dao/job_dao.dart';
import 'package:bacheca_server/dao/json_store.dart';
import 'package:bacheca_server/middleware/auth_middleware.dart';
import 'package:bacheca_server/middleware/error_middleware.dart';
import 'package:bacheca_server/services/cv_storage.dart';
import 'package:bacheca_server/services/token_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final dataDir = Platform.environment['DATA_DIR'] ?? 'data';
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  await Directory(dataDir).create(recursive: true);

  // DAO con persistenza su file JSON + cartella dei curriculum.
  final companyDao = CompanyDao(JsonCollection('$dataDir/companies.json'));
  final jobDao = JobDao(JsonCollection('$dataDir/jobs.json'));
  final applicationDao =
      ApplicationDao(JsonCollection('$dataDir/applications.json'));
  await companyDao.load();
  await jobDao.load();
  await applicationDao.load();

  final storage = CvStorage('$dataDir/uploads');
  await storage.init();

  final tokens = TokenService();

  final health = Router()
    ..get(
        '/api/health',
        (Request req) => jsonResponse({
              'status': 'ok',
              'jobs': jobDao.all().length,
              'applications': applicationDao.all().length,
            }));

  // Cascade: ogni controller dichiara i path completi e i 404 "di business"
  // sono ApiException, quindi non vengono scambiati per "rotta non trovata".
  final api = Cascade()
      .add(health.call)
      .add(AuthController(companyDao, tokens).router.call)
      .add(JobController(jobDao, applicationDao).router.call)
      .add(ApplicationController(jobDao, applicationDao, storage).router.call)
      .add((Request req) => jsonError(404, 'Risorsa non trovata'))
      .handler;

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware())
      .addMiddleware(errorMiddleware())
      .addMiddleware(authMiddleware(tokens, companyDao))
      .addHandler(api);

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
      'Bacheca lavoro - backend in ascolto sulla porta ${server.port}');
  stdout.writeln('Dati persistenti in: ${Directory(dataDir).absolute.path}');
  stdout.writeln(
      'Simulatore iOS / macOS / browser: http://127.0.0.1:${server.port}');
  stdout.writeln('Emulatore Android: http://10.0.2.2:${server.port}');
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        stdout.writeln('Telefono reale: http://${addr.address}:${server.port}');
      }
    }
  } catch (_) {
    stdout.writeln('Impossibile leggere gli indirizzi di rete locali.');
  }
}
