import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'chat_screen.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('conversation_participants')
          .select('''
            conversation_id,
            conversations!inner(
              id,
              created_at,
              updated_at,
              messages!inner(
                content,
                created_at,
                sender_id,
                is_read
              )
            ),
            users!inner(
              id,
              profiles!inner(
                display_name,
                photo_url
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', foreignTable: 'conversations.messages');

      setState(() {
        _conversations = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading conversations: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: Implement new conversation
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.message_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No messages yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          // TODO: Implement new conversation
                        },
                        child: const Text('Start a conversation'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = _conversations[index];
                    final otherUser = conversation['users'];
                    final lastMessage = conversation['conversations']['messages'].last;
                    final isUnread = !lastMessage['is_read'] &&
                        lastMessage['sender_id'] != supabase.auth.currentUser?.id;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: otherUser['profiles']['photo_url'] != null
                            ? NetworkImage(otherUser['profiles']['photo_url'])
                            : null,
                        child: otherUser['profiles']['photo_url'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        otherUser['profiles']['display_name'] ?? 'User',
                        style: TextStyle(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        lastMessage['content'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isUnread ? Colors.black87 : Colors.grey[600],
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeago.format(DateTime.parse(lastMessage['created_at'])),
                            style: TextStyle(
                              fontSize: 12,
                              color: isUnread ? Colors.blue : Colors.grey[600],
                            ),
                          ),
                          if (isUnread)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              conversationId: conversation['conversations']['id'],
                              otherUser: otherUser,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
} 