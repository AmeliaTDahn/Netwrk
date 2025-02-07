import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import '../feed/video_player_screen.dart';

class SavesScreen extends ConsumerStatefulWidget {
  const SavesScreen({super.key});

  @override
  ConsumerState<SavesScreen> createState() => _SavesScreenState();
}

class _SavesScreenState extends ConsumerState<SavesScreen> {
  List<Map<String, dynamic>> _savedVideos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
              profiles (
                id,
                username,
                display_name,
                photo_url
              )
            )
          ''')
          .order('created_at', ascending: false);

      setState(() {
        _savedVideos = List<Map<String, dynamic>>.from(response);
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

      setState(() {
        _savedVideos.removeWhere((save) => save['video_id'] == videoId);
      });

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_savedVideos.isEmpty) {
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
      appBar: AppBar(title: const Text('Saved Videos')),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.5,
        ),
        itemCount: _savedVideos.length,
        itemBuilder: (context, index) {
          final video = _savedVideos[index]['videos'];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(
                    videoUrl: video['url'],
                    username: video['profiles']['username'],
                    description: video['description'],
                  ),
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  video['thumbnail_url'],
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.bookmark_remove),
                    color: Colors.white,
                    onPressed: () => _unsaveVideo(video['id']),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
} 