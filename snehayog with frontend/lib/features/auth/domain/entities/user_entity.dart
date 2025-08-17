class UserEntity {
  final String id;
  final String name;
  final String email;
  final String profilePic;
  final String googleId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.profilePic,
    required this.googleId,
    this.createdAt,
    this.updatedAt,
  });

  // Copy with method for immutable updates
  UserEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? profilePic,
    String? googleId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profilePic: profilePic ?? this.profilePic,
      googleId: googleId ?? this.googleId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profilePic': profilePic,
      'googleId': googleId,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // Create from JSON
  factory UserEntity.fromJson(Map<String, dynamic> json) {
    return UserEntity(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      profilePic: json['profilePic'] ?? '',
      googleId: json['googleId'] ?? '',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : null,
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : null,
    );
  }

  // Equality operator
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserEntity &&
        other.id == id &&
        other.googleId == googleId;
  }

  // Hash code
  @override
  int get hashCode {
    return id.hashCode ^ googleId.hashCode;
  }

  // String representation
  @override
  String toString() {
    return 'UserEntity(id: $id, name: $name, email: $email, googleId: $googleId)';
  }
}
