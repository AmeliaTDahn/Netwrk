import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../components/video_player_widget.dart';
import '../../models/video_model.dart';
import '../../components/save_button.dart';
import '../profile/user_profile_screen.dart';
import '../../core/supabase_config.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String videoUrl;
  final String username;
  final String description;
  final String thumbnailUrl;
  final String displayName;
  final String? photoUrl;
  final String userId;
  final String? applicationId;
  final String? applicationStatus;

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
    this.applicationId,
    this.applicationStatus,
  }) : super(key: key);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final PageController _pageController = PageController();
  List<Map<String, dynamic>> _applications = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  Map<int, VideoPlayerWidget> _videoPlayers = {};

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    try {
      // Get the current application's status to filter by
      final response = await supabase
          .from('job_applications')
          .select('''
            *,
            profiles!inner (
              id,
              name,
              photo_url
            )
          ''')
          .eq('status', widget.applicationStatus)
          .order('created_at', ascending: false);

      final applications = List<Map<String, dynamic>>.from(response);
      
      // Find the index of the current application
      final currentIndex = applications.indexWhere((app) => app['id'] == widget.applicationId);
      
      if (mounted) {
        setState(() {
          _applications = applications;
          _currentIndex = currentIndex != -1 ? currentIndex : 0;
          _isLoading = false;
        });
        
        // Ensure we're on the correct page
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (currentIndex != -1) {
            _pageController.jumpToPage(currentIndex);
          }
        });
      }
    } catch (e) {
      print('Error loading applications: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  VideoModel _createVideoModel(Map<String, dynamic> application) {
    return VideoModel(
      id: application['id'],
      url: application['video_url'],
      thumbnailUrl: '',  // We don't need thumbnail in video player
      description: application['cover_note'] ?? '',
      title: application['cover_note'] ?? '',
      username: application['profiles']['name'] ?? 'Anonymous',
      displayName: application['profiles']['name'] ?? 'Anonymous',
      photoUrl: application['profiles']['photo_url'],
      userId: application['profiles']['id'],
      category: '',
      createdAt: DateTime.parse(application['created_at']),
      profiles: {
        'id': application['profiles']['id'],
        'username': application['profiles']['name'] ?? 'Anonymous',
        'display_name': application['profiles']['name'] ?? 'Anonymous',
        'photo_url': application['profiles']['photo_url'],
      },
    );
  }

  Future<void> _updateApplicationStatus(String newStatus) async {
    try {
      setState(() => _isLoading = true);

      // Get the job listing ID for the application to fetch message templates
      final applicationResponse = await supabase
          .from('job_applications')
          .select('job_listing_id, status')
          .eq('id', widget.applicationId)
          .single();

      final jobListingId = applicationResponse['job_listing_id'];
      final currentStatus = applicationResponse['status'];

      // Get message templates from job listing
      final listingResponse = await supabase
          .from('job_listings')
          .select('acceptance_message_template, interview_message_template')
          .eq('id', jobListingId)
          .single();

      // Determine if the application is currently saved
      final isSaved = currentStatus == 'saved' || currentStatus == 'interviewing_saved';

      // Update application status while preserving saved state
      String finalStatus = newStatus;
      if (isSaved && newStatus == 'interviewing') {
        finalStatus = 'interviewing_saved';
      }

      // Update application status
      await supabase
          .from('job_applications')
          .update({'status': finalStatus})
          .eq('id', widget.applicationId);

      // Create or update chat and send message if accepting or interviewing
      if (newStatus == 'accepted' || newStatus == 'interviewing') {
        // Get or create chat
        final chatResponse = await supabase
            .from('chats')
            .select()
            .or('and(user1_id.eq.${supabase.auth.currentUser?.id},user2_id.eq.${widget.userId}),and(user1_id.eq.${widget.userId},user2_id.eq.${supabase.auth.currentUser?.id})')
            .maybeSingle();

        String chatId;
        if (chatResponse == null) {
          final newChat = await supabase
              .from('chats')
              .insert({
                'user1_id': supabase.auth.currentUser?.id,
                'user2_id': widget.userId,
              })
              .select()
              .single();
          chatId = newChat['id'];
        } else {
          chatId = chatResponse['id'];
        }

        // Send appropriate message
        final messageTemplate = newStatus == 'accepted'
            ? listingResponse['acceptance_message_template']
            : listingResponse['interview_message_template'];

        await supabase.from('messages').insert({
          'chat_id': chatId,
          'sender_id': supabase.auth.currentUser?.id,
          'content': messageTemplate,
        });
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context); // Return to previous screen
      }
    } catch (e) {
      print('Error updating application status: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _applications[_currentIndex]['profiles']['name'] ?? 'Anonymous',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: (index) {
          setState(() {
            // Update current index
            _currentIndex = index;
            
            // Update autoPlay state for all videos
            _videoPlayers.forEach((videoIndex, player) {
              // Remove old player
              _videoPlayers.remove(videoIndex);
            });
            
            // Create new player with correct autoPlay state
            _videoPlayers[index] = VideoPlayerWidget(
              key: ValueKey('video_$index'),
              video: _createVideoModel(_applications[index]),
              autoPlay: true,
            );
            
            // Preload adjacent videos with autoPlay false
            if (index > 0) {
              _videoPlayers[index - 1] = VideoPlayerWidget(
                key: ValueKey('video_${index - 1}'),
                video: _createVideoModel(_applications[index - 1]),
                autoPlay: false,
              );
            }
            if (index < _applications.length - 1) {
              _videoPlayers[index + 1] = VideoPlayerWidget(
                key: ValueKey('video_${index + 1}'),
                video: _createVideoModel(_applications[index + 1]),
                autoPlay: false,
              );
            }
          });
        },
        itemCount: _applications.length,
        itemBuilder: (context, index) {
          final application = _applications[index];
          final video = _createVideoModel(application);
          
          // Create or get existing video player
          _videoPlayers[index] ??= VideoPlayerWidget(
            key: ValueKey('video_$index'),
            video: video,
            autoPlay: index == _currentIndex,
          );
          
          return Stack(
            children: [
              // Video Player
              _videoPlayers[index]!,
              
              // Right side buttons
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).size.height * 0.25,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Save Button - only show if not accepted
                    if (application['status'] != 'accepted')
                      Container(
                        width: 48,
                        height: 70,
                        margin: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: SaveButton(
                                videoId: application['id'],
                                applicationId: application['id'],
                                currentStatus: application['status'],
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Unsave',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Profile Button
                    Container(
                      width: 48,
                      height: 70,
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.person),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserProfileScreen(
                                      userId: application['profiles']['id'],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Resume Button
                    if (application['resume_url'] != null)
                      Container(
                        width: 48,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.description),
                                onPressed: () {
                                  // Handle resume view
                                },
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Resume',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              // Bottom section
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Profile info and caption
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: application['profiles']['photo_url'] != null 
                                ? NetworkImage(application['profiles']['photo_url']) 
                                : null,
                            child: application['profiles']['photo_url'] == null 
                                ? const Icon(Icons.person) 
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                application['profiles']['name'] ?? 'Anonymous',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (application['profiles']['username'] != null)
                                Text(
                                  application['profiles']['username'],
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              if (application['cover_note'] != null && 
                                  application['cover_note'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    application['cover_note'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Action buttons
                    if (application['status'] == 'saved' || 
                        application['status'] == 'interviewing_saved')
                      Container(
                        color: Colors.white,
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 8,
                          bottom: 8 + MediaQuery.of(context).padding.bottom,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => _updateApplicationStatus('rejected'),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.grey[100],
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text(
                                  'Reject',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed: () => _updateApplicationStatus('accepted'),
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFF2196F3),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text(
                                  'Accept',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
} 