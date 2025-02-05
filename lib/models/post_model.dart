class Post {
  final String id;
  final String userId;
  final String username;
  final String content;
  final String? imageUrl;
  final int likes;
  final DateTime timestamp;

  Post({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    this.imageUrl,
    required this.likes,
    required this.timestamp,
  });
} 