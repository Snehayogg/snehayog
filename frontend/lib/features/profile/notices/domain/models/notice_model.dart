class NoticeModel {
  final String id;
  final String title;
  final String type;
  final DateTime? firstSeenAt;
  final DateTime createdAt;

  NoticeModel({
    required this.id,
    required this.title,
    required this.type,
    this.firstSeenAt,
    required this.createdAt,
  });

  factory NoticeModel.fromJson(Map<String, dynamic> json) {
    return NoticeModel(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'notice',
      firstSeenAt: json['firstSeenAt'] != null 
          ? DateTime.parse(json['firstSeenAt']) 
          : null,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  bool get isExpired {
    if (firstSeenAt == null) return false;
    final now = DateTime.now().toUtc();
    return now.difference(firstSeenAt!.toUtc()).inMinutes >= 60;
  }

  bool get isWarning => type == 'warning';
}
