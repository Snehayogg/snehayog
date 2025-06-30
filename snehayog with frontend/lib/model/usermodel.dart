class UserModel {
  final String name;
  final String email;
  final String profilePic;
  final List<String> videos; // List of video URLs

  UserModel({
    required this.name,
    required this.email,
    required this.profilePic,
    required this.videos,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      name: json['name'],
      email: json['email'],
      profilePic: json['profilePic'],
      videos: List<String>.from(json['videos'] ?? []),
    );
  }
}
