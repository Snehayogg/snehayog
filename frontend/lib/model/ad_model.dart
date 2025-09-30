import 'package:flutter/material.dart';

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

  final int? minAge;
  final int? maxAge;
  final String? gender; // 'male', 'female', 'other', null for all
  final List<String> locations; // Geographic targeting
  final List<String> interests; // Interest-based targeting
  final List<String> platforms; // 'android', 'ios', 'web'
  final String? deviceType; // 'mobile', 'tablet', 'desktop'
  final String? optimizationGoal; // 'clicks', 'impressions', 'conversions'
  final int? frequencyCap; // Max times shown to same user
  final String? timeZone; // Campaign timezone
  final Map<String, bool> dayParting; // Days of week targeting
  final double spend; // Total amount spent
  final int conversions; // Number of conversions
  final double conversionRate; // Conversion rate
  final double costPerConversion; // Cost per conversion
  final int reach; // Unique users reached
  final double frequency; // Average impressions per user

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
    // **NEW: Advanced targeting parameters**
    this.minAge,
    this.maxAge,
    this.gender,
    this.locations = const [],
    this.interests = const [],
    this.platforms = const [],
    this.deviceType,
    this.optimizationGoal,
    this.frequencyCap,
    this.timeZone,
    this.dayParting = const {},
    // **NEW: Performance tracking parameters**
    this.spend = 0.0,
    this.conversions = 0,
    this.conversionRate = 0.0,
    this.costPerConversion = 0.0,
    this.reach = 0,
    this.frequency = 0.0,
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
      // **NEW: Advanced targeting fields**
      minAge: json['minAge'],
      maxAge: json['maxAge'],
      gender: json['gender'],
      locations: List<String>.from(json['locations'] ?? []),
      interests: List<String>.from(json['interests'] ?? []),
      platforms: List<String>.from(json['platforms'] ?? []),
      deviceType: json['deviceType'],
      optimizationGoal: json['optimizationGoal'],
      frequencyCap: json['frequencyCap'],
      timeZone: json['timeZone'],
      dayParting: Map<String, bool>.from(json['dayParting'] ?? {}),
      // **NEW: Performance tracking fields**
      spend: (json['spend'] ?? 0.0).toDouble(),
      conversions: json['conversions'] ?? 0,
      conversionRate: (json['conversionRate'] ?? 0.0).toDouble(),
      costPerConversion: (json['costPerConversion'] ?? 0.0).toDouble(),
      reach: json['reach'] ?? 0,
      frequency: (json['frequency'] ?? 0.0).toDouble(),
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
      // **NEW: Advanced targeting fields**
      'minAge': minAge,
      'maxAge': maxAge,
      'gender': gender,
      'locations': locations,
      'interests': interests,
      'platforms': platforms,
      'deviceType': deviceType,
      'optimizationGoal': optimizationGoal,
      'frequencyCap': frequencyCap,
      'timeZone': timeZone,
      'dayParting': dayParting,
      // **NEW: Performance tracking fields**
      'spend': spend,
      'conversions': conversions,
      'conversionRate': conversionRate,
      'costPerConversion': costPerConversion,
      'reach': reach,
      'frequency': frequency,
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
    // **NEW: Advanced targeting parameters**
    int? minAge,
    int? maxAge,
    String? gender,
    List<String>? locations,
    List<String>? interests,
    List<String>? platforms,
    String? deviceType,
    String? optimizationGoal,
    int? frequencyCap,
    String? timeZone,
    Map<String, bool>? dayParting,
    // **NEW: Performance tracking parameters**
    double? spend,
    int? conversions,
    double? conversionRate,
    double? costPerConversion,
    int? reach,
    double? frequency,
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
      // **NEW: Advanced targeting fields**
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      gender: gender ?? this.gender,
      locations: locations ?? this.locations,
      interests: interests ?? this.interests,
      platforms: platforms ?? this.platforms,
      deviceType: deviceType ?? this.deviceType,
      optimizationGoal: optimizationGoal ?? this.optimizationGoal,
      frequencyCap: frequencyCap ?? this.frequencyCap,
      timeZone: timeZone ?? this.timeZone,
      dayParting: dayParting ?? this.dayParting,
      // **NEW: Performance tracking fields**
      spend: spend ?? this.spend,
      conversions: conversions ?? this.conversions,
      conversionRate: conversionRate ?? this.conversionRate,
      costPerConversion: costPerConversion ?? this.costPerConversion,
      reach: reach ?? this.reach,
      frequency: frequency ?? this.frequency,
    );
  }

  // **ENHANCED: Helper methods with new performance metrics**
  bool get isActive => status == 'active';
  bool get isDraft => status == 'draft';
  bool get isPaused => status == 'paused';
  bool get isCompleted => status == 'completed';

  // **ENHANCED: Performance metrics**
  double get cpm => impressions > 0 ? (spend / impressions) * 1000 : 0.0;
  double get cpc => clicks > 0 ? spend / clicks : 0.0;
  double get roas => spend > 0 && costPerConversion > 0
      ? (conversions * costPerConversion) / spend
      : 0.0; // Return on ad spend
  double get engagementRate =>
      impressions > 0 ? (clicks + conversions) / impressions : 0.0;

  // **NEW: Formatted display methods**
  String get formattedBudget => '₹${(budget / 100).toStringAsFixed(2)}';
  String get formattedSpend => '₹${spend.toStringAsFixed(2)}';
  String get formattedCtr => '${(ctr * 100).toStringAsFixed(2)}%';
  String get formattedConversionRate =>
      '${(conversionRate * 100).toStringAsFixed(2)}%';
  String get formattedCpm => '₹${cpm.toStringAsFixed(2)}';
  String get formattedCpc => '₹${cpc.toStringAsFixed(2)}';
  String get formattedRoas => '${roas.toStringAsFixed(2)}x';
  String get formattedFrequency => frequency.toStringAsFixed(1);

  // **NEW: Targeting summary methods**
  String get ageTargeting => minAge != null && maxAge != null
      ? '$minAge-$maxAge years'
      : minAge != null
          ? '$minAge+ years'
          : maxAge != null
              ? 'Up to $maxAge years'
              : 'All ages';

  String get genderTargeting => gender ?? 'All genders';

  String get locationSummary => locations.isEmpty
      ? 'All locations'
      : locations.length == 1
          ? locations.first
          : '${locations.first} +${locations.length - 1} more';

  String get interestSummary => interests.isEmpty
      ? 'All interests'
      : interests.length == 1
          ? interests.first
          : '${interests.first} +${interests.length - 1} more';

  String get platformSummary =>
      platforms.isEmpty ? 'All platforms' : platforms.join(', ');

  String get deviceSummary => deviceType ?? 'All devices';

  // **NEW: Campaign performance status**
  String get performanceStatus {
    if (isDraft) return 'Not started';
    if (spend == 0) return 'No spend';
    if (ctr > 0.05) return 'Excellent';
    if (ctr > 0.02) return 'Good';
    if (ctr > 0.01) return 'Average';
    return 'Needs optimization';
  }

  Color get performanceColor {
    switch (performanceStatus) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.lightGreen;
      case 'Average':
        return Colors.orange;
      case 'Needs optimization':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // **NEW: Budget pacing**
  double get budgetPacing {
    if (startDate == null || endDate == null) return 0.0;
    final totalDays = endDate!.difference(startDate!).inDays + 1;
    final daysPassed = DateTime.now().difference(startDate!).inDays + 1;
    final expectedSpend = (budget * daysPassed) / totalDays;
    return expectedSpend > 0 ? spend / expectedSpend : 0.0;
  }

  String get budgetPacingStatus {
    final pacing = budgetPacing;
    if (pacing > 1.2) return 'Over-pacing';
    if (pacing > 0.8) return 'On track';
    if (pacing > 0.5) return 'Under-pacing';
    return 'Significantly under-pacing';
  }
}
