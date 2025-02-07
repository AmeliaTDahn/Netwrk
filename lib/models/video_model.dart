enum VideoCategory {
  business,
  employee,
}

class Video {
  final String id;
  final String url;
  final String userId;
  final String description;
  final String thumbnailUrl;
  int likes;
  int comments;
  int saves;
  final DateTime createdAt;
  bool isLiked;
  bool isSaved;
  final VideoCategory category;

  Video({
    required this.id,
    required this.url,
    required this.userId,
    required this.description,
    required this.thumbnailUrl,
    this.likes = 0,
    this.comments = 0,
    this.saves = 0,
    required this.createdAt,
    this.isLiked = false,
    this.isSaved = false,
    required this.category,
  });
}

// Separate lists for business and employee videos
final List<Video> businessVideos = [
  Video(
    id: '1',
    url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    userId: 'user1',
    description: 'Looking for talented developers',
    thumbnailUrl: 'https://picsum.photos/seed/1/400/600',
    likes: 120,
    comments: 45,
    saves: 20,
    createdAt: DateTime.now(),
    category: VideoCategory.business,
  ),
  Video(
    id: '3',
    url: 'https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    userId: 'user3',
    description: 'Hiring Senior Backend Engineers',
    thumbnailUrl: 'https://picsum.photos/seed/3/400/600',
    likes: 230,
    comments: 56,
    saves: 42,
    createdAt: DateTime.now(),
    category: VideoCategory.business,
  ),
  Video(
    id: '4',
    url: 'https://storage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    userId: 'user4',
    description: 'Tech startup seeking UI/UX designers',
    thumbnailUrl: 'https://picsum.photos/seed/4/400/600',
    likes: 180,
    comments: 38,
    saves: 25,
    createdAt: DateTime.now(),
    category: VideoCategory.business,
  ),
];

final List<Video> employeeVideos = [
  Video(
    id: '2',
    url: 'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    userId: 'user2',
    description: 'Senior Flutter Developer | Open to work',
    thumbnailUrl: 'https://picsum.photos/seed/2/400/600',
    likes: 85,
    comments: 32,
    saves: 15,
    createdAt: DateTime.now(),
    category: VideoCategory.employee,
  ),
  Video(
    id: '5',
    url: 'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    userId: 'user5',
    description: 'Full Stack Developer | 5+ years experience',
    thumbnailUrl: 'https://picsum.photos/seed/5/400/600',
    likes: 156,
    comments: 42,
    saves: 28,
    createdAt: DateTime.now(),
    category: VideoCategory.employee,
  ),
  Video(
    id: '6',
    url: 'https://storage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    userId: 'user6',
    description: 'Product Manager | AI/ML focus',
    thumbnailUrl: 'https://picsum.photos/seed/6/400/600',
    likes: 198,
    comments: 47,
    saves: 35,
    createdAt: DateTime.now(),
    category: VideoCategory.employee,
  ),
];

class VideoModel {
  final String id;
  final String url;
  final String title;
  final String userId;
  final String thumbnailUrl;
  final String description;
  final String username;
  final String displayName;
  final String? photoUrl;
  final String category;
  final DateTime createdAt;
  final Map<String, dynamic> profiles;

  VideoModel({
    required this.id,
    required this.url,
    required this.title,
    required this.userId,
    required this.thumbnailUrl,
    required this.description,
    required this.username,
    required this.displayName,
    this.photoUrl,
    required this.category,
    required this.createdAt,
    required this.profiles,
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id'],
      url: json['url'],
      title: json['title'] ?? '',
      userId: json['user_id'],
      thumbnailUrl: json['thumbnail_url'],
      description: json['description'] ?? '',
      username: json['profiles']['username'],
      displayName: json['profiles']['display_name'],
      photoUrl: json['profiles']['photo_url'],
      category: json['category'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      profiles: json['profiles'] ?? {},
    );
  }
} 