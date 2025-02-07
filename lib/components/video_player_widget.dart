import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:go_router/go_router.dart';
import '../models/video_model.dart';
import '../core/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'save_button.dart';
import '../screens/comments/comments_screen.dart';
import 'comments_section.dart';
import 'dart:async';
import '../screens/profile/profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/videos_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

const Color primaryBlue = Color(0xFF2196F3);    // Light blue
const Color secondaryBlue = Color(0xFF1565C0);  // Dark blue

class VideoPlayerWidget extends ConsumerStatefulWidget {
  final VideoModel video;
  final bool autoPlay;
  
  const VideoPlayerWidget({
    super.key, 
    required this.video,
    this.autoPlay = false,
  });

  @override
  ConsumerState<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  VideoPlayerController? _nextController;
  bool _isInitialized = false;
  bool _showControls = false;
  bool _isPlaying = false;
  Timer? _hideControlsTimer;
  double _currentPosition = 0.0;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isTitleExpanded = false;
  bool _isDescriptionExpanded = false;
  bool _isPending = false;
  String? _thumbnailPath;

  final ButtonStyle _buttonStyle = ElevatedButton.styleFrom(
    minimumSize: const Size(100, 36), // Set minimum width and height
    padding: const EdgeInsets.symmetric(horizontal: 16), // Add horizontal padding
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
  );

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
    _initializeVideo();
    _checkConnectionStatus();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay) {
        _controller.play();
      } else {
        _controller.pause();
      }
    }
  }

  Future<void> _generateThumbnail() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.video.url,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        quality: 75,
      );
      
      if (mounted) {
        setState(() {
          _thumbnailPath = thumbnailPath;
        });
      }
    } catch (e) {
      print('Error generating thumbnail: $e');
    }
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.video.url));
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isPlaying = widget.autoPlay;
        });
        if (widget.autoPlay) {
          _controller.play();
        }
      }
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        _isPlaying = _controller.value.isPlaying;
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      _isPlaying = !_controller.value.isPlaying;
    });
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Check for existing connection
      final connectionResponse = await supabase
          .from('connections')
          .select()
          .or('and(requester_id.eq.${currentUserId},receiver_id.eq.${widget.video.userId}),and(requester_id.eq.${widget.video.userId},receiver_id.eq.${currentUserId})')
          .single();

      if (mounted) {
        setState(() {
          _isConnected = connectionResponse['status'] == 'accepted';
          _isPending = connectionResponse['status'] == 'pending';
        });
      }
    } catch (e) {
      // No connection found
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isPending = false;
        });
      }
    }
  }

  Future<void> _handleConnect() async {
    try {
      setState(() => _isLoading = true);
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Create connection request
      await supabase.from('connections').insert({
        'requester_id': currentUserId,
        'receiver_id': widget.video.userId,
        'status': 'pending'
      });

      setState(() {
        _isPending = true;
        _isLoading = false;
      });

      if (_isConnected) {
        // Navigate to chat
        final response = await supabase
            .from('chats')
            .select('id')
            .or('and(participant1_id.eq.${currentUserId},participant2_id.eq.${widget.video.userId}),and(participant1_id.eq.${widget.video.userId},participant2_id.eq.${currentUserId})')
            .single();

        if (mounted) {
          context.push('/messages/${response['id']}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                      // When pausing, show controls (scrubbing) and hide description
                      _showControls = true;
                      _hideControlsTimer?.cancel(); // Don't auto-hide when paused
                    } else {
                      _controller.play();
                      // When playing, immediately hide controls and show description
                      _showControls = false;  // Immediately hide controls
                      _hideControlsTimer?.cancel();
                    }
                  });
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_isInitialized && _thumbnailPath != null)
                      Image.file(
                        File(_thumbnailPath!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: MediaQuery.of(context).size.width * 16 / 9,
                      ),
                    if (_isInitialized)
                      VideoPlayer(_controller),

                    // Show title, user info, and description only when playing and controls are not shown
                    if (!_showControls && _controller.value.isPlaying) ...[
                      // Interaction buttons (always shown)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Column(
                          children: [
                            SaveButton(
                              videoId: widget.video.id,
                            ),
                            const SizedBox(height: 8),
                            IconButton(
                              icon: const Icon(Icons.comment),
                              color: Colors.white,
                              onPressed: () => _showComments(context),
                            ),
                            const SizedBox(height: 8),
                            // Add delete button here if user is owner
                            if (supabase.auth.currentUser?.id == widget.video.userId) ...[
                              IconButton(
                                icon: const Icon(Icons.delete),
                                color: Colors.white,
                                onPressed: _deleteVideo,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.all(8),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Title at the top
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 48,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isTitleExpanded = !_isTitleExpanded;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.video.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 4,
                                      color: Colors.black,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                maxLines: _isTitleExpanded ? null : 2,
                                overflow: _isTitleExpanded ? null : TextOverflow.ellipsis,
                              ),
                              if (!_isTitleExpanded && widget.video.title.length > 60)
                                Text(
                                  'more...',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                    shadows: const [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // User info and description at the bottom
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundImage: widget.video.photoUrl != null
                                            ? NetworkImage(widget.video.photoUrl!)
                                            : null,
                                        child: widget.video.photoUrl == null
                                            ? const Icon(Icons.person)
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          widget.video.displayName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 4,
                                                color: Colors.black,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isDescriptionExpanded = !_isDescriptionExpanded;
                                      });
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.video.description,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 4,
                                                color: Colors.black,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          maxLines: _isDescriptionExpanded ? null : 2,
                                          overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                                        ),
                                        if (!_isDescriptionExpanded && widget.video.description.length > 100)
                                          Text(
                                            'more...',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 14,
                                              shadows: const [
                                                Shadow(
                                                  blurRadius: 4,
                                                  color: Colors.black,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Connect/Profile button
                            SizedBox(
                              width: 100,
                              child: _buildActionButton(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Show progress bar only when paused (controls shown)
                    if (_showControls)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            colors: VideoProgressColors(
                              playedColor: Theme.of(context).primaryColor,
                              bufferedColor: Colors.white.withOpacity(0.5),
                              backgroundColor: Colors.white.withOpacity(0.2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }

  Widget _buildActionButton() {
    final currentUserId = supabase.auth.currentUser?.id;
    
    // If this is the current user's video
    if (currentUserId == widget.video.userId) {
      return ElevatedButton(
        onPressed: () {
          context.push('/profile');
        },
        style: _buttonStyle,
        child: const Text('Profile', maxLines: 1),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      // Convert the query to a Future
      future: supabase
          .from('connections')
          .select()
          .or('and(requester_id.eq.${currentUserId},receiver_id.eq.${widget.video.userId}),and(requester_id.eq.${widget.video.userId},receiver_id.eq.${currentUserId})')
          .limit(1)
          .then((data) => List<Map<String, dynamic>>.from(data)), // Convert response to correct type
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ElevatedButton(
            onPressed: null,
            style: _buttonStyle,
            child: const Text('Error', maxLines: 1),
          );
        }

        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        final connections = snapshot.data!;
        
        // If there's no connection yet
        if (connections.isEmpty) {
          return ElevatedButton(
            onPressed: _handleConnect,
            style: _buttonStyle,
            child: const Text('Connect', maxLines: 1),
          );
        }

        final connection = connections.first;
        final status = connection['status'];

        // If connection is pending
        if (status == 'pending') {
          return ElevatedButton(
            onPressed: null,
            style: _buttonStyle.copyWith(
              backgroundColor: MaterialStateProperty.resolveWith(
                (states) => states.contains(MaterialState.disabled) ? Colors.grey[300] : null,
              ),
              foregroundColor: MaterialStateProperty.resolveWith(
                (states) => states.contains(MaterialState.disabled) ? Colors.grey[600] : null,
              ),
            ),
            child: const Text('Pending', maxLines: 1),
          );
        }

        // If users are connected
        if (status == 'accepted') {
          return ElevatedButton(
            onPressed: () async {
              try {
                // Get the chat between these users
                final response = await supabase
                    .from('chats')
                    .select('id')
                    .or('and(user1_id.eq.${currentUserId},user2_id.eq.${widget.video.userId}),and(user1_id.eq.${widget.video.userId},user2_id.eq.${currentUserId})')
                    .single();

                if (mounted) {
                  // Navigate to the chat
                  context.push('/messages/${response['id']}');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error opening chat: $e')),
                  );
                }
              }
            },
            style: _buttonStyle,
            child: const Text('Chat', maxLines: 1),
          );
        }

        return ElevatedButton(
          onPressed: null,
          style: _buttonStyle,
          child: Text('Unknown status: $status', maxLines: 1),
        );
      },
    );
  }

  Widget _buildDescription() {
    if (widget.video.description.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final TextSpan textSpan = TextSpan(
              text: widget.video.description,
              style: const TextStyle(color: Colors.white70),
            );
            final TextPainter textPainter = TextPainter(
              text: textSpan,
              maxLines: 2,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);

            final bool hasOverflow = textPainter.didExceedMaxLines;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.description,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: _isDescriptionExpanded ? null : 2,
                  overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                ),
                if (hasOverflow && !_isDescriptionExpanded)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDescriptionExpanded = true;
                      });
                    },
                    child: const Text(
                      'more...',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (_isDescriptionExpanded)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDescriptionExpanded = false;
                      });
                    },
                    child: const Text(
                      'Show less',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Comments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: CommentsSection(videoId: widget.video.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _hideControlsTimer?.cancel();
    _controller.dispose();
    _nextController?.dispose();
    // Clean up thumbnail
    if (_thumbnailPath != null) {
      File(_thumbnailPath!).delete().catchError((_) {});
    }
    super.dispose();
  }

  // Add this method to check if it's the current user's video
  bool _isCurrentUser() {
    final currentUserId = supabase.auth.currentUser?.id;
    return currentUserId == widget.video.userId;
  }

  Future<void> _deleteVideo() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId != widget.video.userId) return; // Only allow owner to delete

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Video'),
        content: const Text('Are you sure you want to delete this video? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      // Extract video path from URL
      final uri = Uri.parse(widget.video.url);
      final videoPath = uri.pathSegments.last;

      // Delete video file from storage
      await supabase.storage
          .from('videos')
          .remove([videoPath]);

      // Delete video record from database
      await supabase
          .from('videos')
          .delete()
          .eq('id', widget.video.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video deleted successfully')),
        );
        // Refresh the video list
        ref.refresh(videosProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting video: $e')),
        );
      }
    }
  }

  void _preloadNextVideo(String url) {
    _nextController?.dispose();
    _nextController = VideoPlayerController.networkUrl(Uri.parse(url));
    _nextController?.initialize();
  }
} 