import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dao/application_dao.dart';
import '../dao/job_dao.dart';
import '../errors/api_exception.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/error_middleware.dart';
import '../models/application.dart';
import '../services/cv_storage.dart';
import '../utils/multipart.dart';
import '../utils/validators.dart';
import 'job_controller.dart';

class ApplicationController {
  final JobDao jobs;
  final ApplicationDao applications;
  final CvStorage storage;

  ApplicationController(this.jobs, this.applications, this.storage);

  Router get router {
    final r = Router();
    // R6 - candidatura pubblica (nessun login richiesto)
    r.post('/api/jobs/<id|[0-9]+>/applications', _create);
    // R7 - candidature ricevute, riservate all'azienda proprietaria
    r.get('/api/jobs/<id|[0-9]+>/applications', _listByJob);
    r.get('/api/applications/<id|[0-9]+>', _detail);
    r.get('/api/applications/<id|[0-9]+>/cv', _downloadCv);
    return r;
  }

  /// R6 - Il candidato invia dati + curriculum (multipart/form-data).
  Future<Response> _create(Request req, String id) async {
    final job = jobs.findById(int.tryParse(id) ?? -1);
    if (job == null) throw const ApiException(404, 'Annuncio non trovato');

    final form =
        await readMultipartForm(req, maxBytes: CvStorage.maxBytes + 256 * 1024);
    final input = validateApplication(form.fields);

    final upload = form.files['cv'];
    if (upload == null) {
      throw const ApiException(422, 'Il curriculum (PDF) è obbligatorio');
    }

    final cv = await storage.save(
      originalName: upload.filename,
      bytes: upload.bytes,
      contentType: upload.contentType,
    );

    final application = await applications.create(
      jobId: job.id,
      jobTitle: job.title,
      firstName: input.firstName,
      lastName: input.lastName,
      email: input.email,
      message: input.message,
      cv: cv,
      createdAt: formatIsoUtc(DateTime.now()),
    );
    return jsonResponse(application.toJson(), status: 201);
  }

  /// R7 - Candidature ricevute per un annuncio dell'azienda autenticata.
  Response _listByJob(Request req, String id) {
    requireCompany(req);
    final job = ownedJob(jobs, req, id);
    final list = applications.byJob(job.id).map((a) => a.toJson()).toList();
    return jsonResponse({
      'job': job.toPublicJson(applicationsCount: list.length),
      'applications': list,
    });
  }

  /// R7 - Dettaglio di una candidatura (solo per l'azienda proprietaria).
  Response _detail(Request req, String id) {
    requireCompany(req);
    final application = _ownedApplication(req, id);
    return jsonResponse(application.toJson());
  }

  /// R7 - Il curriculum allegato, servito come PDF.
  Future<Response> _downloadCv(Request req, String id) async {
    requireCompany(req);
    final application = _ownedApplication(req, id);
    final file = storage.fileFor(application.cv.storedName);
    if (file == null || !await file.exists()) {
      throw const ApiException(404, 'Curriculum non disponibile');
    }
    final length = await file.length();
    final name = application.cv.originalName.replaceAll('"', '');
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/pdf',
        'content-length': '$length',
        'content-disposition':
            "inline; filename=\"$name\"; filename*=UTF-8''${Uri.encodeComponent(name)}",
      },
    );
  }

  Application _ownedApplication(Request req, String id) {
    final application = applications.findById(int.tryParse(id) ?? -1);
    if (application == null) {
      throw const ApiException(404, 'Candidatura non trovata');
    }
    final job = jobs.findById(application.jobId);
    final company = currentCompany(req)!;
    if (job == null || job.companyId != company.id) {
      throw const ApiException(
          403, 'Questa candidatura non riguarda i tuoi annunci');
    }
    return application;
  }
}
