import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;

class CommentsScreen extends ConsumerStatefulWidget {
  final String videoId;

  const CommentsScreen({
    Key? key,
    required this.videoId,
  }) : super(key: key);

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final response = await supabase
          .from('comments')
          .select('''
            *,
            profiles (
              id,
              username,
              display_name,
              photo_url
            )
          ''')
          .eq('video_id', widget.videoId)
          .order('created_at', ascending: false);

      setState(() {
        _comments = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading comments: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('comments').insert({
        'user_id': userId,
        'video_id': widget.videoId,
        'content': _commentController.text.trim(),
      });

      _commentController.clear();
      _loadComments();  // Reload comments to show the new one
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting comment: $e')),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await supabase
          .from('comments')
          .delete()
          .match({'id': commentId});
      
      _loadComments();  // Reload comments to reflect deletion
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting comment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comments'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(child: Text('No comments yet'))
                    : ListView.builder(
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          final profile = comment['profiles'];
                          final isCurrentUser = comment['user_id'] == 
                              supabase.auth.currentUser?.id;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: profile['photo_url'] != null
                                  ? NetworkImage(profile['photo_url'])
                                  : null,
                              child: profile['photo_url'] == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Text(
                                  profile['display_name'] ?? profile['username'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  timeago.format(
                                    DateTime.parse(comment['created_at']),
                                  ),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(comment['content']),
                            trailing: isCurrentUser
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteComment(comment['id']),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
} 