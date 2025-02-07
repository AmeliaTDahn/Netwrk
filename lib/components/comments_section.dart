import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;

const Color primaryBlue = Color(0xFF2196F3);    // Light blue
const Color secondaryBlue = Color(0xFF1565C0);  // Dark blue

class CommentsSection extends ConsumerStatefulWidget {
  final String videoId;

  const CommentsSection({
    Key? key,
    required this.videoId,
  }) : super(key: key);

  @override
  ConsumerState<CommentsSection> createState() => CommentsSectionState();
}

class CommentsSectionState extends ConsumerState<CommentsSection> {
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
      print('Loading comments for video: ${widget.videoId}');
      final response = await supabase
          .from('comments')
          .select('''
            *,
            profiles!profile_id (
              id,
              username,
              display_name,
              photo_url
            )
          ''')
          .eq('video_id', widget.videoId)
          .order('created_at', ascending: false);

      print('Comments response: $response');
      print('Raw response type: ${response.runtimeType}');
      
      if (response is List) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
        print('Comments loaded: ${_comments.length}');
        print('First comment: ${_comments.firstOrNull}');
      } else {
        print('Response is not a List: $response');
      }
    } catch (e) {
      print('Error loading comments: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      final profileId = supabase.auth.currentUser?.id;
      print('Current profile ID: $profileId');
      if (profileId == null) return;

      print('Adding comment for video: ${widget.videoId}');
      final response = await supabase.from('comments').insert({
        'profile_id': profileId,
        'video_id': widget.videoId,
        'content': _commentController.text.trim(),
      }).select();
      print('Comment added response: $response');

      _commentController.clear();
      await _loadComments();
      print('Comments reloaded after adding');
    } catch (e) {
      print('Error adding comment: $e');
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
      
      _loadComments();
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
    return Column(
      children: [
        // Comments List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(
                  color: primaryBlue,
                ))
              : _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        final profile = comment['profiles'];
                        final isCurrentUser = comment['profile_id'] == 
                            supabase.auth.currentUser?.id;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.grey[200],
                                backgroundImage: profile['photo_url'] != null
                                    ? NetworkImage(profile['photo_url'])
                                    : null,
                                child: profile['photo_url'] == null
                                    ? Icon(Icons.person, color: Colors.grey[400])
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          profile['display_name'] ?? profile['username'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          timeago.format(
                                            DateTime.parse(comment['created_at']),
                                          ),
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comment['content'],
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isCurrentUser)
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.grey[400],
                                    size: 20,
                                  ),
                                  onPressed: () => _deleteComment(comment['id']),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
        // Comment Input
        Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 8,
            left: 16,
            right: 16,
            top: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey[200]!),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 15),
                    maxLines: null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _addComment,
                style: TextButton.styleFrom(
                  foregroundColor: primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Post',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
} 