import '../models/job.dart';
import 'json_store.dart';

class JobDao {
  final JsonCollection _col;

  JobDao(this._col);

  Future<void> load() => _col.load();

  bool get needsSeed => !_col.existedOnDisk;

  /// Tutti gli annunci, dal più recente al più vecchio.
  List<Job> all() {
    final list = _col.all().map(Job.fromJson).toList();
    list.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return list;
  }

  Job? findById(int id) {
    for (final m in _col.all()) {
      if (m['id'] == id) return Job.fromJson(m);
    }
    return null;
  }

  List<Job> byCompany(int companyId) =>
      all().where((j) => j.companyId == companyId).toList();

  /// Ricerca pubblica su titolo, azienda, sede e contratto.
  List<Job> search({String? q}) {
    final query = q?.trim().toLowerCase();
    if (query == null || query.isEmpty) return all();
    return all().where((j) {
      return j.title.toLowerCase().contains(query) ||
          j.companyName.toLowerCase().contains(query) ||
          j.location.toLowerCase().contains(query) ||
          j.contract.toLowerCase().contains(query) ||
          j.description.toLowerCase().contains(query);
    }).toList();
  }

  Future<Job> create({
    required int companyId,
    required String companyName,
    required String title,
    required String description,
    required String location,
    required String contract,
    String? salary,
    required String createdAt,
  }) async {
    final job = Job(
      id: _col.nextId(),
      companyId: companyId,
      companyName: companyName,
      title: title,
      description: description,
      location: location,
      contract: contract,
      salary: salary,
      createdAt: createdAt,
    );
    _col.add(job.toJson());
    await _col.save();
    return job;
  }

  /// Rimozione fisica dell'annuncio (usata solo dai test e dal comando di reset).
  Future<bool> delete(int id) async {
    final removed = _col.remove(id);
    if (removed) await _col.save();
    return removed;
  }
}
