import 'package:flutter/material.dart';
import '../models/video_model.dart';

class VideoInteractionOverlay extends StatelessWidget {
  final Video video;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;

  const VideoInteractionOverlay({
    super.key,
    required this.video,
    required this.onLike,
    required this.onComment,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        children: [
          _buildInteractionButton(
            icon: video.isLiked ? Icons.favorite : Icons.favorite_border,
            label: video.likes.toString(),
            onTap: onLike,
            isActive: video.isLiked,
          ),
          const SizedBox(height: 20),
          _buildInteractionButton(
            icon: Icons.comment,
            label: video.comments.toString(),
            onTap: onComment,
          ),
          const SizedBox(height: 20),
          _buildInteractionButton(
            icon: video.isSaved ? Icons.bookmark : Icons.bookmark_border,
            label: video.saves.toString(),
            onTap: onSave,
            isActive: video.isSaved,
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF2196F3) : Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
} 