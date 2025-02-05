import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
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
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
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
      final response = await supabase
          .from('profiles')
          .select('''
            id,
            display_name,
            photo_url,
            role,
            connections!connections_requester_id_fkey(status, receiver_id),
            connections!connections_receiver_id_fkey(status, requester_id)
          ''')
          .ilike('display_name', '%$query%')
          .neq('id', supabase.auth.currentUser?.id)
          .limit(20);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching users: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connect(String userId) async {
    try {
      // Create connection request
      await supabase.from('connections').insert({
        'requester_id': supabase.auth.currentUser?.id,
        'receiver_id': userId,
      });

      // Create conversation
      final conversationResponse = await supabase
          .from('conversations')
          .insert({})
          .select()
          .single();

      // Add participants
      await supabase.from('conversation_participants').insert([
        {
          'conversation_id': conversationResponse['id'],
          'user_id': supabase.auth.currentUser?.id,
        },
        {
          'conversation_id': conversationResponse['id'],
          'user_id': userId,
        },
      ]);

      if (mounted) {
        // Navigate to chat
        final userResponse = await supabase
            .from('profiles')
            .select()
            .eq('id', userId)
            .single();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationResponse['id'],
              otherUser: {'profiles': userResponse},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting with user: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
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
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Search for users to connect'
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
                          final connections = [
                            ...List<Map<String, dynamic>>.from(
                                user['connections_requester_id_fkey']),
                            ...List<Map<String, dynamic>>.from(
                                user['connections_receiver_id_fkey']),
                          ];
                          
                          final existingConnection = connections.firstWhereOrNull(
                            (c) => c['requester_id'] == supabase.auth.currentUser?.id ||
                                   c['receiver_id'] == supabase.auth.currentUser?.id,
                          );

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: user['photo_url'] != null
                                  ? NetworkImage(user['photo_url'])
                                  : null,
                              child: user['photo_url'] == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(user['display_name'] ?? 'User'),
                            subtitle: Text(user['role'] ?? ''),
                            trailing: TextButton(
                              onPressed: existingConnection != null
                                  ? null
                                  : () => _connect(user['id']),
                              child: Text(
                                existingConnection == null
                                    ? 'Connect'
                                    : existingConnection['status'] == 'pending'
                                        ? 'Pending'
                                        : 'Connected',
                              ),
                            ),
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