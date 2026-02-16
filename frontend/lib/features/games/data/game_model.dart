
class GameModel {
  final String id;
  final String title;
  final String description;
  final String gameUrl;
  final String coverImageUrl;
  final String publisher;

  final int? width;
  final int? height;
  final num? qualityScore;
  final String? orientation;
  final String? bannerImage;

  final String? status;
  final int views;
  final int plays;
  final int totalTimeSpent;
  final String? thumbnailUrl;

  GameModel({
    required this.id,
    required this.title,
    required this.description,
    required this.gameUrl,
    required this.coverImageUrl,
    required this.publisher,
    this.width,
    this.height,
    this.qualityScore,
    this.orientation,
    this.bannerImage,
    this.status = 'active',
    this.views = 0,
    this.plays = 0,
    this.totalTimeSpent = 0,
    this.thumbnailUrl,
  });

  factory GameModel.fromJson(Map<String, dynamic> json) {
    return GameModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      gameUrl: json['url'] ?? '',
      coverImageUrl: json['assets']?['cover'] ?? '',
      publisher: json['publisher'] ?? '',
      width: json['width'],
      height: json['height'],
      qualityScore: json['quality_score'],
      orientation: json['orientation'],
      bannerImage: json['banner_image'],
      plays: json['plays'] ?? 0,
      totalTimeSpent: json['totalTimeSpent'] ?? 0,
    );
  }

  factory GameModel.fromJsonVayu(Map<String, dynamic> json) {
    return GameModel(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      gameUrl: json['gameUrl'] ?? '',
      coverImageUrl: json['thumbnailUrl'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      publisher: json['developer'] != null && json['developer'] is Map 
          ? json['developer']['name'] ?? 'Vayu Developer'
          : 'Vayu Creator',
      orientation: json['orientation'],
      status: json['status'] ?? 'active',
      views: json['views'] ?? 0,
      plays: json['plays'] ?? 0,
      totalTimeSpent: json['totalTimeSpent'] ?? 0,
      width: json['orientation'] == 'landscape' ? 1280 : 720,
      height: json['orientation'] == 'landscape' ? 720 : 1280,
    );
  }
}
