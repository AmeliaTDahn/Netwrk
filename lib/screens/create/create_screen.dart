import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;
import '../../core/supabase_client.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  String? _videoPath;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  double _compressionProgress = 0.0;
  Subscription? _compressionSubscription;

  @override
  void initState() {
    super.initState();
    // Subscribe to compression progress
    _compressionSubscription = VideoCompress.compressProgress$.subscribe((progress) {
      setState(() {
        _compressionProgress = progress;
      });
    });
  }

  Future<void> _recordVideo() async {
    try {
      // First check if we're running on a simulator
      if (Platform.isIOS) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final iosInfo = await deviceInfoPlugin.iosInfo;
        final bool isSimulator = !iosInfo.isPhysicalDevice;
        
        if (isSimulator) {
          // Show alert that camera isn't available on simulator
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Simulator Detected'),
                content: const Text(
                  'Camera is not available on the iOS simulator. Please use "Select from Gallery" or test on a physical device.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      // If we're on a physical device, proceed with camera
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 1),
        preferredCameraDevice: CameraDevice.front,
      );

      if (video != null) {
        setState(() {
          _videoPath = video.path;
        });
        _showPostCreationDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording video: $e')),
        );
      }
    }
  }

  Future<void> _processAndUploadVideo() async {
    if (_videoPath == null) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _compressionProgress = 0.0;
    });

    File? videoFile;
    File? thumbnailFile;
    File? originalVideoFile;

    try {
      // Show compression progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              title: const Text('Processing Video'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Compressing: ${(_compressionProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ),
        );
      }

      originalVideoFile = File(_videoPath!);
      
      // Compress video
      final MediaInfo? compressedVideo = await VideoCompress.compressVideo(
        _videoPath!,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false, // Keep original video
        includeAudio: true,
      );

      // Close progress dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (compressedVideo == null || compressedVideo.file == null) {
        throw 'Video compression failed';
      }

      // Generate thumbnail
      final thumbnailPath = await video_thumbnail.VideoThumbnail.thumbnailFile(
        video: compressedVideo.file!.path,
        imageFormat: video_thumbnail.ImageFormat.JPEG,
        quality: 75,
      );

      if (thumbnailPath == null) throw 'Thumbnail generation failed';

      videoFile = File(compressedVideo.file!.path);
      thumbnailFile = File(thumbnailPath);

      // Upload to Supabase
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw 'User not authenticated';

      final userData = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
      
      final userRole = userData['role'] as String;
      if (!['business', 'employee'].contains(userRole)) {
        throw 'Invalid user role';
      }

      // Upload video with proper path structure
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoFileName = '$userId/$timestamp.mp4';
      await supabase.storage
          .from('videos')
          .upload(videoFileName, videoFile);

      // Upload thumbnail
      final thumbnailFileName = '$userId/$timestamp.jpg';
      await supabase.storage
          .from('thumbnails')
          .upload(thumbnailFileName, thumbnailFile);

      // Get public URLs
      final videoUrl = supabase.storage
          .from('videos')
          .getPublicUrl(videoFileName);
      final thumbnailUrl = supabase.storage
          .from('thumbnails')
          .getPublicUrl(thumbnailFileName);

      // Create video post with current timestamp
      final now = DateTime.now().toUtc();
      await supabase.from('videos').insert({
        'user_id': userId,
        'title': _titleController.text.trim(),
        'url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'description': _descriptionController.text.trim(),
        'category': userRole,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Clear the form
      _titleController.clear();
      _descriptionController.clear();
      setState(() {
        _videoPath = null;
      });

      if (mounted) {
        Navigator.pop(context); // Close post creation dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video posted successfully!')),
        );
        
        // Navigate back to home page
        context.go('/');
      }
    } catch (e) {
      print('Error uploading video: $e');
      String errorMessage = 'Error uploading video';
      
      if (e.toString().contains('Invalid user role')) {
        errorMessage = 'Invalid user role. Please update your profile.';
      } else if (e.toString().contains('not-null constraint')) {
        errorMessage = 'Please fill in all required fields';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      // Clean up files safely
      try {
        await VideoCompress.deleteAllCache();
        
        if (originalVideoFile?.existsSync() == true) {
          await originalVideoFile!.delete();
        }
        if (videoFile?.existsSync() == true) {
          await videoFile!.delete();
        }
        if (thumbnailFile?.existsSync() == true) {
          await thumbnailFile!.delete();
        }
      } catch (e) {
        print('Error cleaning up files: $e');
      }

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _compressionProgress = 0.0;
        });
      }
    }
  }

  void _showPostCreationDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Enter a title for your video...',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Write a description for your video...',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _processAndUploadVideo,
                  child: _isProcessing
                      ? const CircularProgressIndicator()
                      : const Text('Post Video'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Video'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Create a new video',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _recordVideo(),
              icon: const Icon(Icons.videocam),
              label: const Text('Record Video'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Add gallery option for simulator testing
            TextButton.icon(
              onPressed: () async {
                final XFile? video = await _picker.pickVideo(
                  source: ImageSource.gallery,
                  maxDuration: const Duration(minutes: 1),
                );

                if (video != null) {
                  setState(() {
                    _videoPath = video.path;
                  });
                  _showPostCreationDialog();
                }
              },
              icon: const Icon(Icons.photo_library),
              label: const Text('Select from Gallery'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _compressionSubscription?.unsubscribe();
    VideoCompress.cancelCompression();
    _descriptionController.dispose();
    super.dispose();
  }
} 