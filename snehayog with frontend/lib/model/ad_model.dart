class AdModel {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final String? videoUrl;
  final String? link;
  final String adType; // 'banner', 'interstitial', 'rewarded', 'native'
  final String status; // 'draft', 'active', 'paused', 'completed'
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final int budget;
  final int impressions;
  final int clicks;
  final double ctr; // Click-through rate
  final String targetAudience;
  final List<String> targetKeywords;
  final String uploaderId;
  final String uploaderName;
  final String? uploaderProfilePic;

  AdModel({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    this.videoUrl,
    this.link,
    required this.adType,
    required this.status,
    required this.createdAt,
    this.startDate,
    this.endDate,
    required this.budget,
    required this.impressions,
    required this.clicks,
    required this.ctr,
    required this.targetAudience,
    required this.targetKeywords,
    required this.uploaderId,
    required this.uploaderName,
    this.uploaderProfilePic,
  });

  factory AdModel.fromJson(Map<String, dynamic> json) {
    return AdModel(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'],
      videoUrl: json['videoUrl'],
      link: json['link'],
      adType: json['adType'] ?? 'banner',
      status: json['status'] ?? 'draft',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      startDate:
          json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      budget: json['budget'] ?? 0,
      impressions: json['impressions'] ?? 0,
      clicks: json['clicks'] ?? 0,
      ctr: (json['ctr'] ?? 0.0).toDouble(),
      targetAudience: json['targetAudience'] ?? 'all',
      targetKeywords: List<String>.from(json['targetKeywords'] ?? []),
      uploaderId: json['uploaderId'] ?? '',
      uploaderName: json['uploaderName'] ?? '',
      uploaderProfilePic: json['uploaderProfilePic'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'link': link,
      'adType': adType,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'budget': budget,
      'impressions': impressions,
      'clicks': clicks,
      'ctr': ctr,
      'targetAudience': targetAudience,
      'targetKeywords': targetKeywords,
      'uploaderId': uploaderId,
      'uploaderName': uploaderName,
      'uploaderProfilePic': uploaderProfilePic,
    };
  }

  AdModel copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    String? videoUrl,
    String? link,
    String? adType,
    String? status,
    DateTime? createdAt,
    DateTime? startDate,
    DateTime? endDate,
    int? budget,
    int? impressions,
    int? clicks,
    double? ctr,
    String? targetAudience,
    List<String>? targetKeywords,
    String? uploaderId,
    String? uploaderName,
    String? uploaderProfilePic,
  }) {
    return AdModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      link: link ?? this.link,
      adType: adType ?? this.adType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      budget: budget ?? this.budget,
      impressions: impressions ?? this.impressions,
      clicks: clicks ?? this.clicks,
      ctr: ctr ?? this.ctr,
      targetAudience: targetAudience ?? this.targetAudience,
      targetKeywords: targetKeywords ?? this.targetKeywords,
      uploaderId: uploaderId ?? this.uploaderId,
      uploaderName: uploaderName ?? this.uploaderName,
      uploaderProfilePic: uploaderProfilePic ?? this.uploaderProfilePic,
    );
  }

  // Helper methods
  bool get isActive => status == 'active';
  bool get isDraft => status == 'draft';
  bool get isPaused => status == 'paused';
  bool get isCompleted => status == 'completed';

  double get cpm => impressions > 0 ? (budget / impressions) * 1000 : 0.0;
  double get cpc => clicks > 0 ? budget / clicks : 0.0;

  String get formattedBudget => '\$${budget.toStringAsFixed(2)}';
  String get formattedCtr => '${(ctr * 100).toStringAsFixed(2)}%';
}
