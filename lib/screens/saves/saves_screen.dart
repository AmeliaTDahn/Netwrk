import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import '../../models/video_model.dart';
import '../../components/video_player_widget.dart';

class SavesScreen extends ConsumerStatefulWidget {
  const SavesScreen({super.key});

  @override
  ConsumerState<SavesScreen> createState() => _SavesScreenState();
}

class _SavesScreenState extends ConsumerState<SavesScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _businessVideos = [];
  List<Map<String, dynamic>> _employeeVideos = [];
  bool _isLoading = true;
  late TabController _tabController;
  bool _isGridView = true;
  int? _selectedVideoIndex;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedVideos();
  }

  Future<void> _loadSavedVideos() async {
    try {
      final response = await supabase
          .from('saves')
          .select('''
            *,
            videos (
              id,
              url,
              thumbnail_url,
              description,
              created_at,
              category,
              profiles (
                id,
                username,
                display_name,
                photo_url
              )
            )
          ''')
          .order('created_at', ascending: false);

      final savedVideos = List<Map<String, dynamic>>.from(response);
      
      setState(() {
        _businessVideos = savedVideos
            .where((save) => save['videos']['category'] == 'business')
            .toList();
        _employeeVideos = savedVideos
            .where((save) => save['videos']['category'] == 'employee')
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading saved videos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unsaveVideo(String videoId) async {
    try {
      await supabase
          .from('saves')
          .delete()
          .match({
            'user_id': supabase.auth.currentUser!.id,
            'video_id': videoId,
          });

      // Refresh the videos list
      _loadSavedVideos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video removed from saves')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing video: $e')),
        );
      }
    }
  }

  VideoModel _createVideoModel(Map<String, dynamic> videoData) {
    return VideoModel(
      id: videoData['id'],
      url: videoData['url'],
      thumbnailUrl: videoData['thumbnail_url'],
      description: videoData['description'] ?? '',
      title: videoData['description'] ?? '',
      username: videoData['profiles']['username'],
      displayName: videoData['profiles']['display_name'],
      photoUrl: videoData['profiles']['photo_url'],
      userId: videoData['profiles']['id'],
      category: videoData['category'] ?? '',
      createdAt: DateTime.parse(videoData['created_at']),
      profiles: videoData['profiles'] ?? {},
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> videos, String emptyMessage) {
    if (videos.isEmpty) {
      return Center(child: Text(emptyMessage));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.5,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final videoData = videos[index]['videos'];
        return GestureDetector(
          onTap: () {
            setState(() {
              _isGridView = false;
              _selectedVideoIndex = index;
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                videoData['thumbnail_url'],
                fit: BoxFit.cover,
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Text(
                  videoData['profiles']['display_name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFullScreenView(List<Map<String, dynamic>> videos) {
    // Create a new PageController each time with the initial page
    final controller = PageController(initialPage: _selectedVideoIndex ?? 0);
    
    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      itemCount: videos.length,
      onPageChanged: (index) {
        setState(() {
          _selectedVideoIndex = index;
        });
      },
      itemBuilder: (context, index) {
        final videoData = videos[index]['videos'];
        final video = _createVideoModel(videoData);
        return VideoPlayerWidget(video: video);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_businessVideos.isEmpty && _employeeVideos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved Videos')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No saved videos yet',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Videos'),
        leading: _isGridView 
            ? null 
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isGridView = true;
                    _selectedVideoIndex = null;
                  });
                },
              ),
        bottom: _isGridView ? TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Businesses (${_businessVideos.length})'),
            Tab(text: 'Employees (${_employeeVideos.length})'),
          ],
        ) : null,
      ),
      body: _isGridView
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildGridView(
                  _businessVideos,
                  'No saved business videos',
                ),
                _buildGridView(
                  _employeeVideos,
                  'No saved employee videos',
                ),
              ],
            )
          : _buildFullScreenView(
              _tabController.index == 0 ? _businessVideos : _employeeVideos,
            ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
} 