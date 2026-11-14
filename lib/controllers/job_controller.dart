import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dao/application_dao.dart';
import '../dao/job_dao.dart';
import '../errors/api_exception.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/error_middleware.dart';
import '../models/job.dart';
import '../utils/validators.dart';

class JobController {
  final JobDao jobs;
  final ApplicationDao applications;

  JobController(this.jobs, this.applications);

  Router get router {
    final r = Router();
    r.get('/api/jobs', _list);
    r.get('/api/jobs/mine', guard(_mine));
    r.post('/api/jobs', guard(_create));
    r.get('/api/jobs/<id|[0-9]+>', _detail);
    return r;
  }

  /// R5 - Bacheca pubblica: elenco annunci, con ricerca testuale opzionale.
  Response _list(Request req) {
    final q = req.url.queryParameters['q'];
    final list = jobs.search(q: q).map((j) => j.toPublicJson()).toList();
    return jsonResponse(list);
  }

  /// R5 - Dettaglio pubblico di un annuncio.
  Response _detail(Request req, String id) {
    final job = jobs.findById(_parseId(id));
    if (job == null) throw const ApiException(404, 'Annuncio non trovato');
    return jsonResponse(job.toPublicJson());
  }

  /// R7 - Annunci della sola azienda autenticata, con numero di candidature.
  Response _mine(Request req) {
    final company = currentCompany(req)!;
    final list = jobs
        .byCompany(company.id)
        .map((j) => j.toPublicJson(
            applicationsCount: applications.countByJob(j.id)))
        .toList();
    return jsonResponse(list);
  }

  /// R4 - Pubblicazione di un nuovo annuncio.
  Future<Response> _create(Request req) async {
    final company = currentCompany(req)!;
    final input = validateJob(await readJsonObject(req));
    final job = await jobs.create(
      companyId: company.id,
      companyName: company.name,
      title: input.title,
      description: input.description,
      location: input.location,
      contract: input.contract,
      salary: input.salary,
      createdAt: formatIsoUtc(DateTime.now()),
    );
    return jsonResponse(job.toPublicJson(applicationsCount: 0), status: 201);
  }

  int _parseId(String raw) =>
      int.tryParse(raw) ?? (throw const ApiException(404, 'Annuncio non trovato'));
}

/// Carica un annuncio verificando che appartenga all'azienda autenticata.
Job ownedJob(JobDao jobs, Request req, String id) {
  final job = jobs.findById(int.tryParse(id) ?? -1);
  if (job == null) throw const ApiException(404, 'Annuncio non trovato');
  final company = currentCompany(req)!;
  if (job.companyId != company.id) {
    throw const ApiException(403, 'Questo annuncio non appartiene alla tua azienda');
  }
  return job;
}
