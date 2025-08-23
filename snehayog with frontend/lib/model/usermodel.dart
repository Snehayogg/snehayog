class UserModel {
  final String id;
  final String name;
  final String email;
  final String profilePic;
  final List<String> videos;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final DateTime? createdAt;
  final String? bio;
  final String? location;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.profilePic,
    required this.videos,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.createdAt,
    this.bio,
    this.location,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? json['id'] ?? json['googleId'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      profilePic: json['profilePic'] ?? '',
      videos: List<String>.from(json['videos'] ?? []),
      followersCount: json['followersCount'] ?? json['followers'] ?? 0,
      followingCount: json['followingCount'] ?? json['following'] ?? 0,
      isFollowing: json['isFollowing'] ?? false,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : null,
      bio: json['bio'],
      location: json['location'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profilePic': profilePic,
      'videos': videos,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'isFollowing': isFollowing,
      'createdAt': createdAt?.toIso8601String(),
      'bio': bio,
      'location': location,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? profilePic,
    List<String>? videos,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    DateTime? createdAt,
    String? bio,
    String? location,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profilePic: profilePic ?? this.profilePic,
      videos: videos ?? this.videos,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      createdAt: createdAt ?? this.createdAt,
      bio: bio ?? this.bio,
      location: location ?? this.location,
    );
  }
}
