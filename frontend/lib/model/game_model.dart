
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
}
