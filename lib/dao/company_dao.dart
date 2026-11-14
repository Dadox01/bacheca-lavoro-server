import '../models/company.dart';
import 'json_store.dart';

class CompanyDao {
  final JsonCollection _col;

  CompanyDao(this._col);

  Future<void> load() => _col.load();

  List<Company> all() => _col.all().map(Company.fromJson).toList();

  Company? findById(int id) {
    for (final m in _col.all()) {
      if (m['id'] == id) return Company.fromJson(m);
    }
    return null;
  }

  /// Le email sono univoche a prescindere da maiuscole/minuscole.
  Company? findByEmail(String email) {
    final target = email.trim().toLowerCase();
    for (final m in _col.all()) {
      if ((m['email'] as String).toLowerCase() == target) {
        return Company.fromJson(m);
      }
    }
    return null;
  }

  Future<Company> create({
    required String name,
    required String email,
    required String passwordHash,
    required String salt,
    required String createdAt,
  }) async {
    final company = Company(
      id: _col.nextId(),
      name: name,
      email: email,
      passwordHash: passwordHash,
      salt: salt,
      createdAt: createdAt,
    );
    _col.add(company.toJson());
    await _col.save();
    return company;
  }
}
