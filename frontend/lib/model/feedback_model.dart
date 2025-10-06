class FeedbackModel {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String feedbackType;
  final String message;
  final int rating;
  final DateTime createdAt;
  final String? deviceInfo;
  final String? appVersion;
  final bool isResolved;

  FeedbackModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.feedbackType,
    required this.message,
    required this.rating,
    required this.createdAt,
    this.deviceInfo,
    this.appVersion,
    this.isResolved = false,
  });

  factory FeedbackModel.fromJson(Map<String, dynamic> json) {
    return FeedbackModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      userId:
          json['userId']?.toString() ?? json['user']?['_id']?.toString() ?? '',
      userName: json['userName']?.toString() ??
          json['user']?['name']?.toString() ??
          '',
      userEmail: json['userEmail']?.toString() ??
          json['user']?['email']?.toString() ??
          '',
      feedbackType: json['feedbackType']?.toString() ?? 'general',
      message: json['message']?.toString() ?? '',
      rating: (json['rating'] is int)
          ? json['rating']
          : int.tryParse(json['rating']?.toString() ?? '5') ?? 5,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      deviceInfo: json['deviceInfo']?.toString(),
      appVersion: json['appVersion']?.toString(),
      isResolved: json['isResolved'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'feedbackType': feedbackType,
      'message': message,
      'rating': rating,
      'createdAt': createdAt.toIso8601String(),
      'deviceInfo': deviceInfo,
      'appVersion': appVersion,
      'isResolved': isResolved,
    };
  }

  FeedbackModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userEmail,
    String? feedbackType,
    String? message,
    int? rating,
    DateTime? createdAt,
    String? deviceInfo,
    String? appVersion,
    bool? isResolved,
  }) {
    return FeedbackModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      feedbackType: feedbackType ?? this.feedbackType,
      message: message ?? this.message,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      appVersion: appVersion ?? this.appVersion,
      isResolved: isResolved ?? this.isResolved,
    );
  }
}
