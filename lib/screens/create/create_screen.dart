import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;
import '../../core/supabase_client.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  String? _videoPath;
  final TextEditingController _descriptionController = TextEditingController();

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

    setState(() {
      _isProcessing = true;
    });

    try {
      // Compress video
      final MediaInfo? compressedVideo = await VideoCompress.compressVideo(
        _videoPath!,
        quality: VideoQuality.MediumQuality,
      );

      if (compressedVideo == null || compressedVideo.file == null) {
        throw 'Video compression failed';
      }

      // Generate thumbnail
      final thumbnailPath = await video_thumbnail.VideoThumbnail.thumbnailFile(
        video: _videoPath!,
        imageFormat: video_thumbnail.ImageFormat.JPEG,
        quality: 75,
      );

      if (thumbnailPath == null) throw 'Thumbnail generation failed';

      final videoFile = File(compressedVideo.file!.path);
      final thumbnailFile = File(thumbnailPath);

      // Upload to Supabase
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw 'User not authenticated';

      // Get user's role
      final userData = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
      
      final userRole = userData['role'] as String;

      // Upload video
      final videoFileName = 'videos/${userId}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await supabase.storage
          .from('videos')
          .upload(videoFileName, videoFile);

      // Upload thumbnail
      final thumbnailFileName = 'thumbnails/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage
          .from('thumbnails')
          .upload(thumbnailFileName, thumbnailFile);

      // Get public URLs
      final videoUrl = supabase.storage.from('videos').getPublicUrl(videoFileName);
      final thumbnailUrl = supabase.storage.from('thumbnails').getPublicUrl(thumbnailFileName);

      // Create video post
      await supabase.from('videos').insert({
        'user_id': userId,
        'url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'description': _descriptionController.text,
        'category': userRole,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video uploaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading video: $e')),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
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
    _descriptionController.dispose();
    super.dispose();
  }
} 