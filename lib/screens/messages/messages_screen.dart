import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/supabase_config.dart';
import 'package:go_router/go_router.dart';
import 'chat_screen.dart';
import '../../providers/unread_messages_provider.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChats();
    // Refresh unread messages state when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.refresh(unreadMessagesProvider);
    });
  }

  Future<void> _loadChats() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get all chats where the user is a participant
      final chats = await supabase
          .from('chats')
          .select('''
            *,
            user1:profiles!chats_user1_id_fkey (id, display_name, photo_url),
            user2:profiles!chats_user2_id_fkey (id, display_name, photo_url),
            messages!inner (
              content,
              created_at,
              sender_id,
              read_at
            )
          ''')
          .or('user1_id.eq.$currentUserId,user2_id.eq.$currentUserId)');

      // Sort chats by latest message timestamp
      final sortedChats = List<Map<String, dynamic>>.from(chats)
        ..sort((a, b) {
          final aMessages = (a['messages'] as List).cast<Map<String, dynamic>>();
          final bMessages = (b['messages'] as List).cast<Map<String, dynamic>>();
          
          // Get latest message from each chat
          final aLatest = aMessages.reduce((curr, next) => 
            DateTime.parse(curr['created_at']).isAfter(DateTime.parse(next['created_at'])) 
              ? curr 
              : next
          );
          final bLatest = bMessages.reduce((curr, next) => 
            DateTime.parse(curr['created_at']).isAfter(DateTime.parse(next['created_at'])) 
              ? curr 
              : next
          );
          
          return DateTime.parse(bLatest['created_at'])
              .compareTo(DateTime.parse(aLatest['created_at']));
        });

      if (mounted) {
        setState(() {
          _chats = sortedChats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading chats: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.refresh(unreadMessagesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? const Center(
                  child: Text(
                    'No messages yet',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    final currentUserId = supabase.auth.currentUser?.id;
                    final otherUser = chat['user1']['id'] == currentUserId
                        ? chat['user2']
                        : chat['user1'];
                    
                    final messages = (chat['messages'] as List).cast<Map<String, dynamic>>();
                    final lastMessage = messages.reduce((curr, next) => 
                      DateTime.parse(curr['created_at']).isAfter(DateTime.parse(next['created_at'])) 
                        ? curr 
                        : next
                    );

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: otherUser['photo_url'] != null
                            ? NetworkImage(otherUser['photo_url'])
                            : null,
                        child: otherUser['photo_url'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              otherUser['display_name'] ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (lastMessage['sender_id'] != currentUserId &&
                              lastMessage['read_at'] == null)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      subtitle: lastMessage != null
                          ? Text(
                              lastMessage['content'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: lastMessage['sender_id'] != currentUserId &&
                                        lastMessage['read_at'] == null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            )
                          : const Text(
                              'No messages yet',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (lastMessage != null)
                            Text(
                              timeago.format(
                                DateTime.parse(lastMessage['created_at']),
                                allowFromNow: true,
                              ),
                              style: TextStyle(
                                color: lastMessage['sender_id'] != currentUserId &&
                                        lastMessage['read_at'] == null
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: lastMessage['sender_id'] != currentUserId &&
                                        lastMessage['read_at'] == null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              chatId: chat['id'],
                            ),
                          ),
                        );
                        // Reload chats when returning from chat screen
                        _loadChats();
                      },
                    );
                  },
                ),
    );
  }
} 