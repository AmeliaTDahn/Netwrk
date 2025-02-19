import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import 'package:go_router/go_router.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  
  const UserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isPendingConnection = false;
  bool _isLoadingConnection = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _checkConnectionStatus();
  }

  Future<void> _loadUserProfile() async {
    try {
      final response = await supabase
          .from('profiles')
          .select()  // This will select all columns
          .eq('id', widget.userId)
          .single();

      if (mounted) {
        setState(() {
          _userProfile = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await supabase
          .from('connections')
          .select()
          .or('and(requester_id.eq.${currentUserId},receiver_id.eq.${widget.userId}),and(requester_id.eq.${widget.userId},receiver_id.eq.${currentUserId})')
          .single();

      if (mounted) {
        setState(() {
          _isConnected = response['status'] == 'accepted';
          _isPendingConnection = response['status'] == 'pending' && 
              (response['requester_id'] == currentUserId || response['receiver_id'] == currentUserId);
        });
      }
    } catch (e) {
      // No connection found
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isPendingConnection = false;
        });
      }
    }
  }

  Future<void> _handleConnect() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    setState(() => _isLoadingConnection = true);

    try {
      if (_isConnected) {
        // Show confirmation dialog before disconnecting
        final shouldDisconnect = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Disconnect'),
            content: const Text('Are you sure you want to disconnect? This will remove your connection and chat history.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        );

        if (shouldDisconnect == true) {
          // Delete the connection
          await supabase
              .from('connections')
              .delete()
              .or('and(requester_id.eq.${currentUserId},receiver_id.eq.${widget.userId}),and(requester_id.eq.${widget.userId},receiver_id.eq.${currentUserId})');

          if (mounted) {
            setState(() {
              _isConnected = false;
              _isPendingConnection = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Connection removed')),
            );
          }
        }
      } else if (!_isPendingConnection) {
        // Send connection request
        await supabase.from('connections').insert({
          'requester_id': currentUserId,
          'receiver_id': widget.userId,
          'status': 'pending',
        });

        // Update local state immediately after successful request
        if (mounted) {
          setState(() {
            _isPendingConnection = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection request sent!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingConnection = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userProfile == null) {
      return const Scaffold(
        body: Center(child: Text('User not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_userProfile!['display_name'] ?? _userProfile!['username'] ?? 'Profile'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header with Background
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Profile Picture
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.white,
                        backgroundImage: _userProfile!['photo_url'] != null
                            ? NetworkImage(_userProfile!['photo_url'])
                            : null,
                        child: _userProfile!['photo_url'] == null
                            ? const Icon(Icons.person, size: 60, color: Colors.grey)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Name and Role
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          Text(
                            _userProfile!['display_name'] ?? _userProfile!['username'] ?? 'User',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _userProfile!['role'] ?? '',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          if (_userProfile!['location'] != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _userProfile!['location'],
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          _buildConnectButton(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Profile Sections
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // About Section
                  if (_userProfile!['bio'] != null && _userProfile!['bio'].toString().isNotEmpty) ...[
                    _buildSection(
                      title: 'About',
                      icon: Icons.person_outline,
                      child: Text(
                        _userProfile!['bio'],
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Experience Section
                  if (_userProfile!['experience'] != null && _userProfile!['experience'].toString().isNotEmpty) ...[
                    _buildSection(
                      title: 'Experience',
                      icon: Icons.work_outline,
                      child: Text(
                        _userProfile!['experience'],
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Education Section
                  if (_userProfile!['education'] != null && _userProfile!['education'].toString().isNotEmpty) ...[
                    _buildSection(
                      title: 'Education',
                      icon: Icons.school_outlined,
                      child: Text(
                        _userProfile!['education'],
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Skills Section
                  if (_userProfile!['skills'] != null) ...[
                    _buildSection(
                      title: 'Skills',
                      icon: Icons.psychology_outlined,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_userProfile!['skills'].toString()
                                .replaceAll('[', '')
                                .replaceAll(']', '')
                                .split(','))
                            .where((skill) => skill.trim().isNotEmpty)
                            .map((skill) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    skill.trim(),
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Contact Information
                  if (_userProfile!['email'] != null || 
                      _userProfile!['phone'] != null || 
                      _userProfile!['website'] != null) ...[
                    _buildSection(
                      title: 'Contact Information',
                      icon: Icons.contact_mail_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_userProfile!['email'] != null)
                            _buildContactRow(Icons.email_outlined, _userProfile!['email']),
                          if (_userProfile!['phone'] != null)
                            _buildContactRow(Icons.phone_outlined, _userProfile!['phone']),
                          if (_userProfile!['website'] != null)
                            _buildContactRow(Icons.language_outlined, _userProfile!['website']),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton() {
    if (_userProfile!['id'] == supabase.auth.currentUser?.id) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 140,
      child: ElevatedButton(
        onPressed: _isLoadingConnection ? null : _handleConnect,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isConnected 
              ? Colors.red 
              : _isPendingConnection 
                  ? Colors.orange 
                  : Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          minimumSize: const Size(140, 45),
        ),
        child: _isLoadingConnection
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            : Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isConnected 
                        ? Icons.person_remove 
                        : _isPendingConnection 
                            ? Icons.pending_outlined 
                            : Icons.person_add,
                        size: 20),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected 
                          ? 'Disconnect' 
                          : _isPendingConnection 
                              ? 'Pending' 
                              : 'Connect',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
} 