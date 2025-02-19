import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import '../profile/user_profile_screen.dart';
import '../../components/banner_notification.dart';
import 'dart:convert';
import '../feed/video_player_screen.dart';

class ApplicationsScreen extends StatefulWidget {
  final String? jobListingId;
  final String? filterStatus;
  final bool showFolderView;
  final String? singleApplicationId;

  const ApplicationsScreen({
    super.key,
    this.jobListingId,
    this.filterStatus,
    this.showFolderView = true,
    this.singleApplicationId,
  });

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  final PageController _pageController = PageController();
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;
  Map<String, bool> _tabLoadingStates = {
    'accepted': true,
    'interviewing': true,
    'saved': true,
  };
  Map<String, List<Map<String, dynamic>>> _tabApplications = {
    'accepted': [],
    'interviewing': [],
    'saved': [],
  };
  int _currentIndex = 0;
  Map<String, VideoPlayerController> _videoControllers = {};
  Map<String, Uint8List?> _thumbnails = {};
  VideoPlayerController? _nextVideoController;
  String _currentView = 'all'; // 'all', 'accepted', 'interviewing'
  Map<String, dynamic>? _lastRejectedApplication; // Store last rejected application
  bool _isRefreshing = false;
  static const int _preloadAhead = 3; // Number of videos to preload ahead
  final Map<String, bool> _preloadingVideos = {}; // Track which videos are being preloaded
  final Set<String> _preloadQueue = {}; // Queue of videos to preload

  @override
  void initState() {
    super.initState();
    _loadApplications().then((_) {
      if (_applications.isNotEmpty) {
        _preloadVideos(0); // Start preloading videos after initial load
      }
    });
  }

  Future<void> _loadApplications() async {
    if (_currentView == 'all') {
      setState(() => _isLoading = true);
    } else {
      setState(() => _tabLoadingStates[_currentView] = true);
    }

    try {
      final userId = supabase.auth.currentUser?.id;
      print('\n=== Loading Applications Debug Log ===');
      print('Current user ID: $userId');
      print('Current view: $_currentView');
      print('Job listing ID filter: ${widget.jobListingId}');
      print('Status filter: ${widget.filterStatus}');
      
      if (userId == null) {
        print('ERROR: No authenticated user found');
        return;
      }

      // First verify if the user is a business user
      print('\n=== Verifying Business User Status ===');
      final userProfile = await supabase
          .from('profiles')
          .select('account_type, business_name')
          .eq('id', userId)
          .single();
      
      print('User profile data:');
      print('Account type: ${userProfile['account_type']}');
      print('Business name: ${userProfile['business_name']}');
      
      var query = supabase
          .from('job_applications')
          .select('''
            *,
            profiles!inner (
              id,
              name,
              photo_url,
              experience_years,
              profile_skills (
                skills (
                  name
                )
              )
            ),
            job_listings!inner (
              *,
              interview_message_template,
              acceptance_message_template,
              profiles!business_id (*)
            ),
            application_match_ratings (
              id,
              match_rating,
              analysis_text
            )
          ''');

      print('\n=== Building Query Filters ===');
      // Add job listing filter if specified
      if (widget.jobListingId != null) {
        print('Adding job listing filter: ${widget.jobListingId}');
        query = query.eq('job_listing_id', widget.jobListingId);
      }

      // Add single application filter if specified
      if (widget.singleApplicationId != null) {
        print('Adding single application filter: ${widget.singleApplicationId}');
        query = query.eq('id', widget.singleApplicationId);
      } else {
        // Only apply status filters if not viewing a single application
        if (widget.filterStatus != null) {
          print('Adding status filter: ${widget.filterStatus}');
          query = query.eq('status', widget.filterStatus);
        } else if (_currentView != 'all') {
          print('Adding view-specific status filter for: $_currentView');
          if (_currentView == 'accepted') {
            query = query.eq('status', 'accepted');
          } else if (_currentView == 'interviewing') {
            query = query.or('status.eq.interviewing,status.eq.interviewing_saved');
          } else if (_currentView == 'saved') {
            query = query.or('status.eq.saved,status.eq.interviewing_saved');
          }
        } else {
          print('Adding filter for unprocessed applications');
          query = query.not('status', 'in', '(accepted,rejected,saved,interviewing,interviewing_saved)');
        }
      }

      print('\n=== Executing Query ===');
      final response = await query.order('created_at', ascending: false);
      
      print('\n=== Response Analysis ===');
      print('Total applications received: ${response.length}');
      
      if (response is List && response.isNotEmpty) {
        final firstApp = response[0];
        print('\nFirst Application Details:');
        print('Application ID: ${firstApp['id']}');
        print('Status: ${firstApp['status']}');
        print('Created at: ${firstApp['created_at']}');
        print('Job listing ID: ${firstApp['job_listing_id']}');
        
        print('\nBusiness User Check:');
        print('Job listing business profile: ${firstApp['job_listings']['profiles']}');
        print('Account type: ${firstApp['job_listings']['profiles']['account_type']}');
        
        print('\nMatch Rating Data:');
        print('Match ratings array: ${firstApp['application_match_ratings']}');
        if (firstApp['application_match_ratings'] != null) {
          if (firstApp['application_match_ratings'] is List) {
            print('Match ratings count: ${firstApp['application_match_ratings'].length}');
            if (firstApp['application_match_ratings'].isNotEmpty) {
              print('First match rating: ${firstApp['application_match_ratings'][0]}');
              print('Rating value: ${firstApp['application_match_ratings'][0]['match_rating']}');
            } else {
              print('Match ratings array is empty');
            }
          } else {
            print('Match ratings is not a List: ${firstApp['application_match_ratings'].runtimeType}');
          }
        } else {
          print('No match ratings found');
        }
      } else {
        print('No applications found in response');
      }

      setState(() {
        if (_currentView == 'all') {
          _applications = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          print('\nUpdated main applications list: ${_applications.length} items');
        } else {
          _tabApplications[_currentView] = List<Map<String, dynamic>>.from(response);
          _tabLoadingStates[_currentView] = false;
          print('\nUpdated $_currentView tab: ${_tabApplications[_currentView]?.length} items');
        }
      });

      // Initialize video controllers for visible applications
      final applicationsToInitialize = _currentView == 'all' ? _applications : _tabApplications[_currentView]!;
      print('\n=== Video Controller Initialization ===');
      print('Applications to initialize: ${applicationsToInitialize.length}');
      
      for (var application in applicationsToInitialize) {
        final videoUrl = application['video_url'];
        if (videoUrl != null) {
          print('Initializing video controller for: $videoUrl');
          await _initializeVideoController(videoUrl);
        }
      }

      print('\n=== Load Applications Complete ===');

    } catch (e, stackTrace) {
      print('\n=== Error Loading Applications ===');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      print('Stack trace:');
      print(stackTrace);
      
      if (e is PostgrestException) {
        print('\nPostgrest Error Details:');
        print('Code: ${e.code}');
        print('Message: ${e.message}');
        print('Details: ${e.details}');
        print('Hint: ${e.hint}');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading applications: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          if (_currentView == 'all') {
            _isLoading = false;
          } else {
            _tabLoadingStates[_currentView] = false;
          }
        });
      }
    }
  }

  Future<void> _loadAllThumbnails() async {
    // Collect all unique video URLs across all tabs and main view
    final allApplications = [
      ..._applications,
      ...(_tabApplications['accepted'] ?? []),
      ...(_tabApplications['interviewing'] ?? []),
      ...(_tabApplications['saved'] ?? []),
    ];
    
    final uniqueVideoUrls = allApplications
        .map((app) => app['video_url'])
        .where((url) => url != null)
        .toSet();
    
    // Load thumbnails in the background
    for (var videoUrl in uniqueVideoUrls) {
      if (_thumbnails[videoUrl] != null) continue;  // Skip if already loaded
      
      try {
        final storagePath = videoUrl.split('applications/').last;
        final signedUrl = await supabase.storage
            .from('applications')
            .createSignedUrl(storagePath, 3600);
            
        final thumbnail = await VideoThumbnail.thumbnailData(
          video: signedUrl,
          imageFormat: ImageFormat.JPEG,
          quality: 50,
          maxWidth: 300,
        );
        
        if (mounted) {
          setState(() {
            _thumbnails[videoUrl] = thumbnail;
          });
        }
      } catch (e) {
        print('Error loading thumbnail for $videoUrl: $e');
      }
    }
  }

  Future<void> _preloadVideos(int currentIndex) async {
    // Calculate range of videos to preload
    final startIndex = currentIndex + 1;
    final endIndex = min(startIndex + _preloadAhead, _applications.length);
    
    for (var i = startIndex; i < endIndex; i++) {
      final videoUrl = _applications[i]['video_url'];
      if (videoUrl == null || 
          _videoControllers[videoUrl] != null || 
          _preloadingVideos[videoUrl] == true) continue;

      _preloadQueue.add(videoUrl);
      _preloadingVideos[videoUrl] = true;
      
      _preloadVideo(videoUrl);
    }
  }

  Future<void> _preloadVideo(String videoUrl) async {
    try {
      print('\n=== Starting Video Preload ===');
      print('Video URL to preload: $videoUrl');
      
      final storagePath = videoUrl.split('applications/').last;
      print('Storage path: $storagePath');
      
      print('Requesting signed URL...');
      final signedUrl = await supabase.storage
          .from('applications')
          .createSignedUrl(storagePath, 3600);
      print('Received signed URL: $signedUrl');

      print('Creating controller...');
      final controller = VideoPlayerController.network(
        signedUrl,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      print('Initializing controller...');
      await controller.initialize();
      print('Setting video to loop...');
      await controller.setLooping(true);
      
      if (!mounted) {
        print('Widget unmounted during preload, disposing controller');
        controller.dispose();
        return;
      }

      setState(() {
        print('Storing controller in state');
        _videoControllers[videoUrl] = controller;
        _preloadingVideos[videoUrl] = false;
        _preloadQueue.remove(videoUrl);
      });
      
      print('=== Video Preload Complete ===');
    } catch (e) {
      print('\n=== Video Preload Error ===');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      print('Stack trace:');
      print(StackTrace.current);
      
      _preloadingVideos[videoUrl] = false;
      _preloadQueue.remove(videoUrl);
    }
  }

  Future<void> _initializeVideoController(String videoUrl) async {
    if (_videoControllers[videoUrl] == null) {
      try {
        print('\n=== Starting Video Initialization ===');
        print('Input video URL: $videoUrl');

        final storagePath = videoUrl.split('applications/').last;
        print('Storage path extracted: $storagePath');

        print('Requesting signed URL from Supabase...');
        final signedUrl = await supabase.storage
            .from('applications')
            .createSignedUrl(storagePath, 3600);
        print('Received signed URL: $signedUrl');

        print('Creating video controller...');
        final controller = VideoPlayerController.network(
          signedUrl,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );

        try {
          print('Initializing controller...');
          await controller.initialize();
          print('Controller initialized successfully');
          
          print('Setting video to loop...');
          await controller.setLooping(true);
          print('Setting volume...');
          await controller.setVolume(1.0);

          if (!mounted) {
            print('Widget not mounted, disposing controller');
            controller.dispose();
            return;
          }

          print('Updating state with new controller');
          setState(() {
            _videoControllers[videoUrl] = controller;
          });
          
          // Only play if this is the current video and we're still mounted
          if (mounted && _applications.isNotEmpty && 
              _applications[_currentIndex]['video_url'] == videoUrl) {
            print('Playing video automatically');
            await controller.play();
          }
          
          print('=== Video Initialization Complete ===');
        } catch (initError) {
          print('Error during controller initialization:');
          print(initError);
          print('Stack trace:');
          print(StackTrace.current);
          controller.dispose();
          throw initError;
        }
      } catch (e) {
        print('\n=== Video Initialization Error ===');
        print('Error type: ${e.runtimeType}');
        print('Error message: $e');
        print('Stack trace:');
        print(StackTrace.current);
        
        if (e is StorageException) {
          print('Storage error details:');
          print('Status code: ${e.statusCode}');
          print('Error message: ${e.message}');
        }
        
        if (mounted) {
          _showNotification('Error loading video. Tap to retry', isSuccess: false);
        }
      }
    }
  }

  // Add this helper method for consistent notifications
  void _showNotification(String message, {bool isSuccess = true}) {
    if (!mounted) return;
    BannerNotification.show(context, message);
  }

  Future<void> _updateApplicationStatus(String applicationId, String newStatus) async {
    try {
      // Get current application status and full application data
      final currentApp = await supabase
          .from('job_applications')
          .select('''
            *,
            profiles!inner (
              id,
              name,
              photo_url,
              experience_years,
              profile_skills (
                skills (
                  name
                )
              )
            ),
            job_listings!inner (
              *,
              interview_message_template,
              acceptance_message_template,
              profiles!business_id (
                id,
                name,
                photo_url,
                business_name,
                account_type
              )
            )
          ''')
          .eq('id', applicationId)
          .single();
      
      final currentStatus = currentApp['status'] as String;
      final businessId = currentApp['job_listings']['profiles']['id'];
      final applicantId = currentApp['applicant_id'];

      // Special handling for save/unsave in interview state
      if (currentStatus == 'interviewing' && newStatus == 'saved') {
        newStatus = 'interviewing_saved';
      } else if (currentStatus == 'interviewing_saved' && newStatus == 'pending') {
        newStatus = 'interviewing';  // Unsave but keep in interview state
      }

      // Update application status first
      await supabase
          .from('job_applications')
          .update({'status': newStatus})
          .eq('id', applicationId);

      // If accepting application or moving to interview, create connection if it doesn't exist
      if (newStatus == 'accepted' || newStatus == 'interviewing' || newStatus == 'interviewing_saved') {
        try {
          // Check for existing connection
          final existingConnection = await supabase
              .from('connections')
              .select()
              .or('and(requester_id.eq.$businessId,receiver_id.eq.$applicantId),and(requester_id.eq.$applicantId,receiver_id.eq.$businessId)')
              .maybeSingle();

          if (existingConnection == null) {
            // Create new connection with accepted status
            await supabase.from('connections').insert({
              'requester_id': businessId,
              'receiver_id': applicantId,
              'status': 'accepted',
              'created_at': DateTime.now().toIso8601String(),
            });
            print('Created new connection between business and applicant');
          } else if (existingConnection['status'] != 'accepted') {
            // Update existing connection to accepted status
            await supabase
                .from('connections')
                .update({'status': 'accepted'})
                .eq('id', existingConnection['id']);
            print('Updated existing connection to accepted status');
          }
        } catch (connectionError) {
          print('Error handling connection: $connectionError');
        }
      }

      // Create chat and send message for accept/interview
      if (['accepted', 'interviewing'].contains(newStatus)) {
        try {
          print('Starting chat/message process for status: $newStatus');
          
          // Check for existing chat
          final existingChat = await supabase
              .from('chats')
              .select('id')
              .or('and(user1_id.eq.$businessId,user2_id.eq.$applicantId),and(user1_id.eq.$applicantId,user2_id.eq.$businessId)')
              .maybeSingle();

          print('Existing chat check result: $existingChat');
          
          String chatId;
          if (existingChat == null) {
            print('Creating new chat');
            // Create new chat
            final chatResponse = await supabase
                .from('chats')
                .insert({
                  'user1_id': businessId,
                  'user2_id': applicantId,
                  'created_at': DateTime.now().toIso8601String(),
                })
                .select()
                .single();
            
            chatId = chatResponse['id'];
            print('New chat created with ID: $chatId');
          } else {
            chatId = existingChat['id'];
            print('Using existing chat with ID: $chatId');
          }

          // Prepare message template
          String messageTemplate;
          if (newStatus == 'accepted') {
            messageTemplate = currentApp['job_listings']['acceptance_message_template'] ?? 
                'Congratulations! We are pleased to inform you that we would like to offer you the position. We believe your skills and experience will be a great addition to our team.';
          } else {
            messageTemplate = currentApp['job_listings']['interview_message_template'] ?? 
                'Hi! Thanks for applying. We would like to schedule an interview with you. Please let me know your availability for this week.';
          }

          print('Sending message with template: $messageTemplate');

          // Send message
          await supabase.from('messages').insert({
            'chat_id': chatId,
            'sender_id': businessId,
            'content': messageTemplate,
          });

          print('Message sent successfully');

        } catch (chatError) {
          print('Error handling chat/message: $chatError');
          if (mounted) {
            _showNotification('Status updated but failed to send message: ${chatError.toString()}', isSuccess: false);
          }
        }
      }

      // Update local state
      setState(() {
        final applicationIndex = _applications.indexWhere((app) => app['id'] == applicationId);
        if (applicationIndex != -1) {
          _applications[applicationIndex]['status'] = newStatus;
        }
      });

      // Show appropriate notification
      if (newStatus == 'rejected') {
        _showNotification('Application rejected');
      } else if (newStatus == 'accepted') {
        _showNotification('Application accepted');
      } else if (newStatus == 'interviewing' || newStatus == 'interviewing_saved') {
        _showNotification('Interview scheduled');
      } else if (newStatus == 'saved' || newStatus == 'interviewing_saved') {
        _showNotification('Application saved');
      } else if ((currentStatus == 'saved' || currentStatus == 'interviewing_saved') && 
                 (newStatus == 'pending' || newStatus == 'interviewing')) {
        _showNotification('Application unsaved');
      }

      // Refresh the applications list if we're in folder view
      if (_currentView != 'all') {
        _loadApplications();
      }

    } catch (e) {
      print('Error updating application: $e');
      _showNotification('Error updating application status: ${e.toString()}', isSuccess: false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'interviewing':
        return Colors.blue;
      default:
        return Colors.grey;
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
        title: const Text('Accept Application'),
        content: const Text('Would you like to accept this candidate or schedule an interview?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Check if the application is saved before moving to interview
              final application = _applications.firstWhere((app) => app['id'] == applicationId);
              final currentStatus = application['status'] as String;
              final newStatus = currentStatus == 'saved' ? 'interviewing_saved' : 'interviewing';
              _updateApplicationStatus(applicationId, newStatus);
            },
            child: const Text('Schedule Interview'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateApplicationStatus(applicationId, 'accepted');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
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
              backgroundColor: Colors.grey[200],
              foregroundColor: Colors.black87,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    final controller = _videoControllers[videoUrl];
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.grey[100],
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        children: [
          VideoPlayer(controller),
          // Video controls overlay
          AnimatedOpacity(
            opacity: controller.value.isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
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
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _onPageChanged(int index) async {
    if (!mounted) return;
    
    print('\n=== Page Change Event ===');
    print('Changing to index: $index');
    
    // Pause current video before changing state
    final currentVideoUrl = _applications[_currentIndex]['video_url'];
    if (currentVideoUrl != null) {
      print('Pausing current video: $currentVideoUrl');
      await _videoControllers[currentVideoUrl]?.pause();
    }
    
    setState(() => _currentIndex = index);
    
    // Initialize and play new video
    final newVideoUrl = _applications[index]['video_url'];
    if (newVideoUrl != null) {
      print('Preparing new video: $newVideoUrl');
      if (_videoControllers[newVideoUrl] == null) {
        print('Video controller not found, initializing...');
        await _initializeVideoController(newVideoUrl);
      } else {
        print('Reusing existing controller');
        await _videoControllers[newVideoUrl]?.seekTo(Duration.zero);
        await _videoControllers[newVideoUrl]?.play();
      }
    }
    
    // Mark application as viewed if in 'all' view
    if (_currentView == 'all') {
      print('Marking application as viewed');
      _markApplicationAsViewed(_applications[index]['id']);
    }
    
    print('Starting video preload for next pages');
    _preloadVideos(index);
    
    print('=== Page Change Complete ===');
  }

  Widget _buildApplicationInfo(Map<String, dynamic> application) {
    final profile = application['profiles'] as Map<String, dynamic>;
    final isSaved = application['status'] == 'accepted' || 
                    application['status'].toString().startsWith('accepted_');
    final hasResume = application['resume_url'] != null;
    final skills = profile['profile_skills'] as List?;
    final matchRating = application['application_match_ratings']?[0]?['match_rating'];
    final isBusinessUser = application['job_listings']['profiles']['account_type'] == 'business';
    
    return Stack(
      children: [
        // Right side buttons (Save, Profile, Resume)
        Positioned(
          right: 8,
          bottom: 140,
          child: Column(
            children: [
              _buildActionButton(
                icon: application['status'] == 'saved' ? Icons.bookmark : Icons.bookmark_border,
                label: application['status'] == 'saved' ? 'Unsave' : 'Save',
                onTap: () => _updateApplicationStatus(
                  application['id'],
                  application['status'] == 'saved' ? 'pending' : 'saved'
                ),
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.person,
                label: 'Profile',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: profile['id'],
                    ),
                  ),
                ),
              ),
              if (hasResume) ...[
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.description,
                  label: 'Resume',
                  onTap: () async {
                    final url = application['resume_url'];
                    if (url != null) {
                      try {
                        await launchUrl(Uri.parse(url));
                      } catch (e) {
                        _showNotification('Could not open resume', isSuccess: false);
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
          bottom: 80,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: profile['photo_url'] != null
                          ? NetworkImage(profile['photo_url'])
                          : null,
                      child: profile['photo_url'] == null
                          ? const Icon(Icons.person, color: Colors.white70, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['name'] ?? 'Anonymous',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (application['cover_note'] != null && 
                              application['cover_note'].toString().isNotEmpty)
                            Text(
                              application['cover_note'],
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            '${profile['experience_years'] ?? 0} years experience',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Match Rating for Business Users
                    if (isBusinessUser && matchRating != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8), // Add padding around for larger touch target
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque, // Makes entire area clickable
                          onTap: () {
                            final analysis = application['application_match_ratings'] is Map ? 
                                application['application_match_ratings']['analysis_text'] : 
                                application['application_match_ratings'] is List && 
                                application['application_match_ratings'].isNotEmpty ? 
                                    application['application_match_ratings'][0]['analysis_text'] : null;
                            
                            if (analysis != null) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Row(
                                    children: [
                                      Icon(
                                        Icons.analytics,
                                        color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Candidate Match: ${matchRating?.toStringAsFixed(1) ?? 'N/A'}',
                                          style: TextStyle(
                                            color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Why this rating?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Flexible(
                                        child: SingleChildScrollView(
                                          child: Text(
                                            analysis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _getMatchRatingColor(matchRating),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.analytics,
                                  color: _getMatchRatingColor(matchRating),
                                  size: 10,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  matchRating.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: _getMatchRatingColor(matchRating),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (skills != null && skills.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: skills
                        .take(3)
                        .map((skill) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                skill.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
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

        // Centered Accept/Reject buttons at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Center(
              child: SizedBox(
                width: 240,
                child: _currentView == 'accepted'
                    ? Container()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ElevatedButton(
                                onPressed: () => _showRejectDialog(application['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black87,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text('Reject'),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ElevatedButton(
                                onPressed: () => _showAcceptDialog(application['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text('Accept'),
                              ),
                            ),
                          ),
                        ],
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
    final bool isSaved = label == 'Unsave';
    
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSaved ? Colors.blue : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon),
            onPressed: onTap,
            color: isSaved ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: isSaved ? FontWeight.bold : FontWeight.normal,
            shadows: const [
              Shadow(
                color: Colors.black,
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFolderView() {
    return DefaultTabController(
      length: 3,
      initialIndex: _currentView == 'accepted' ? 0 : _currentView == 'interviewing' ? 1 : 2,
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
                Tab(text: 'Accepted'),
                Tab(text: 'Interviews'),
                Tab(text: 'Saved'),
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
                      _currentView = 'accepted';
                      break;
                    case 1:
                      _currentView = 'interviewing';
                      break;
                    case 2:
                      _currentView = 'saved';
                      break;
                  }
                });
                // Just load applications, thumbnails will be loaded in the background
                _loadApplications();
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              physics: const ClampingScrollPhysics(),
              children: [
                _buildApplicationsList('accepted'),
                _buildApplicationsList('interviewing'),
                _buildApplicationsList('saved'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationsList(String status) {
    final applications = _tabApplications[status] ?? [];
    final isLoading = _tabLoadingStates[status] ?? false;
    
    if (isLoading && applications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredApplications = applications.where((app) {
      final appStatus = app['status'] as String?;
      if (appStatus == null) return false;
      
      switch (status) {
        case 'accepted':
          return appStatus == 'accepted';
        case 'interviewing':
          return appStatus == 'interviewing' || appStatus == 'interviewing_saved';
        case 'saved':
          return appStatus == 'saved' || appStatus == 'interviewing_saved';
        default:
          return false;
      }
    }).toList();

    if (!isLoading && filteredApplications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              status == 'accepted' ? Icons.check_circle : 
              status == 'interviewing' ? Icons.schedule :
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

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 0.6,
          ),
          itemCount: filteredApplications.length,
          itemBuilder: (context, index) {
            final application = filteredApplications[index];
            final profile = application['profiles'] as Map<String, dynamic>;
            final videoUrl = application['video_url'];
            final matchRating = application['application_match_ratings']?[0]?['match_rating'];
            final isBusinessUser = application['job_listings']['profiles']['account_type'] == 'business';
            List<String> skills = [];
            
            if (profile['profile_skills'] != null) {
              skills = (profile['profile_skills'] as List)
                  .where((ps) => ps['skills'] != null)
                  .map((ps) => ps['skills']['name'].toString())
                  .toList();
            }
            
            return GestureDetector(
              onTap: () async {
                // Dispose all current video controllers before navigating
                for (var controller in _videoControllers.values) {
                  await controller.dispose();
                }
                _videoControllers.clear();
                
                if (!mounted) return;
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(
                      videoId: application['id'],
                      videoUrl: application['video_url'],
                      username: application['profiles']['name'] ?? 'Anonymous',
                      description: application['cover_note'] ?? '',
                      thumbnailUrl: _thumbnails[application['video_url']] != null 
                          ? 'data:image/jpeg;base64,${base64Encode(_thumbnails[application['video_url']]!)}'
                          : '',
                      displayName: application['profiles']['name'] ?? 'Anonymous',
                      photoUrl: application['profiles']['photo_url'],
                      userId: application['profiles']['id'],
                      applicationId: application['id'],
                      applicationStatus: application['status'],
                    ),
                  ),
                ).then((_) async {
                  // Clean up video controllers when returning from the detail view
                  for (var controller in _videoControllers.values) {
                    await controller.dispose();
                  }
                  _videoControllers.clear();
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_thumbnails[videoUrl] != null)
                    Image.memory(
                      _thumbnails[videoUrl]!,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(
                      color: Colors.grey[900],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: const [0.7, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                profile['name'] ?? 'Anonymous',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isBusinessUser && matchRating != null) ...[
                              Container(
                                padding: const EdgeInsets.all(8), // Add padding around for larger touch target
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque, // Makes entire area clickable
                                  onTap: () {
                                    final analysis = application['application_match_ratings'] is Map ? 
                                        application['application_match_ratings']['analysis_text'] : 
                                        application['application_match_ratings'] is List && 
                                        application['application_match_ratings'].isNotEmpty ? 
                                            application['application_match_ratings'][0]['analysis_text'] : null;
                                            
                                    if (analysis != null) {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Row(
                                            children: [
                                              Icon(
                                                Icons.analytics,
                                                color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Candidate Match: ${matchRating?.toStringAsFixed(1) ?? 'N/A'}',
                                                  style: TextStyle(
                                                    color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Why this rating?',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Flexible(
                                                child: SingleChildScrollView(
                                                  child: Text(
                                                    analysis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Close'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _getMatchRatingColor(matchRating),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.analytics,
                                          color: _getMatchRatingColor(matchRating),
                                          size: 10,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          matchRating.toStringAsFixed(1),
                                          style: TextStyle(
                                            color: _getMatchRatingColor(matchRating),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (application['cover_note'] != null && 
                            application['cover_note'].toString().isNotEmpty)
                          Text(
                            application['cover_note'],
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (profile['experience_years'] != null)
                          Text(
                            '${profile['experience_years']} yrs exp',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (skills.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            skills.take(2).join(' • '),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (isLoading)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildApplicationVideo(Map<String, dynamic> application) {
    // Get match rating if available
    num? matchRating;
    final matchRatings = application['application_match_ratings'];
    
    // Handle both Map and List data structures
    if (matchRatings != null) {
      if (matchRatings is List) {
        matchRating = matchRatings.isNotEmpty ? matchRatings[0]['match_rating'] : null;
      } else if (matchRatings is Map) {
        matchRating = matchRatings['match_rating'];
      }
    }
    
    final isBusinessUser = application['job_listings']['profiles']['account_type'] == 'business';
    
    return Stack(
      children: [
        // Full screen video player
        Positioned.fill(
          child: _buildVideoPlayer(application['video_url']),
        ),

        // Match Rating for Business Users - Prominently displayed in bottom right
        if (isBusinessUser) ...[
          Positioned(
            right: 16,
            bottom: 100, // Position above the action buttons
            child: GestureDetector(
              onTap: () {
                final analysis = matchRatings is Map ? 
                    matchRatings['analysis_text'] : 
                    matchRatings is List && matchRatings.isNotEmpty ? 
                        matchRatings[0]['analysis_text'] : null;
                        
                if (analysis != null) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(
                            Icons.analytics,
                            color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Candidate Match: ${matchRating?.toStringAsFixed(1) ?? 'N/A'}',
                              style: TextStyle(
                                color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Why this rating?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Text(
                                analysis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.analytics,
                      color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      matchRating != null ? matchRating.toStringAsFixed(1) : 'N/A',
                      style: TextStyle(
                        color: matchRating != null ? _getMatchRatingColor(matchRating) : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // Right side action buttons with background
        Positioned(
          right: 16,
          top: MediaQuery.of(context).size.height * 0.3,
          child: Column(
            children: [
              _buildCircularButton(
                icon: (application['status'] == 'saved' || application['status'] == 'interviewing_saved') 
                    ? Icons.bookmark 
                    : Icons.bookmark_border,
                label: (application['status'] == 'saved' || application['status'] == 'interviewing_saved') 
                    ? 'Unsave' 
                    : 'Save',
                onTap: () => _updateApplicationStatus(
                  application['id'],
                  (application['status'] == 'saved' || application['status'] == 'interviewing_saved')
                      ? (application['status'] == 'interviewing_saved' ? 'interviewing' : 'pending')
                      : (application['status'] == 'interviewing' ? 'interviewing_saved' : 'saved')
                ),
              ),
              const SizedBox(height: 16),
              _buildCircularButton(
                icon: Icons.person_outline,
                label: 'Profile',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: application['profiles']['id'],
                    ),
                  ),
                ),
              ),
              if (application['resume_url'] != null) ...[
                const SizedBox(height: 16),
                _buildCircularButton(
                  icon: Icons.description_outlined,
                  label: 'Resume',
                  onTap: () => launchUrl(Uri.parse(application['resume_url'])),
                ),
              ],
            ],
          ),
        ),

        // Bottom section with user info and action buttons
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // User info with gradient background
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.black.withOpacity(0.0),
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
                          backgroundImage: application['profiles']['photo_url'] != null
                              ? NetworkImage(application['profiles']['photo_url'])
                              : null,
                          backgroundColor: Colors.grey[800],
                          child: application['profiles']['photo_url'] == null
                              ? const Icon(Icons.person, color: Colors.white70)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                application['profiles']['name'] ?? 'Anonymous',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (application['cover_note'] != null && 
                                  application['cover_note'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    application['cover_note'],
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Show Accept/Reject buttons
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 240,
                    child: _currentView == 'accepted'
                        ? Container()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: ElevatedButton(
                                    onPressed: () => _showRejectDialog(application['id']),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[200],
                                      foregroundColor: Colors.black87,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    child: const Text('Reject'),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: ElevatedButton(
                                    onPressed: () => _showAcceptDialog(application['id']),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    child: const Text('Accept'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final bool isSaved = label == 'Unsave';
    
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSaved ? Colors.blue : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon),
            onPressed: onTap,
            color: isSaved ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: isSaved ? FontWeight.bold : FontWeight.normal,
            shadows: const [
              Shadow(
                color: Colors.black,
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Add this new method for the empty state
  Widget _buildEmptyState() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve reviewed all applications',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVideo(String applicationId, Map<String, dynamic> application) async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get user's connections
      final connectionsResponse = await supabase
          .from('connections')
          .select('''
            *,
            profiles!receiver_id (*),
            requester_profile:profiles!requester_id (*)
          ''')
          .eq('status', 'accepted')
          .or('requester_id.eq.${currentUserId},receiver_id.eq.${currentUserId}');

      final connections = List<Map<String, dynamic>>.from(connectionsResponse);
      
      if (!mounted) return;

      // Show connection selection dialog
      final selectedConnections = await showDialog<List<String>>(
        context: context,
        builder: (context) => _ShareDialog(connections: connections, currentUserId: currentUserId),
      );

      if (selectedConnections == null || selectedConnections.isEmpty) return;

      // Share with selected connections
      for (final connectionId in selectedConnections) {
        await supabase.from('shared_applications').insert({
          'application_id': applicationId,
          'shared_by': currentUserId,
          'shared_with': connectionId,
        });
      }

      _showNotification('Application shared successfully');
    } catch (e) {
      print('Error sharing application: $e');
      _showNotification('Error sharing application', isSuccess: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.filterStatus != null
        ? '${widget.filterStatus![0].toUpperCase()}${widget.filterStatus!.substring(1)} Applications'
        : 'Applications';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.black,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black,
          ),
        ),
        actions: [
          if (_currentView == 'all' && _applications.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentIndex + 1}/${_applications.length}',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (_currentView != 'all')
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadApplications,
              tooltip: 'Refresh applications',
            ),
          if (widget.showFolderView)
            IconButton(
              icon: Icon(
                _currentView == 'all' ? Icons.folder : Icons.play_circle,
                color: Colors.black,
              ),
              onPressed: () async {
                // Pause all videos when switching to folder view
                if (_currentView == 'all') {
                  for (var controller in _videoControllers.values) {
                    await controller.pause();
                  }
                }
                setState(() {
                  _currentView = _currentView == 'all' ? 'accepted' : 'all';
                  _loadApplications();
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentView == 'all'
              ? _applications.isEmpty
                  ? _buildEmptyState()
                  : GestureDetector(
                      onVerticalDragEnd: (details) {
                        // Only trigger when scrolling up at the last video
                        if (_currentIndex == _applications.length - 1 && 
                            details.primaryVelocity! < 0) {
                          setState(() {
                            _applications = [];  // Show empty state
                          });
                        }
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _applications.length,
                        scrollDirection: Axis.vertical,
                        physics: const AlwaysScrollableScrollPhysics(),
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, index) {
                          return _buildApplicationVideo(_applications[index]);
                        },
                      ),
                    )
              : _buildFolderView(),
    );
  }

  @override
  void dispose() {
    // Clean up video controllers
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _nextVideoController?.dispose();
    _pageController.dispose();

    // Clean up Supabase realtime connection
    supabase.removeAllChannels();
    
    super.dispose();
  }

  // Keep the _getMatchRatingColor helper method
  Color _getMatchRatingColor(num rating) {
    if (rating >= 8.0) return Colors.green;
    if (rating >= 6.0) return Colors.yellow;
    if (rating >= 4.0) return Colors.orange;
    return Colors.red;
  }
}

// Add ShareDialog widget
class _ShareDialog extends StatefulWidget {
  final List<Map<String, dynamic>> connections;
  final String currentUserId;

  const _ShareDialog({
    required this.connections,
    required this.currentUserId,
  });

  @override
  _ShareDialogState createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final Set<String> _selectedConnections = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share with Connections'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.connections.isEmpty
            ? const Center(
                child: Text('No connections found'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.connections.length,
                itemBuilder: (context, index) {
                  final connection = widget.connections[index];
                  final isRequester = connection['requester_id'] == widget.currentUserId;
                  final userProfile = isRequester
                      ? connection['profiles']
                      : connection['requester_profile'];
                  final userId = userProfile['id'];
                  final userName = userProfile['name'] ?? 'Anonymous';
                  final photoUrl = userProfile['photo_url'];

                  return CheckboxListTile(
                    value: _selectedConnections.contains(userId),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedConnections.add(userId);
                        } else {
                          _selectedConnections.remove(userId);
                        }
                      });
                    },
                    title: Text(userName),
                    secondary: CircleAvatar(
                      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null ? const Icon(Icons.person) : null,
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedConnections.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedConnections.toList()),
          child: const Text('Share'),
        ),
      ],
    );
  }
} 