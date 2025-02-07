Future<void> _loadConnectionRequests() async {
  try {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Get connection requests where user is receiver AND status is pending
    final requests = await supabase
        .from('connections')
        .select('''
          *,
          requester:profiles!requester_id (
            id,
            display_name,
            photo_url,
            role
          )
        ''')
        .eq('receiver_id', currentUserId)
        .eq('status', 'pending');

    if (mounted) {
      setState(() {
        _connectionRequests = List<Map<String, dynamic>>.from(requests);
        _isLoading = false;
      });
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading requests: $e')),
      );
      setState(() => _isLoading = false);
    }
  }
}

Future<void> _acceptConnection(String requesterId) async {
  try {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    await supabase.rpc('accept_connection', params: {
      'p_requester_id': requesterId,
      'p_receiver_id': currentUserId,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection accepted')),
      );
      // Remove this request from the list
      setState(() {
        _connectionRequests.removeWhere(
          (request) => request['requester']['id'] == requesterId
        );
      });
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accepting connection: $e')),
      );
    }
  }
} 