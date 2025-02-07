import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';

class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() => _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen> {
  List<Map<String, dynamic>> _incomingRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIncomingRequests();
  }

  Future<void> _loadIncomingRequests() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await supabase
          .from('connections')
          .select('''
            *,
            requester_profile:profiles!requester_id (*)
          ''')
          .eq('receiver_id', currentUserId)
          .eq('status', 'pending');

      if (mounted) {
        setState(() {
          _incomingRequests = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _acceptRequest(String connectionId) async {
    try {
      // Start a Supabase transaction
      final response = await supabase.rpc(
        'accept_connection_and_create_chat',
        params: {'connection_id': connectionId},
      );

      // Remove the request from the list
      setState(() {
        _incomingRequests.removeWhere((request) => request['id'] == connectionId);
      });

      await _loadIncomingRequests();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection request accepted')),
        );
      }
    } catch (e) {
      print('Error accepting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting request: $e')),
        );
      }
    }
  }

  Future<void> _declineRequest(String connectionId) async {
    try {
      // Get the connection data before deleting
      final connection = _incomingRequests.firstWhere(
        (request) => request['id'] == connectionId,
      );

      // Delete the connection
      await supabase
          .from('connections')
          .delete()
          .match({'id': connectionId});

      // Update local state
      setState(() {
        _incomingRequests.removeWhere((request) => request['id'] == connectionId);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection request declined')),
        );
      }
    } catch (e) {
      print('Error declining request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error declining request: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Requests'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _incomingRequests.isEmpty
              ? const Center(child: Text('No pending requests'))
              : ListView.builder(
                  itemCount: _incomingRequests.length,
                  itemBuilder: (context, index) {
                    final request = _incomingRequests[index];
                    final requester = request['requester_profile'];
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: requester['photo_url'] != null
                              ? NetworkImage(requester['photo_url'])
                              : null,
                          child: requester['photo_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          requester['display_name'] ?? requester['username'] ?? 'User',
                        ),
                        subtitle: Text(requester['role'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check),
                              color: Colors.green,
                              onPressed: () => _acceptRequest(request['id']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              color: Colors.red,
                              onPressed: () => _declineRequest(request['id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
} 