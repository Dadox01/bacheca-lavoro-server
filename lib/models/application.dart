/// Metadati del curriculum caricato sul server.
class CvFile {
  final String originalName;
  final String storedName;
  final int size;
  final String uploadedAt;

  const CvFile({
    required this.originalName,
    required this.storedName,
    required this.size,
    required this.uploadedAt,
  });

  factory CvFile.fromJson(Map<String, dynamic> j) => CvFile(
        originalName: j['originalName'] as String,
        storedName: j['storedName'] as String,
        size: (j['size'] as num).toInt(),
        uploadedAt: j['uploadedAt'] as String,
      );

  Map<String, dynamic> toJson() => {
        'originalName': originalName,
        'storedName': storedName,
        'size': size,
        'uploadedAt': uploadedAt,
      };
}

class Application {
  final int id;
  final int jobId;
  final String jobTitle;
  final String firstName;
  final String lastName;
  final String email;
  final String message;
  final CvFile cv;
  final String createdAt;

  const Application({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.message,
    required this.cv,
    required this.createdAt,
  });

  factory Application.fromJson(Map<String, dynamic> j) => Application(
        id: j['id'] as int,
        jobId: j['jobId'] as int,
        jobTitle: j['jobTitle'] as String,
        firstName: j['firstName'] as String,
        lastName: j['lastName'] as String,
        email: j['email'] as String,
        message: (j['message'] as String?) ?? '',
        cv: CvFile.fromJson(Map<String, dynamic>.from(j['cv'] as Map)),
        createdAt: j['createdAt'] as String,
      );

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'jobTitle': jobTitle,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'message': message,
        'cv': cv.toJson(),
        'createdAt': createdAt,
      };
}
