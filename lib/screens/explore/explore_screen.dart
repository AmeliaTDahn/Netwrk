import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import '../messages/chat_screen.dart';
import 'dart:async';
import 'package:collection/collection.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _connectionRequests = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadConnectionRequests();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchUsers(_searchController.text);
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Simplified query first
      final response = await supabase
          .from('profiles')
          .select()
          .neq('id', currentUserId)
          .or('username.ilike.%${query}%,display_name.ilike.%${query}%')
          .limit(20);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error searching users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching users: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  String _getConnectionStatus(Map<String, dynamic> user) {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return 'Connect';

    // Check connections where user is receiver
    final receiverConnections = List<Map<String, dynamic>>.from(user['connections!connections_receiver_id_fkey'] ?? []);
    final asReceiver = receiverConnections.firstWhere(
      (c) => c['requester_id'] == currentUserId,
      orElse: () => {},
    );

    // Check connections where user is requester
    final requesterConnections = List<Map<String, dynamic>>.from(user['connections!connections_requester_id_fkey'] ?? []);
    final asRequester = requesterConnections.firstWhere(
      (c) => c['receiver_id'] == currentUserId,
      orElse: () => {},
    );

    // Return appropriate status
    if (asReceiver.isNotEmpty) {
      return asReceiver['status'] ?? 'Connect';
    }
    if (asRequester.isNotEmpty) {
      return asRequester['status'] ?? 'Connect';
    }
    return 'Connect';
  }

  Widget _buildConnectionButton(Map<String, dynamic> user) {
    final status = _getConnectionStatus(user);
    
    switch (status) {
      case 'pending':
        return TextButton.icon(
          onPressed: null,
          icon: const Icon(Icons.pending, color: Colors.orange),
          label: const Text('Pending', style: TextStyle(color: Colors.orange)),
        );
      case 'accepted':
        return TextButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle, color: Colors.green),
          label: const Text('Connected', style: TextStyle(color: Colors.green)),
        );
      default:
        return TextButton(
          onPressed: () => _connect(user['id']),
          child: const Text('Connect'),
        );
    }
  }

  Future<void> _connect(String userId) async {
    try {
      await supabase.from('connections').insert({
        'requester_id': supabase.auth.currentUser!.id,
        'receiver_id': userId,
        'status': 'pending',
      });

      _searchUsers(_searchController.text); // Refresh results
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting: $e')),
        );
      }
    }
  }

  Future<void> _loadConnectionRequests() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get pending connection requests
      final requests = await supabase
          .from('connections')
          .select('''
            id,
            requester_id,
            status,
            created_at,
            profiles!connections_requester_id_fkey (
              username,
              display_name,
              photo_url
            )
          ''')
          .eq('receiver_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      setState(() {
        _connectionRequests = List<Map<String, dynamic>>.from(requests);
      });
    } catch (e) {
      print('Error loading connection requests: $e');
    }
  }

  Future<void> _handleConnectionRequest(String connectionId, bool accept) async {
    try {
      await supabase
          .from('connections')
          .update({
            'status': accept ? 'accepted' : 'rejected',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', connectionId);

      // Refresh the connection requests
      _loadConnectionRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? 'Connection accepted' : 'Connection rejected'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating connection: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Connection Requests Section
          if (_connectionRequests.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection Requests',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _connectionRequests.length,
                    itemBuilder: (context, index) {
                      final request = _connectionRequests[index];
                      final requester = request['profiles'];
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: requester['photo_url'] != null
                              ? NetworkImage(requester['photo_url'])
                              : null,
                          child: requester['photo_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          requester['display_name'] ?? 
                          requester['username'] ?? 
                          'User'
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _handleConnectionRequest(
                                request['id'], 
                                true
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _handleConnectionRequest(
                                request['id'], 
                                false
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          
          // Search Results Section
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Search for users'
                              : 'No users found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: user['photo_url'] != null
                                  ? NetworkImage(user['photo_url'])
                                  : null,
                              child: user['photo_url'] == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(
                              user['display_name'] ?? 
                              user['username'] ?? 
                              'User'
                            ),
                            subtitle: Text(user['role'] ?? ''),
                            trailing: _buildConnectionButton(user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
} 