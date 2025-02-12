import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';

final unreadMessagesProvider = StreamProvider<bool>((ref) {
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) return Stream.value(false);

  // Listen to messages table directly for real-time updates
  return supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .map((messages) {
        // Filter messages to find unread ones
        final hasUnread = messages.any((message) {
          return message['sender_id'] != currentUserId && 
                 message['read_at'] == null;
        });
        return hasUnread;
      });
}); 