import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import '../../providers/unread_messages_provider.dart';
import 'package:intl/intl.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;

  const ChatScreen({
    super.key,
    required this.chatId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _otherUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChat();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadChat() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get chat details and other user's profile
      final chatDetails = await supabase
          .from('chats')
          .select('''
            *,
            user1:profiles!chats_user1_id_fkey (id, display_name, photo_url),
            user2:profiles!chats_user2_id_fkey (id, display_name, photo_url)
          ''')
          .eq('id', widget.chatId)
          .single();

      // Determine which user is the other participant
      final otherUser = chatDetails['user1']['id'] == currentUserId
          ? chatDetails['user2']
          : chatDetails['user1'];

      // Load messages separately
      final messagesResponse = await supabase
          .from('messages')
          .select('''
            *,
            sender:profiles!messages_sender_id_fkey (id, display_name, photo_url)
          ''')
          .eq('chat_id', widget.chatId)
          .order('created_at', ascending: true);

      // Mark unread messages as read
      if (currentUserId != null) {
        await supabase
            .from('messages')
            .update({ 'read_at': DateTime.now().toIso8601String() })
            .eq('chat_id', widget.chatId)
            .neq('sender_id', currentUserId)
            .is_('read_at', null);
        
        // Refresh the unread messages state
        if (mounted) {
          ref.refresh(unreadMessagesProvider);
        }
      }

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(messagesResponse);
          _otherUser = otherUser;
          _isLoading = false;
        });
        
        // Scroll to bottom after messages are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      print('Error loading chat: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading chat: $e')),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Send message
      final response = await supabase
          .from('messages')
          .insert({
            'chat_id': widget.chatId,
            'sender_id': currentUserId,
            'content': message,
          })
          .select('*, sender:profiles!sender_id (id, display_name)')
          .single();

      // Clear input but keep keyboard open
      _messageController.clear();

      // Update UI
      setState(() {
        _messages.add(response);
      });
      
      // Scroll to bottom after sending message
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: _isLoading
              ? const Text('Loading...')
              : Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: _otherUser?['photo_url'] != null
                          ? NetworkImage(_otherUser!['photo_url'])
                          : null,
                      child: _otherUser?['photo_url'] == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _otherUser?['display_name'] ?? _otherUser?['username'] ?? 'Chat',
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
          titleSpacing: 0, // Reduce spacing to align with back button
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: false,
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message['sender_id'] == supabase.auth.currentUser?.id;
                          final timestamp = DateTime.parse(message['created_at']);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: EdgeInsets.only(
                                    left: isMe ? 32 : 0,
                                    right: isMe ? 0 : 32,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isMe ? Theme.of(context).primaryColor : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message['content'],
                                        style: TextStyle(
                                          color: isMe ? Colors.white : Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatTimestamp(timestamp),
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.only(
                        left: 8,
                        right: 8,
                        top: 8,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardType: TextInputType.multiline,
                              maxLines: null,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.send),
                              color: Colors.white,
                              onPressed: _sendMessage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    // Convert UTC timestamp to local time
    final localTimestamp = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(localTimestamp.year, localTimestamp.month, localTimestamp.day);

    if (messageDate == today) {
      // Today, show time only
      return DateFormat('h:mm a').format(localTimestamp);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday ${DateFormat('h:mm a').format(localTimestamp)}';
    } else if (now.difference(messageDate).inDays < 7) {
      // Within last week
      return '${DateFormat('EEEE').format(localTimestamp)} ${DateFormat('h:mm a').format(localTimestamp)}';
    } else {
      // Older messages
      return DateFormat('MMM d, h:mm a').format(localTimestamp);
    }
  }
} 