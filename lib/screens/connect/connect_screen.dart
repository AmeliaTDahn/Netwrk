import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import '../messages/chat_screen.dart';

const Color primaryBlue = Color(0xFF2196F3);    // Light blue
const Color secondaryBlue = Color(0xFF1565C0);  // Dark blue

class ConnectScreen extends ConsumerStatefulWidget {
  final int? initialTab;

  const ConnectScreen({
    super.key,
    this.initialTab,
  });

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _connectionRequests = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  bool _isLoading = true;
  Timer? _debounce;
  List<Map<String, dynamic>> _businessUsers = [];
  List<Map<String, dynamic>> _employeeUsers = [];
  List<Map<String, dynamic>> _connections = [];
  late TabController _tabController;
  List<Map<String, dynamic>> _discoveredUsers = [];
  List<Map<String, dynamic>> _pendingConnections = [];
  List<Map<String, dynamic>> _connectedUsers = [];
  int _incomingRequestsCount = 0;
  Timer? _refreshTimer;
  late FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab ?? 0,
    );
    _searchController.addListener(_onSearchChanged);
    _loadUsers();
    _loadIncomingRequestsCount();
    // Refresh incoming requests count every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadIncomingRequestsCount();
    });
    _searchFocusNode = FocusNode();
  }

  Future<void> _loadUsers() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Load connected users (accepted connections)
      final connectedResponse = await supabase
          .from('connections')
          .select('''
            *,
            profiles!receiver_id (*),
            requester_profile:profiles!requester_id (*)
          ''')
          .or('and(requester_id.eq.${currentUserId},status.eq.accepted),and(receiver_id.eq.${currentUserId},status.eq.accepted)');

      // Load pending connections where current user is either requester or receiver
      final pendingResponse = await supabase
          .from('connections')
          .select('''
            *,
            profiles!receiver_id (*),
            requester_profile:profiles!requester_id (*)
          ''')
          .or('and(requester_id.eq.${currentUserId},status.eq.pending),and(receiver_id.eq.${currentUserId},status.eq.pending)');

      // Get all users
      final allUsersResponse = await supabase
          .from('profiles')
          .select()
          .neq('id', currentUserId);  // Exclude current user

      // Convert responses to lists
      final connectedUsers = List<Map<String, dynamic>>.from(connectedResponse);
      final pendingUsers = List<Map<String, dynamic>>.from(pendingResponse);
      final allUsers = List<Map<String, dynamic>>.from(allUsersResponse);

      // Get IDs of users who are either connected or have pending connections
      final connectedUserIds = connectedUsers.map((conn) {
        return conn['requester_id'] == currentUserId 
            ? conn['receiver_id'] 
            : conn['requester_id'];
      }).toList();

      final pendingUserIds = pendingUsers.map((conn) {
        return conn['requester_id'] == currentUserId 
            ? conn['receiver_id'] 
            : conn['requester_id'];
      }).toList();

      // Filter discovered users to exclude connected and pending users
      final discoveredUsers = allUsers.where((user) {
        return !connectedUserIds.contains(user['id']) && 
               !pendingUserIds.contains(user['id']);
      }).toList();

      // Filter pending connections to only show outgoing requests
      final outgoingPendingConnections = pendingUsers.where((conn) {
        return conn['requester_id'] == currentUserId;
      }).toList();

      setState(() {
        _connectedUsers = connectedUsers;
        _pendingConnections = outgoingPendingConnections;  // Only show outgoing requests
        _discoveredUsers = discoveredUsers;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() => _isLoading = false);
    }
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

      // Get users matching search query
      final response = await supabase
          .from('profiles')
          .select()
          .neq('id', currentUserId)
          .or('username.ilike.%${query}%,display_name.ilike.%${query}%')
          .limit(20);

      // Get current user's ACTIVE connections only
      final connections = await supabase
          .from('connections')
          .select()
          .or('requester_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
          .or('status.eq.pending,status.eq.accepted');  // Only get active connections

      final users = List<Map<String, dynamic>>.from(response);
      final connectionsList = List<Map<String, dynamic>>.from(connections);

      // Filter out users who have active connections only
      final filteredUsers = users.where((user) {
        final hasActiveConnection = connectionsList.any((conn) {
          final isConnected = (conn['requester_id'] == currentUserId && conn['receiver_id'] == user['id']) ||
                            (conn['receiver_id'] == currentUserId && conn['requester_id'] == user['id']);
          return isConnected;  // We already filtered for active connections in the query
        });
        return !hasActiveConnection;
      }).toList();

      setState(() {
        _searchResults = filteredUsers;
        _isLoading = false;
      });
    } catch (e) {
      print('Error searching users: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadIncomingRequestsCount() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await supabase
          .from('connections')
          .select('id')
          .eq('receiver_id', currentUserId)
          .eq('status', 'pending');

      if (mounted) {
        setState(() {
          _incomingRequestsCount = response.length;
        });
      }
    } catch (e) {
      print('Error loading incoming requests count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  context.push('/connection-requests').then((_) {
                    // Refresh the counts when returning from requests screen
                    _loadIncomingRequestsCount();
                    _loadUsers();
                  });
                },
              ),
              if (_incomingRequestsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _incomingRequestsCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Discover (${_discoveredUsers.length})'),
            Tab(text: 'Pending (${_pendingConnections.length})'),
            Tab(text: 'Connected (${_connectedUsers.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDiscoverList(),
          _buildPendingList(),
          _buildConnectedList(),
        ],
      ),
    );
  }

  Widget _buildDiscoverList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 8,
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: const Icon(Icons.search),
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
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () {
                _searchUsers(value);
              });
            },
          ),
        ),
        
        // Results List
        Expanded(
          child: _searchController.text.isNotEmpty
              ? _buildSearchResults()
              : _buildDiscoveredUsers(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No users found',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _buildUserCard(
          user,
          actionButton: ElevatedButton.icon(
            icon: Icon(
              Icons.person_add_outlined,
              color: Colors.white,
              size: 20,
            ),
            label: const Text(
              'Connect',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => _sendConnectionRequest(user['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: secondaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiscoveredUsers() {
    if (_discoveredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No users to discover',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _discoveredUsers.length,
      itemBuilder: (context, index) {
        final user = _discoveredUsers[index];
        return _buildUserCard(
          user,
          actionButton: ElevatedButton.icon(
            icon: const Icon(
              Icons.person_add_outlined,
              color: Colors.white,
              size: 20,
            ),
            label: const Text(
              'Connect',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => _sendConnectionRequest(user['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: secondaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: _pendingConnections.length,
      itemBuilder: (context, index) {
        final connection = _pendingConnections[index];
        final user = connection['profiles'];
        return _buildUserCard(
          user,
          actionButton: TextButton(
            onPressed: () => _cancelConnectionRequest(connection['id']),
            child: const Text('Cancel Request'),
          ),
        );
      },
    );
  }

  Future<void> _sendConnectionRequest(String receiverId) async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Check if an active connection exists - only check current active connections
      final existingConnection = await supabase
          .from('connections')
          .select()
          .or('and(requester_id.eq.${currentUserId},receiver_id.eq.${receiverId}),and(requester_id.eq.${receiverId},receiver_id.eq.${currentUserId})')
          .eq('status', 'pending')  // Only check for pending connections
          .maybeSingle();

      if (existingConnection != null) {
        // If active connection exists, show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection request already exists')),
          );
        }
        return;
      }

      // Create new connection
      final response = await supabase.from('connections').insert({
        'requester_id': currentUserId,
        'receiver_id': receiverId,
        'status': 'pending',
      }).select().single();

      // Update the UI
      setState(() {
        // Find and remove the user from discovered users
        final userToMove = _discoveredUsers.firstWhere((user) => user['id'] == receiverId);
        _discoveredUsers.removeWhere((user) => user['id'] == receiverId);
        
        // Add to pending connections with correct structure
        _pendingConnections.add({
          'id': response['id'],
          'requester_id': currentUserId,
          'receiver_id': receiverId,
          'status': 'pending',
          'profiles': userToMove, // Add the user profile data
        });
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection request sent!')),
        );
      }
    } catch (e) {
      print('Error sending request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending request: $e')),
        );
      }
    }
  }

  Future<void> _cancelConnectionRequest(String connectionId) async {
    try {
      // Find the connection before deleting it
      final connection = _pendingConnections.firstWhere(
        (conn) => conn['id'] == connectionId,
      );
      
      // Get the other user's profile data
      final currentUserId = supabase.auth.currentUser?.id;
      final otherUserProfile = connection['requester_id'] == currentUserId
          ? connection['profiles']
          : connection['requester_profile'];
      
      // Hard delete the connection from the database
      await supabase
          .from('connections')
          .delete()
          .match({'id': connectionId});

      if (mounted) {
        setState(() {
          // Remove from pending connections
          _pendingConnections.removeWhere((conn) => conn['id'] == connectionId);
          // Add back to discovered users
          _discoveredUsers.add(otherUserProfile);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection request cancelled')),
        );
      }
    } catch (e) {
      print('Error cancelling request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling request: $e')),
        );
      }
    }
  }

  Widget _buildConnectedList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_connectedUsers.isEmpty) {
      return Center(
        child: Text(
          'No connections yet',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _connectedUsers.length,
      itemBuilder: (context, index) {
        final connection = _connectedUsers[index];
        final user = _getOtherUserProfile(connection);
        return _buildUserCard(
          user,
          actionButton: TextButton.icon(
            onPressed: () => _openOrCreateChat(user['id']),
            icon: const Icon(Icons.chat),
            label: const Text('Chat'),
            style: TextButton.styleFrom(
              foregroundColor: primaryBlue,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openOrCreateChat(String otherUserId) async {
    try {
      setState(() => _isLoading = true);
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Try to find existing chat
      final response = await supabase
          .from('chats')
          .select('id')
          .or('and(user1_id.eq.${currentUserId},user2_id.eq.${otherUserId}),and(user1_id.eq.${otherUserId},user2_id.eq.${currentUserId})')
          .maybeSingle();

      String chatId;
      if (response != null) {
        // Existing chat found
        chatId = response['id'];
      } else {
        // Create new chat
        final newChat = await supabase
            .from('chats')
            .insert({
              'user1_id': currentUserId,
              'user2_id': otherUserId,
            })
            .select()
            .single();
        chatId = newChat['id'];
      }

      if (mounted) {
        context.push('/messages/$chatId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening chat: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildUserCard(Map<String, dynamic> user, {required Widget actionButton}) {
    // Add debug print to see the user data
    print('Building card for user: $user');
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _navigateToProfile(user['id'], user['role']),
          child: CircleAvatar(
            backgroundImage: user['photo_url'] != null
                ? NetworkImage(user['photo_url'])
                : null,
            child: user['photo_url'] == null
                ? const Icon(Icons.person)
                : null,
          ),
        ),
        title: GestureDetector(
          onTap: () => _navigateToProfile(user['id'], user['role']),
          child: Text(
            user['display_name'] ?? user['username'] ?? 'User',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        subtitle: Text(user['role'] ?? ''),
        trailing: actionButton,
      ),
    );
  }

  Map<String, dynamic> _getOtherUserProfile(Map<String, dynamic> connection) {
    final currentUserId = supabase.auth.currentUser?.id;
    if (connection['requester_id'] == currentUserId) {
      return connection['profiles'] ?? {};
    } else {
      return connection['requester_profile'] ?? {};
    }
  }

  void _navigateToProfile(String userId, String role) {
    if (role == 'business') {
      context.push('/business-profile/$userId');
    } else {
      context.push('/profile/$userId');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }
} 