class CarouselItem {
  final String id;
  final String type; // 'video' or 'ad'
  final String? videoUrl;
  final String? imageUrl;
  final String? title;
  final String? description;
  final String? adLink;
  final String? adTitle;
  final String? adDescription;

  CarouselItem({
    required this.id,
    required this.type,
    this.videoUrl,
    this.imageUrl,
    this.title,
    this.description,
    this.adLink,
    this.adTitle,
    this.adDescription,
  });

  factory CarouselItem.fromJson(Map<String, dynamic> json) {
    return CarouselItem(
      id: json['id'],
      type: json['type'],
      videoUrl: json['videoUrl'],
      imageUrl: json['imageUrl'],
      title: json['title'],
      description: json['description'],
      adLink: json['adLink'],
      adTitle: json['adTitle'],
      adDescription: json['adDescription'],
    );
  }
}
