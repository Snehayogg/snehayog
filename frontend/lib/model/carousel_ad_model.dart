
class CarouselAdModel {
  final String id;
  final String campaignId;
  final String advertiserName;
  final String advertiserProfilePic;
  final List<CarouselSlide> slides;
  final String callToActionLabel;
  final String callToActionUrl;
  final bool isActive;
  final DateTime createdAt;
  final int impressions;
  final int clicks;

  CarouselAdModel({
    required this.id,
    required this.campaignId,
    required this.advertiserName,
    required this.advertiserProfilePic,
    required this.slides,
    required this.callToActionLabel,
    required this.callToActionUrl,
    required this.isActive,
    required this.createdAt,
    this.impressions = 0,
    this.clicks = 0,
  });

  factory CarouselAdModel.fromJson(Map<String, dynamic> json) {
    return CarouselAdModel(
      id: json['_id'] ?? json['id'] ?? '',
      campaignId: json['campaignId'] ?? '',
      advertiserName: json['advertiserName'] ?? 'Advertiser',
      advertiserProfilePic: json['advertiserProfilePic'] ?? '',
      slides: (json['slides'] as List<dynamic>?)
              ?.map((slide) => CarouselSlide.fromJson(slide))
              .toList() ??
          [],
      callToActionLabel: json['callToActionLabel'] ?? 'Learn More',
      callToActionUrl: json['callToActionUrl'] ?? '',
      isActive: json['isActive'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      impressions: json['impressions'] ?? 0,
      clicks: json['clicks'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'campaignId': campaignId,
      'advertiserName': advertiserName,
      'advertiserProfilePic': advertiserProfilePic,
      'slides': slides.map((slide) => slide.toJson()).toList(),
      'callToActionLabel': callToActionLabel,
      'callToActionUrl': callToActionUrl,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'impressions': impressions,
      'clicks': clicks,
    };
  }

  CarouselAdModel copyWith({
    String? id,
    String? campaignId,
    String? advertiserName,
    String? advertiserProfilePic,
    List<CarouselSlide>? slides,
    String? callToActionLabel,
    String? callToActionUrl,
    bool? isActive,
    DateTime? createdAt,
    int? impressions,
    int? clicks,
  }) {
    return CarouselAdModel(
      id: id ?? this.id,
      campaignId: campaignId ?? this.campaignId,
      advertiserName: advertiserName ?? this.advertiserName,
      advertiserProfilePic: advertiserProfilePic ?? this.advertiserProfilePic,
      slides: slides ?? this.slides,
      callToActionLabel: callToActionLabel ?? this.callToActionLabel,
      callToActionUrl: callToActionUrl ?? this.callToActionUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      impressions: impressions ?? this.impressions,
      clicks: clicks ?? this.clicks,
    );
  }
}

class CarouselSlide {
  final String id;
  final String mediaUrl;
  final String? thumbnailUrl;
  final String? title;
  final String? description;
  final String mediaType; // 'image' or 'video'
  final int? durationSec;
  final String aspectRatio;

  CarouselSlide({
    required this.id,
    required this.mediaUrl,
    this.thumbnailUrl,
    this.title,
    this.description,
    required this.mediaType,
    this.durationSec,
    required this.aspectRatio,
  });

  factory CarouselSlide.fromJson(Map<String, dynamic> json) {
    return CarouselSlide(
      id: json['_id'] ?? json['id'] ?? '',
      mediaUrl: json['mediaUrl'] ?? json['cloudinaryUrl'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail'],
      title: json['title'],
      description: json['description'],
      mediaType: json['mediaType'] ?? json['type'] ?? 'image',
      durationSec: json['durationSec'] ?? json['durationSec'],
      aspectRatio: json['aspectRatio'] ?? '9:16',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'title': title,
      'description': description,
      'mediaType': mediaType,
      'durationSec': durationSec,
      'aspectRatio': aspectRatio,
    };
  }

  CarouselSlide copyWith({
    String? id,
    String? mediaUrl,
    String? thumbnailUrl,
    String? title,
    String? description,
    String? mediaType,
    int? durationSec,
    String? aspectRatio,
  }) {
    return CarouselSlide(
      id: id ?? this.id,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      mediaType: mediaType ?? this.mediaType,
      durationSec: durationSec ?? this.durationSec,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}
