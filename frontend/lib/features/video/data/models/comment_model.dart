import '../../domain/entities/video_entity.dart';

/// Data model for video comments - extends the domain entity
/// This model handles JSON serialization/deserialization
class CommentModel extends CommentEntity {
  const CommentModel({
    required super.id,
    required super.text,
    required super.userId,
    required super.userName,
    required super.createdAt,
  });


  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['_id'] ?? json['id'] ?? '',
      text: json['text'] ?? '',
      userId: json['userId'] ?? json['googleId'] ?? '',
      userName: json['userName'] ?? json['name'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  /// Converts the CommentModel to JSON
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'text': text,
      'userId': userId,
      'userName': userName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Creates a copy of this model with updated values
  @override
  CommentModel copyWith({
    String? id,
    String? text,
    String? userId,
    String? userName,
    DateTime? createdAt,
  }) {
    return CommentModel(
      id: id ?? this.id,
      text: text ?? this.text,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Converts the domain entity to a data model
  factory CommentModel.fromEntity(CommentEntity entity) {
    return CommentModel(
      id: entity.id,
      text: entity.text,
      userId: entity.userId,
      userName: entity.userName,
      createdAt: entity.createdAt,
    );
  }

  /// Converts the data model to a domain entity
  CommentEntity toEntity() {
    return CommentEntity(
      id: id,
      text: text,
      userId: userId,
      userName: userName,
      createdAt: createdAt,
    );
  }
}
