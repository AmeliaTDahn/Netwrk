import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../components/video_player_widget.dart';
import '../../models/video_model.dart';

class VideoPlayerScreen extends StatelessWidget {
  final String videoId;
  final String videoUrl;
  final String username;
  final String description;
  final String thumbnailUrl;
  final String displayName;
  final String? photoUrl;
  final String userId;

  const VideoPlayerScreen({
    Key? key,
    required this.videoId,
    required this.videoUrl,
    required this.username,
    required this.description,
    required this.thumbnailUrl,
    required this.displayName,
    this.photoUrl,
    required this.userId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final video = VideoModel(
      id: videoId,
      url: videoUrl,
      thumbnailUrl: thumbnailUrl,
      description: description,
      title: description, // You might want to add a separate title field
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
      userId: userId,
      category: '', // Add if needed
      createdAt: DateTime.now(), // Add if needed
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video'),
      ),
      body: VideoPlayerWidget(
        video: video,
      ),
    );
  }
} 