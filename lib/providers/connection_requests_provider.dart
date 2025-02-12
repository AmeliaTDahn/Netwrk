import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';

// Provider for the count of pending requests
final connectionRequestsCountProvider = StreamProvider<int>((ref) {
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) return Stream.value(0);

  return supabase
      .from('connections')
      .stream(primaryKey: ['id'])
      .map((connections) {
        // Count pending connection requests where user is the receiver
        return connections.where((connection) {
          return connection['receiver_id'] == currentUserId && 
                 connection['status'] == 'pending';
        }).length;
      });
});

// Provider for whether there are any pending requests (used for notification dots)
final hasConnectionRequestsProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectionRequestsCountProvider.stream).map((count) => count > 0);
}); 