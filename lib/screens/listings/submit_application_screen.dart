import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:video_compress/video_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import 'dart:io';
import '../../components/ai_recommendations_card.dart';

class SubmitApplicationScreen extends StatefulWidget {
  final String jobListingId;
  final String jobTitle;
  final String businessName;
  final String description;
  final String requirements;

  const SubmitApplicationScreen({
    super.key,
    required this.jobListingId,
    required this.jobTitle,
    required this.businessName,
    required this.description,
    required this.requirements,
  });

  @override
  State<SubmitApplicationScreen> createState() => _SubmitApplicationScreenState();
}

class _SubmitApplicationScreenState extends State<SubmitApplicationScreen> {
  final _coverNoteController = TextEditingController();
  File? _videoFile;
  File? _resumeFile;
  bool _isLoading = false;
  bool _isRecording = false;
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  bool _hasExistingApplication = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _checkExistingApplication();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing camera: $e')),
        );
      }
    }
  }

  Future<void> _checkExistingApplication() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('job_applications')
          .select()
          .eq('job_listing_id', widget.jobListingId)
          .eq('applicant_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _hasExistingApplication = response != null;
          _isLoading = false;
        });

        if (_hasExistingApplication) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already applied to this job'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking application status: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_isLoading) return;
    
    try {
      setState(() => _isLoading = true);
      
      // 1. Clean up existing resources first
      if (_videoController != null) {
        await _videoController!.dispose();
        _videoController = null;
      }
      _videoFile = null;
      
      // 2. Create picker instance
      final ImagePicker picker = ImagePicker();
      
      // 3. Pick video with size constraints
      final XFile? pickedVideo = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      
      // Handle case where user cancels selection
      if (pickedVideo == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      
      // 4. Validate file exists and check size
      final File videoFile = File(pickedVideo.path);
      if (!await videoFile.exists()) {
        throw Exception('Selected video file does not exist');
      }
      
      final int fileSize = await videoFile.length();
      const int maxFileSize = 100 * 1024 * 1024; // 100 MB
      
      if (fileSize > maxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a video under 100 MB'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }
      
      // 5. Process the video
      await VideoCompress.deleteAllCache();
      await _processVideo(videoFile);
      
    } catch (e, stackTrace) {
      print('Error picking video: $e');
      print('Stack trace: $stackTrace');
      
      // Clean up resources
      _videoController?.dispose();
      _videoFile = null;
      await VideoCompress.deleteAllCache();
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load video: ${e.toString().split('\n')[0]}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _recordVideo() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isRecording) {
      final file = await _cameraController!.stopVideoRecording();
      setState(() => _isRecording = false);
      await _processVideo(File(file.path));
    } else {
      try {
        await _cameraController!.startVideoRecording();
        setState(() => _isRecording = true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording video: $e')),
        );
      }
    }
  }

  Future<void> _processVideo(File videoFile) async {
    print('DEBUG: Starting _processVideo');
    print('DEBUG: Input video path: ${videoFile.path}');
    
    if (mounted) setState(() => _isLoading = true);
    
    try {
      // Clear any existing compressed files
      await VideoCompress.deleteAllCache();
      
      print('DEBUG: Starting video compression');
      final MediaInfo? compressedVideo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 24,
      );
      
      if (compressedVideo?.file == null) {
        throw Exception('Failed to compress video');
      }
      
      print('DEBUG: Compression complete. Original size: ${videoFile.lengthSync() / 1024 / 1024} MB');
      print('DEBUG: Compressed size: ${compressedVideo!.file!.lengthSync() / 1024 / 1024} MB');
      
      if (mounted) {
        setState(() {
          _videoFile = compressedVideo.file!;
        });
        await _initializeVideoPlayer();
      }
      
    } catch (e, stackTrace) {
      print('DEBUG: Error in _processVideo: $e');
      print('DEBUG: Stack trace: $stackTrace');
      
      // Clean up resources
      await VideoCompress.cancelCompression();
      await VideoCompress.deleteAllCache();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing video: ${e.toString().split('\n')[0]}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      print('DEBUG: _processVideo completed');
    }
  }

  Future<void> _pickResume() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);

    if (file != null) {
      setState(() => _resumeFile = File(file.path));
    }
  }

  Future<void> _initializeVideoPlayer() async {
    print('DEBUG: Starting _initializeVideoPlayer');
    if (_videoFile != null) {
      print('DEBUG: Video file exists at path: ${_videoFile!.path}');
      _videoController?.dispose();
      _videoController = VideoPlayerController.file(_videoFile!);
      try {
        print('DEBUG: Initializing video controller');
        await _videoController!.initialize();
        print('DEBUG: Setting video to loop');
        await _videoController!.setLooping(true);
        if (mounted) {
          setState(() {});
          print('DEBUG: Video player initialized successfully');
        }
      } catch (e, stackTrace) {
        print('DEBUG: Error initializing video player: $e');
        print('DEBUG: Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error initializing video player: $e')),
          );
        }
      }
    } else {
      print('DEBUG: No video file to initialize');
    }
  }

  Future<void> _submitApplication() async {
    if (_hasExistingApplication) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already applied to this job')),
      );
      return;
    }

    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record or upload a video')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Check again for existing application right before submitting
      final existingApplication = await supabase
          .from('job_applications')
          .select()
          .eq('job_listing_id', widget.jobListingId)
          .eq('applicant_id', userId)
          .maybeSingle();

      if (existingApplication != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already applied to this job'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // Upload video
      final videoFileName = '${userId}/${DateTime.now().toIso8601String()}_video.mp4';
      await supabase.storage.from('applications').upload(
        videoFileName,
        _videoFile!,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );
      final videoUrl = supabase.storage.from('applications').getPublicUrl(videoFileName);

      // Upload resume if provided
      String? resumeUrl;
      if (_resumeFile != null) {
        final resumeFileName = '${userId}/${DateTime.now().toIso8601String()}_resume.pdf';
        await supabase.storage.from('applications').upload(
          resumeFileName,
          _resumeFile!,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: false,
          ),
        );
        resumeUrl = supabase.storage.from('applications').getPublicUrl(resumeFileName);
      }

      // Create application record
      await supabase.from('job_applications').insert({
        'job_listing_id': widget.jobListingId,
        'applicant_id': userId,
        'video_url': videoUrl,
        'resume_url': resumeUrl,
        'cover_note': _coverNoteController.text,
        'status': 'pending',
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application submitted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        // Check if error is due to unique constraint violation
        if (e.toString().contains('duplicate key value violates unique constraint') ||
            e.toString().contains('unique violation')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already applied to this job'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error submitting application: $e')),
          );
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Submit Application'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Applying for ${widget.jobTitle}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'at ${widget.businessName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AIRecommendationsCard(
                    jobTitle: widget.jobTitle,
                    description: widget.description,
                    requirements: widget.requirements,
                  ),
                  const SizedBox(height: 24),
                  if (_videoFile == null) ...[
                    if (_cameraController != null &&
                        _cameraController!.value.isInitialized)
                      AspectRatio(
                        aspectRatio: _cameraController!.value.aspectRatio,
                        child: CameraPreview(_cameraController!),
                      )
                    else
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('Camera not available'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _recordVideo,
                          icon: Icon(_isRecording ? Icons.stop : Icons.videocam),
                          label: Text(_isRecording ? 'Stop' : 'Record Video'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _pickVideo,
                          icon: const Icon(Icons.upload),
                          label: const Text('Upload Video'),
                        ),
                      ],
                    ),
                  ] else ...[
                    if (_videoController != null &&
                        _videoController!.value.isInitialized)
                      AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _videoFile = null;
                            _videoController?.dispose();
                            _videoController = null;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Record Again'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Cover Note',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _coverNoteController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Tell us why you\'re a great fit for this role...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Resume (Optional)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_resumeFile != null)
                              Text(
                                'Resume uploaded',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _pickResume,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_resumeFile == null ? 'Upload' : 'Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _videoFile != null ? _submitApplication : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                      child: const Text('Submit Application'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _coverNoteController.dispose();
    _videoController?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }
} 