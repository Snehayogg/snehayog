class VideoModel {
  final String videoName;
  final String videoUrl;
  final int likes;
  final int views;
  final String description;
  final String uploader;
  final DateTime uploadedAt;

  VideoModel({
    required this.videoName,
    required this.videoUrl,
    required this.likes,
    required this.views,
    required this.description,
    required this.uploader,
    required this.uploadedAt,
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      videoName: json['videoName'],
      videoUrl: json['videoUrl'],
      likes: json['likes'] ?? 0,
      views: json['views'] ?? 0,
      description: json['description'] ?? '',
      uploader: json['uploader'],
      uploadedAt: DateTime.parse(json['uploadedAt']),
    );
  }
}
