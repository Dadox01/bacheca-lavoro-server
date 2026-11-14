class Job {
  final int id;
  final int companyId;
  final String companyName;
  final String title;
  final String description;
  final String location;
  final String contract;
  final String? salary;
  final String createdAt;

  const Job({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.title,
    required this.description,
    required this.location,
    required this.contract,
    required this.salary,
    required this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as int,
        companyId: j['companyId'] as int,
        companyName: j['companyName'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        location: (j['location'] as String?) ?? '',
        contract: (j['contract'] as String?) ?? '',
        salary: j['salary'] as String?,
        createdAt: j['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'companyName': companyName,
        'title': title,
        'description': description,
        'location': location,
        'contract': contract,
        'salary': salary,
        'createdAt': createdAt,
      };

  /// JSON pubblico: la bacheca non espone quanti candidati hanno risposto.
  Map<String, dynamic> toPublicJson({int? applicationsCount}) => {
        'id': id,
        'companyId': companyId,
        'companyName': companyName,
        'title': title,
        'description': description,
        'location': location,
        'contract': contract,
        'salary': salary,
        'createdAt': createdAt,
        if (applicationsCount != null) 'applicationsCount': applicationsCount,
      };
}
