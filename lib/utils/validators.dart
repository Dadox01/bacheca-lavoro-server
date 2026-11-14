import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';

final RegExp _emailRe = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
final RegExp _passwordRe = RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,72}$');
final RegExp _nameRe = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ' ]+$");

const String kMaxCvBytesLabel = '5 MB';

/// Contratti accettati per un annuncio.
const List<String> kContractTypes = [
  'Tempo indeterminato',
  'Tempo determinato',
  'Apprendistato',
  'Stage',
  'Part-time',
  'Freelance',
];

/// Data ISO-8601 UTC senza frazioni di secondo: 2026-11-01T10:00:00Z.
String formatIsoUtc(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// Legge il body come oggetto JSON; JSON non valido o non-oggetto -> FormatException (400).
Future<Map<String, dynamic>> readJsonObject(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) {
    throw const FormatException('Corpo della richiesta vuoto');
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map) {
    throw const FormatException('Il corpo deve essere un oggetto JSON');
  }
  return Map<String, dynamic>.from(decoded);
}

/// Stringa obbligatoria (dopo trim) con lunghezza tra min e max.
String _text(Map<String, dynamic> m, String key, String label, int max,
    {int min = 1}) {
  final v = m[key];
  if (v is! String) throw ApiException(422, '$label obbligatorio');
  final s = v.trim();
  if (s.length < min) {
    throw ApiException(
        422,
        min <= 1
            ? '$label obbligatorio'
            : '$label troppo corto (minimo $min caratteri)');
  }
  if (s.length > max) {
    throw ApiException(422, '$label troppo lungo (massimo $max caratteri)');
  }
  return s;
}

bool isValidEmail(String email) => _emailRe.hasMatch(email.trim());

// ---------------------------------------------------------------- Aziende

class RegisterInput {
  final String name;
  final String email;
  final String password;

  const RegisterInput(this.name, this.email, this.password);
}

RegisterInput validateRegister(Map<String, dynamic> b) {
  final name = _text(b, 'name', "Nome dell'azienda", 80, min: 2);
  final password = b['password'];
  if (password is! String || !_passwordRe.hasMatch(password)) {
    throw const ApiException(422,
        'Password non valida: da 8 a 72 caratteri con almeno una lettera e un numero');
  }
  final email = b['email'];
  if (email is! String || !isValidEmail(email)) {
    throw const ApiException(422, 'Email non valida');
  }
  return RegisterInput(name, email.trim(), password);
}

({String email, String password}) validateLogin(Map<String, dynamic> b) {
  final email = b['email'];
  final password = b['password'];
  if (email is! String ||
      password is! String ||
      email.trim().isEmpty ||
      password.isEmpty) {
    throw const ApiException(422, 'Email e password sono obbligatorie');
  }
  return (email: email.trim(), password: password);
}

// ---------------------------------------------------------------- Annunci

class JobInput {
  final String title;
  final String description;
  final String location;
  final String contract;
  final String? salary;

  const JobInput({
    required this.title,
    required this.description,
    required this.location,
    required this.contract,
    required this.salary,
  });
}

JobInput validateJob(Map<String, dynamic> b) {
  final title = _text(b, 'title', 'Titolo', 100, min: 3);
  final description = _text(b, 'description', 'Descrizione', 3000, min: 10);
  final location = _text(b, 'location', 'Sede', 80);

  final c = b['contract'];
  if (c is! String || !kContractTypes.contains(c.trim())) {
    throw ApiException(422,
        'Tipo di contratto non valido. Valori ammessi: ${kContractTypes.join(', ')}');
  }

  final rawSalary = b['salary'];
  String? salary;
  if (rawSalary == null) {
    salary = null;
  } else if (rawSalary is String) {
    final s = rawSalary.trim();
    if (s.isEmpty) {
      salary = null;
    } else if (s.length > 40) {
      throw const ApiException(
          422, 'Retribuzione troppo lunga (massimo 40 caratteri)');
    } else {
      salary = s;
    }
  } else {
    throw const ApiException(422, 'Retribuzione non valida');
  }

  return JobInput(
    title: title,
    description: description,
    location: location,
    contract: c.trim(),
    salary: salary,
  );
}

// ---------------------------------------------------------------- Candidature

class ApplicationInput {
  final String firstName;
  final String lastName;
  final String email;
  final String message;

  const ApplicationInput({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.message,
  });
}

/// Campi testuali della candidatura (il curriculum è un file: vedi CvStorage).
ApplicationInput validateApplication(Map<String, String> fields) {
  final firstName = _text(fields, 'firstName', 'Nome', 40, min: 2);
  if (!_nameRe.hasMatch(firstName)) {
    throw const ApiException(
        422, "Il nome può contenere solo lettere, spazi e apostrofi");
  }
  final lastName = _text(fields, 'lastName', 'Cognome', 40, min: 2);
  if (!_nameRe.hasMatch(lastName)) {
    throw const ApiException(
        422, 'Il cognome può contenere solo lettere, spazi e apostrofi');
  }
  final email = fields['email'];
  if (email is! String || !isValidEmail(email)) {
    throw const ApiException(422, 'Email non valida');
  }
  final message = (fields['message'] ?? '').trim();
  if (message.length > 1000) {
    throw const ApiException(
        422, 'Lettera di presentazione troppo lunga (massimo 1000 caratteri)');
  }
  return ApplicationInput(
    firstName: firstName,
    lastName: lastName,
    email: email.trim(),
    message: message,
  );
}

/// Nome file "pulito": solo l'ultimo segmento, senza caratteri di controllo.
String sanitizeFileName(String raw) {
  var name = raw.replaceAll('\\', '/');
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F"]'), '').trim();
  if (name.isEmpty || name == '.' || name == '..') return 'curriculum.pdf';
  if (name.length > 120) {
    name = name.substring(name.length - 120);
  }
  return name;
}

/// Un PDF inizia con "%PDF-" (eventualmente dopo pochi byte di BOM/spazzatura).
bool looksLikePdf(Uint8List bytes) {
  if (bytes.length < 5) return false;
  final head = String.fromCharCodes(bytes.take(1024));
  return head.contains('%PDF-');
}
