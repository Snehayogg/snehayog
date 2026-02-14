
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
    );
  }

  factory GameModel.fromJsonGamePix(Map<String, dynamic> json) {
    return GameModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      gameUrl: json['url'] ?? '',
      coverImageUrl: json['image'] ?? '',
      publisher: 'GamePix',
      width: json['width'],
      height: json['height'],
      qualityScore: json['quality_score'],
      orientation: json['orientation'],
      bannerImage: json['banner_image'],
    );
  }

  factory GameModel.fromJsonVayu(Map<String, dynamic> json) {
    return GameModel(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      gameUrl: json['gameUrl'] ?? '',
      coverImageUrl: json['thumbnailUrl'] ?? '',
      publisher: json['developer'] != null && json['developer'] is Map 
          ? json['developer']['name'] ?? 'Vayu Developer'
          : 'Vayu Creator',
      orientation: json['orientation'],
      // Map other fields if necessary
      width: json['orientation'] == 'landscape' ? 1280 : 720,
      height: json['orientation'] == 'landscape' ? 720 : 1280,
    );
  }
}
