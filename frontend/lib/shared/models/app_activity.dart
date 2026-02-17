
enum ActivityType {
  videoPlayback,
  videoUpload,
  adCreation,
  none,
}

class AppActivity {
  final ActivityType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  AppActivity({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'data': data,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory AppActivity.fromJson(Map<String, dynamic> json) {
    return AppActivity(
      type: ActivityType.values[json['type'] as int],
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }

  bool get isExpired {
    // Expire after 30 minutes
    return DateTime.now().difference(timestamp).inMinutes > 30;
  }

  @override
  String toString() => 'AppActivity(type: $type, timestamp: $timestamp)';
}
