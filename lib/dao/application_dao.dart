import '../models/application.dart';
import 'json_store.dart';

class ApplicationDao {
  final JsonCollection _col;

  ApplicationDao(this._col);

  Future<void> load() => _col.load();

  List<Application> all() {
    final list = _col.all().map(Application.fromJson).toList();
    list.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return list;
  }

  Application? findById(int id) {
    for (final m in _col.all()) {
      if (m['id'] == id) return Application.fromJson(m);
    }
    return null;
  }

  List<Application> byJob(int jobId) =>
      all().where((a) => a.jobId == jobId).toList();

  int countByJob(int jobId) =>
      _col.all().where((m) => m['jobId'] == jobId).length;

  Future<Application> create({
    required int jobId,
    required String jobTitle,
    required String firstName,
    required String lastName,
    required String email,
    required String message,
    required CvFile cv,
    required String createdAt,
  }) async {
    final application = Application(
      id: _col.nextId(),
      jobId: jobId,
      jobTitle: jobTitle,
      firstName: firstName,
      lastName: lastName,
      email: email,
      message: message,
      cv: cv,
      createdAt: createdAt,
    );
    _col.add(application.toJson());
    await _col.save();
    return application;
  }
}
