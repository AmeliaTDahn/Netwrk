import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';

final unreadMessagesProvider = StreamProvider<bool>((ref) {
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) return Stream.value(false);

  // Get initial state and set up realtime subscription
  return supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('read_at', null)
      .neq('sender_id', currentUserId)
      .map((event) {
        // Filter messages to only include those from user's chats
        final hasUnread = event.any((message) {
          return message['sender_id'] != currentUserId && 
                 message['read_at'] == null;
        });
        return hasUnread;
      });
}); 