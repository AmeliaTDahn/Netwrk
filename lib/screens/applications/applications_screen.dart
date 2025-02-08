import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import '../profile/user_profile_screen.dart';

class ApplicationsScreen extends StatefulWidget {
  final String? jobListingId;
  final String? filterStatus;
  final bool showFolderView;

  const ApplicationsScreen({
    super.key,
    this.jobListingId,
    this.filterStatus,
    this.showFolderView = true,
  });

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  final PageController _pageController = PageController();
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  Map<String, VideoPlayerController> _videoControllers = {};
  Map<String, Uint8List?> _thumbnails = {};
  VideoPlayerController? _nextVideoController;
  String _currentView = 'all'; // 'all', 'accepted', 'interviewing', 'saved'

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      var query = supabase
          .from('job_applications')
          .select('''
            id,
            video_url,
            status,
            created_at,
            viewed_at,
            job_listing_id,
            job_listings (
              id,
              title,
              business_id
            ),
            profiles (
              id,
              name,
              photo_url,
              education,
              experience_years,
              skills,
              location
            ),
            resume_url
          ''')
          .eq('job_listings.business_id', userId);

      // Add job listing filter if specified
      if (widget.jobListingId != null) {
        query = query.eq('job_listing_id', widget.jobListingId);
      }

      // Add status filter if specified
      if (widget.filterStatus != null) {
        query = query.eq('status', widget.filterStatus);
      } else if (_currentView != 'all') {
        // Filter by current folder view if not showing all
        query = query.eq('status', _currentView);
      }

      // Only show unviewed applications in the main feed
      if (_currentView == 'all') {
        query = query.is_('viewed_at', null);
      }

      // Load all relevant applications for folder view
      if (_currentView != 'all') {
        query = query.in_('status', ['saved', 'accepted', 'interviewing']);
      }

      final response = await query.order('created_at', ascending: false);

      setState(() {
        _applications = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

      // Initialize first video and preload thumbnails
      if (_applications.isNotEmpty && _currentView == 'all') {
        await _initializeVideoController(_applications[0]['video_url']);
        _preloadNextVideo(1);
        _loadThumbnails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading applications: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadThumbnails() async {
    for (var application in _applications) {
      final videoUrl = application['video_url'];
      try {
        final thumbnail = await VideoThumbnail.thumbnailData(
          video: videoUrl,
          imageFormat: ImageFormat.JPEG,
          quality: 25,
        );
        if (mounted) {
          setState(() {
            _thumbnails[videoUrl] = thumbnail;
          });
        }
      } catch (e) {
        // Silently fail for thumbnails
        print('Error loading thumbnail: $e');
      }
    }
  }

  Future<void> _preloadNextVideo(int nextIndex) async {
    if (nextIndex >= _applications.length) return;
    
    final nextVideoUrl = _applications[nextIndex]['video_url'];
    if (_videoControllers[nextVideoUrl] == null) {
      try {
        final controller = VideoPlayerController.network(
          nextVideoUrl,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _nextVideoController = controller;
        await controller.initialize();
        _videoControllers[nextVideoUrl] = controller;
      } catch (e) {
        print('Error preloading next video: $e');
      }
    }
  }

  Future<void> _initializeVideoController(String videoUrl) async {
    if (_videoControllers[videoUrl] == null) {
      try {
        // Check if this was preloaded
        if (_nextVideoController != null && 
            _nextVideoController!.dataSource == videoUrl) {
          _videoControllers[videoUrl] = _nextVideoController!;
          _nextVideoController = null;
        } else {
          final controller = VideoPlayerController.network(
            videoUrl,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
          await controller.initialize();
          _videoControllers[videoUrl] = controller;
        }
        await _videoControllers[videoUrl]?.setLooping(true);
        await _videoControllers[videoUrl]?.play();
        if (mounted) setState(() {});
      } catch (e) {
        print('Error initializing video: $e');
      }
    }
  }

  Future<void> _updateApplicationStatus(String applicationId, String newStatus) async {
    try {
      await supabase
          .from('job_applications')
          .update({'status': newStatus})
          .eq('id', applicationId);

      // If accepting from saved folder, switch to accepted tab
      if (mounted && _currentView == 'saved' && newStatus == 'accepted') {
        setState(() {
          _currentView = 'accepted';
        });
      }

      // Refresh the applications list after status update
      _loadApplications();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Application ${newStatus.toLowerCase()}',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: newStatus == 'accepted' ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating application status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markApplicationAsViewed(String applicationId) async {
    try {
      await supabase
          .from('job_applications')
          .update({
            'viewed_at': DateTime.now().toIso8601String(),
            'status': 'viewed'
          })
          .eq('id', applicationId);
    } catch (e) {
      print('Error marking application as viewed: $e');
    }
  }

  void _showAcceptDialog(String applicationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept or Interview?'),
        content: const Text('Would you like to accept this candidate or schedule an interview?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _updateApplicationStatus(applicationId, 'interviewing');
            },
            child: const Text('Schedule Interview'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateApplicationStatus(applicationId, 'accepted');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(String applicationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Application?'),
        content: const Text('Are you sure you want to reject this application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateApplicationStatus(applicationId, 'rejected');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    final controller = _videoControllers[videoUrl];
    final thumbnail = _thumbnails[videoUrl];

    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnail != null)
            Image.memory(
              thumbnail,
              fit: BoxFit.cover,
            )
          else
            Container(color: Colors.black),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          if (!controller.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    
    // Play current video
    final currentVideoUrl = _applications[index]['video_url'];
    _initializeVideoController(currentVideoUrl);
    
    // Mark application as viewed if in 'all' view
    if (_currentView == 'all') {
      _markApplicationAsViewed(_applications[index]['id']);
    }
    
    // Pause all other videos
    for (var entry in _videoControllers.entries) {
      if (entry.key != currentVideoUrl) {
        entry.value.pause();
      }
    }
    
    // Preload next video
    _preloadNextVideo(index + 1);
    
    // Clean up videos that are no longer needed
    final keepUrls = {
      currentVideoUrl,
      if (index > 0) _applications[index - 1]['video_url'],
      if (index < _applications.length - 1) _applications[index + 1]['video_url'],
    };
    
    _videoControllers.removeWhere((url, controller) {
      if (!keepUrls.contains(url)) {
        controller.dispose();
        return true;
      }
      return false;
    });

    // Check if we've reached the end of the feed
    if (index == _applications.length - 1) {
      // Show a snackbar with the notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You\'ve reached the end of new applications'),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View All',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _currentView = 'saved';
                  _loadApplications();
                });
              },
            ),
          ),
        );

        // After a short delay, automatically switch to the applications view
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _currentView = 'saved';
              _loadApplications();
            });
          }
        });
      }
    }
  }

  Widget _buildApplicationInfo(Map<String, dynamic> application) {
    final profile = application['profiles'] as Map<String, dynamic>;
    final isSaved = application['status'] == 'saved' || 
                    application['status'].toString().startsWith('saved_');
    final hasResume = application['resume_url'] != null;
    
    return Stack(
      children: [
        // Right side buttons
        Positioned(
          right: 8,
          bottom: 100,
          child: Column(
            children: [
              _buildActionButton(
                icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                label: isSaved ? 'Unsave' : 'Save',
                onTap: () => _updateApplicationStatus(
                  application['id'],
                  isSaved ? 'unsave' : 'saved'
                ),
              ),
              const SizedBox(height: 16),
              _buildActionButton(
                icon: Icons.person,
                label: 'Profile',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        userId: profile['id'],
                      ),
                    ),
                  );
                },
              ),
              if (hasResume) ...[
                const SizedBox(height: 16),
                _buildActionButton(
                  icon: Icons.description,
                  label: 'Resume',
                  onTap: () async {
                    final url = application['resume_url'];
                    if (url != null) {
                      try {
                        await launchUrl(Uri.parse(url));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not open resume'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ),

        // Bottom info section with gradient background
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: profile['photo_url'] != null
                          ? NetworkImage(profile['photo_url'])
                          : null,
                      child: profile['photo_url'] == null
                          ? const Icon(Icons.person, color: Colors.white70)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['name'] ?? 'Anonymous',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${profile['experience_years'] ?? 0} years experience',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (profile['skills'] != null && profile['skills'] is List) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (profile['skills'] as List)
                        .map((skill) => skill.toString())
                        .take(3)
                        .map((skill) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                skill,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Swipe instruction text
        Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Swipe ← to reject, → to accept/interview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderView() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              tabs: const [
                Tab(text: 'Saved'),
                Tab(text: 'Accepted'),
                Tab(text: 'Interviews'),
              ],
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 16,
              ),
              indicatorColor: Colors.black,
              indicatorWeight: 2,
              onTap: (index) {
                setState(() {
                  switch (index) {
                    case 0:
                      _currentView = 'saved';
                      break;
                    case 1:
                      _currentView = 'accepted';
                      break;
                    case 2:
                      _currentView = 'interviewing';
                      break;
                  }
                  _loadApplications();
                });
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildApplicationsList('saved'),
                _buildApplicationsList('accepted'),
                _buildApplicationsList('interviewing'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationsList(String status) {
    final filteredApplications = _applications.where((app) {
      final appStatus = app['status'] as String;
      if (status == 'saved') {
        return appStatus == 'saved' || appStatus.startsWith('saved_');
      } else if (status == 'accepted') {
        return appStatus == 'accepted' || appStatus == 'saved_accepted';
      } else if (status == 'interviewing') {
        return appStatus == 'interviewing' || appStatus == 'saved_interviewing';
      }
      return false;
    }).toList();

    if (filteredApplications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No ${status == 'interviewing' ? 'interview' : status} applications',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredApplications.length,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemBuilder: (context, index) {
        final application = filteredApplications[index];
        return Dismissible(
          key: Key(application['id']),
          direction: DismissDirection.horizontal,
          onDismissed: (direction) {
            final newStatus = direction == DismissDirection.endToStart
                ? 'rejected'
                : 'accepted';
            _updateApplicationStatus(application['id'], newStatus);
          },
          confirmDismiss: (direction) async {
            // Show confirmation dialog for rejection
            if (direction == DismissDirection.endToStart) {
              return await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reject Application?'),
                  content: const Text('Are you sure you want to reject this application?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              );
            }
            return true;
          },
          background: Container(
            color: Colors.green,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20.0),
            child: const Icon(Icons.check, color: Colors.white, size: 36),
          ),
          secondaryBackground: Container(
            color: Colors.red,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20.0),
            child: const Icon(Icons.close, color: Colors.white, size: 36),
          ),
          child: _buildApplicationCard(application),
        );
      },
    );
  }

  Widget _buildApplicationVideo(Map<String, dynamic> application) {
    return GestureDetector(
      onHorizontalDragEnd: (details) async {
        if (details.primaryVelocity == null) return;
        
        // Swipe left for reject
        if (details.primaryVelocity! < -1000) {
          // Show confirmation dialog for rejection
          final shouldReject = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Reject Application?'),
              content: const Text('Are you sure you want to reject this application?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ],
            ),
          );
          
          if (shouldReject == true) {
            _updateApplicationStatus(application['id'], 'rejected');
          }
        }
        // Swipe right for accept/interview
        else if (details.primaryVelocity! > 1000) {
          final choice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Accept or Interview?'),
              content: const Text('Would you like to accept this candidate or schedule an interview?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop('interview'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  child: const Text('Schedule Interview'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('accept'),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                  child: const Text('Accept'),
                ),
              ],
            ),
          );
          
          if (choice != null) {
            _updateApplicationStatus(
              application['id'], 
              choice == 'accept' ? 'accepted' : 'interviewing'
            );
          }
        }
      },
      child: Stack(
        children: [
          _buildVideoPlayer(application['video_url']),
          _buildApplicationInfo(application),
        ],
      ),
    );
  }

  Widget _buildApplicationCard(Map<String, dynamic> application) {
    final profile = application['profiles'] as Map<String, dynamic>;
    final hasResume = application['resume_url'] != null;
    final isSaved = application['status'] == 'saved' || 
                    application['status'].toString().startsWith('saved_');
    
    // Convert skills to List<String> regardless of input type
    List<String> skills = [];
    if (profile['skills'] != null) {
      if (profile['skills'] is List) {
        skills = (profile['skills'] as List).map((skill) => skill.toString()).toList();
      } else if (profile['skills'] is String) {
        // If skills is a string, split it by commas
        skills = (profile['skills'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: profile['photo_url'] != null
                  ? NetworkImage(profile['photo_url'])
                  : null,
              child: profile['photo_url'] == null
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(
              profile['name'] ?? 'Anonymous',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (profile['location'] != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16),
                      const SizedBox(width: 4),
                      Text(profile['location']),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (profile['experience_years'] != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.work, size: 16),
                      const SizedBox(width: 4),
                      Text('${profile['experience_years']} years experience'),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (profile['education'] != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.school, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          profile['education'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (skills.isNotEmpty) ...[
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: skills
                        .map((skill) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                skill,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
            isThreeLine: true,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await _initializeVideoController(application['video_url']);
                            if (!mounted) return;
                            
                            if (_videoControllers[application['video_url']] == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Error loading video'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.black,
                                insetPadding: EdgeInsets.zero,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 9 / 16,
                                      child: VideoPlayer(_videoControllers[application['video_url']]!),
                                    ),
                                    StatefulBuilder(
                                      builder: (context, setState) {
                                        final controller = _videoControllers[application['video_url']]!;
                                        controller.play();
                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              if (controller.value.isPlaying) {
                                                controller.pause();
                                              } else {
                                                controller.play();
                                              }
                                            });
                                          },
                                          child: Container(
                                            color: Colors.transparent,
                                            child: Center(
                                              child: AnimatedOpacity(
                                                opacity: controller.value.isPlaying ? 0.0 : 1.0,
                                                duration: const Duration(milliseconds: 200),
                                                child: Container(
                                                  padding: const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.5),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                                    color: Colors.white,
                                                    size: 40,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        onPressed: () {
                                          _videoControllers[application['video_url']]?.pause();
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ).then((_) {
                              // Pause video when dialog is closed
                              _videoControllers[application['video_url']]?.pause();
                            });
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error playing video: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play Video'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: profile['id'],
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.person),
                        label: const Text('View Profile'),
                      ),
                    ),
                  ],
                ),
                if (hasResume) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url = application['resume_url'];
                        if (url != null) {
                          try {
                            await launchUrl(Uri.parse(url));
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open resume'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.description),
                      label: const Text('View Resume'),
                    ),
                  ),
                ],
                // Add accept/reject buttons for saved applications
                if (_currentView == 'saved') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showAcceptDialog(application['id']),
                          icon: const Icon(Icons.check),
                          label: const Text('Accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showRejectDialog(application['id']),
                          icon: const Icon(Icons.close),
                          label: const Text('Reject'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.filterStatus != null
        ? '${widget.filterStatus![0].toUpperCase()}${widget.filterStatus!.substring(1)} Applications'
        : 'Applications';

    return Scaffold(
      backgroundColor: _currentView == 'all' ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: _currentView == 'all' ? Colors.transparent : Colors.white,
        elevation: 0,
        title: Text(title),
        actions: [
          if (_currentView == 'all' && _applications.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentIndex + 1}/${_applications.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (widget.showFolderView)
            IconButton(
              icon: Icon(
                _currentView == 'all' ? Icons.folder : Icons.play_circle,
                color: _currentView == 'all' ? Colors.white : Colors.black,
              ),
              onPressed: () {
                setState(() {
                  _currentView = _currentView == 'all' ? 'saved' : 'all';
                  _loadApplications();
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _applications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _currentView == 'all' ? Icons.videocam_off : Icons.folder_open,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No current applications',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : _currentView == 'all'
                  ? PageView.builder(
                      controller: _pageController,
                      itemCount: _applications.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        return _buildApplicationVideo(_applications[index]);
                      },
                    )
                  : _buildFolderView(),
    );
  }

  @override
  void dispose() {
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _nextVideoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }
} 