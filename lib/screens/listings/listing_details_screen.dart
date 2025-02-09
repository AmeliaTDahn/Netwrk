import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../applications/applications_screen.dart';
import '../../components/banner_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';

class ListingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> listing;

  const ListingDetailsScreen({
    super.key,
    required this.listing,
  });

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  final _currencyFormat = NumberFormat.currency(symbol: '\$');
  bool _isLoading = false;
  Map<String, dynamic>? _updatedListing;
  List<Map<String, dynamic>> _sharedUsers = [];

  @override
  void initState() {
    super.initState();
    _updatedListing = widget.listing;
    _refreshListing();
    _loadSharedUsers();
  }

  Future<void> _refreshListing() async {
    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('job_listings')
          .select('''
            *,
            job_applications (
              id,
              status,
              applicant_id,
              video_url,
              resume_url,
              cover_note,
              created_at,
              profiles!applicant_id (
                id,
                name,
                photo_url,
                education,
                experience_years,
                skills
              )
            )
          ''')
          .eq('id', widget.listing['id'])
          .single();

      if (mounted) {
        setState(() {
          _updatedListing = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        BannerNotification.show(context, 'Error refreshing listing: $e');
      }
    }
  }

  Future<void> _toggleListingStatus() async {
    final currentStatus = _updatedListing?['is_active'] ?? false;
    
    try {
      await supabase
          .from('job_listings')
          .update({'is_active': !currentStatus})
          .eq('id', _updatedListing?['id']);

      setState(() {
        if (_updatedListing != null) {
          _updatedListing!['is_active'] = !currentStatus;
        }
      });
    } catch (e) {
      if (mounted) {
        BannerNotification.show(context, 'Error updating listing status: $e');
      }
    }
  }

  Future<void> _loadSharedUsers() async {
    try {
      final response = await supabase
          .from('shared_listings')
          .select('''
            *,
            shared_with_profile:profiles!shared_with (
              id,
              name,
              business_name,
              photo_url
            )
          ''')
          .eq('listing_id', widget.listing['id']);

      if (mounted) {
        setState(() {
          _sharedUsers = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error loading shared users: $e');
    }
  }

  Future<void> _shareWithBusinesses() async {
    try {
      // Get list of business profiles
      final response = await supabase
          .from('profiles')
          .select()
          .eq('account_type', 'business')
          .neq('id', supabase.auth.currentUser?.id);

      if (!mounted) return;

      final businesses = List<Map<String, dynamic>>.from(response);
      
      // Show business selection dialog
      final selectedBusinesses = await showDialog<List<String>>(
        context: context,
        builder: (context) => _ShareListingDialog(
          businesses: businesses,
          alreadySharedWith: _sharedUsers.map((u) => u['shared_with'] as String).toList(),
        ),
      );

      if (selectedBusinesses == null || selectedBusinesses.isEmpty) return;

      // Share with selected businesses
      for (final businessId in selectedBusinesses) {
        await supabase.from('shared_listings').insert({
          'listing_id': widget.listing['id'],
          'shared_by': supabase.auth.currentUser?.id,
          'shared_with': businessId,
          'shared_at': DateTime.now().toIso8601String(),
        });
      }

      _loadSharedUsers();
      BannerNotification.show(context, 'Listing shared successfully');
    } catch (e) {
      print('Error sharing listing: $e');
      if (mounted) {
        BannerNotification.show(context, 'Error sharing listing: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_updatedListing == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isActive = _updatedListing!['is_active'] ?? false;
    final salary = _updatedListing!['salary'] as num?;
    final isRemote = _updatedListing!['is_remote'] ?? false;
    final applications = _updatedListing!['job_applications'] as List;
    final createdAt = DateTime.parse(_updatedListing!['created_at']);
    final isOwner = _updatedListing!['business_id'] == supabase.auth.currentUser?.id;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing Details'),
        actions: [
          if (isOwner) ...[
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareWithBusinesses,
              tooltip: 'Share with other businesses',
            ),
            Switch(
              value: isActive,
              onChanged: (value) => _toggleListingStatus(),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshListing,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshListing,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          color: isActive ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Title
                    Text(
                      _updatedListing!['title'],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Key details
                    Row(
                      children: [
                        Icon(Icons.work, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _updatedListing!['employment_type'],
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _updatedListing!['location'],
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        if (isRemote) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue),
                            ),
                            child: const Text(
                              'Remote',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Salary
                    Row(
                      children: [
                        Icon(Icons.attach_money, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          salary != null ? _currencyFormat.format(salary) : 'Salary not specified',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Posted date
                    Text(
                      'Posted ${timeago.format(createdAt)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Description section
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_updatedListing!['description']),
                    const SizedBox(height: 24),
                    
                    // Requirements section
                    const Text(
                      'Requirements',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_updatedListing!['requirements']),
                    const SizedBox(height: 32),
                    
                    // Acceptance Message Template section
                    const Text(
                      'Acceptance Message Template',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isOwner) ...[
                      TextFormField(
                        initialValue: _updatedListing!['acceptance_message_template'] ?? 
                            'Congratulations! We are pleased to inform you that we would like to offer you the position. We believe your skills and experience will be a great addition to our team.',
                        decoration: const InputDecoration(
                          hintText: 'Enter message to send when accepting candidates',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (value) async {
                          try {
                            await supabase
                                .from('job_listings')
                                .update({'acceptance_message_template': value})
                                .eq('id', _updatedListing!['id']);
                            
                            setState(() {
                              _updatedListing!['acceptance_message_template'] = value;
                            });
                          } catch (e) {
                            if (mounted) {
                              BannerNotification.show(context, 'Error updating acceptance message: $e');
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This message will be automatically sent to candidates when you accept their application.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else
                      Text(_updatedListing!['acceptance_message_template'] ?? 
                          'Congratulations! We are pleased to inform you that we would like to offer you the position. We believe your skills and experience will be a great addition to our team.'),
                    
                    const SizedBox(height: 32),
                    
                    // Interview Message Template Section
                    const Text(
                      'Interview Message Template',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isOwner) ...[
                      TextFormField(
                        initialValue: _updatedListing!['interview_message_template'] ?? 
                            'Hi! Thanks for applying. We would like to schedule an interview with you. Please let me know your availability for this week.',
                        decoration: const InputDecoration(
                          hintText: 'Enter message to send when scheduling interviews',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (value) async {
                          try {
                            await supabase
                                .from('job_listings')
                                .update({'interview_message_template': value})
                                .eq('id', _updatedListing!['id']);
                            
                            setState(() {
                              _updatedListing!['interview_message_template'] = value;
                            });
                          } catch (e) {
                            if (mounted) {
                              BannerNotification.show(context, 'Error updating interview message: $e');
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This message will be automatically sent to candidates when you schedule an interview.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else
                      Text(_updatedListing!['interview_message_template'] ?? 
                          'Hi! Thanks for applying. We would like to schedule an interview with you. Please let me know your availability for this week.'),
                    
                    const SizedBox(height: 32),
                    
                    // Applications section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Applications (${applications.length})',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ApplicationsScreen(
                                  jobListingId: _updatedListing!['id'],
                                ),
                              ),
                            );
                          },
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Applications summary
                    if (applications.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No applications yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: applications.length,
                        itemBuilder: (context, index) {
                          final application = applications[index];
                          final applicant = application['profiles'];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: applicant['photo_url'] != null
                                        ? NetworkImage(applicant['photo_url'])
                                        : null,
                                    child: applicant['photo_url'] == null
                                        ? const Icon(Icons.person)
                                        : null,
                                  ),
                                  title: Text(
                                    applicant['name'] ?? 'Anonymous',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Applied ${timeago.format(DateTime.parse(application['created_at']))}',
                                      ),
                                      Text(
                                        'Status: ${application['status']}'.toUpperCase(),
                                        style: TextStyle(
                                          color: _getStatusColor(application['status']),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ApplicationsScreen(
                                                jobListingId: _updatedListing!['id'],
                                                filterStatus: application['status'],
                                                singleApplicationId: application['id'],
                                                showFolderView: false,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.play_circle_outline),
                                        label: const Text('View Application'),
                                        style: ElevatedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor: Theme.of(context).primaryColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
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
                  ],
                ),
              ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'interviewing':
        return Colors.blue;
      case 'saved':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class _ShareListingDialog extends StatefulWidget {
  final List<Map<String, dynamic>> businesses;
  final List<String> alreadySharedWith;

  const _ShareListingDialog({
    required this.businesses,
    required this.alreadySharedWith,
  });

  @override
  _ShareListingDialogState createState() => _ShareListingDialogState();
}

class _ShareListingDialogState extends State<_ShareListingDialog> {
  final Set<String> _selectedBusinesses = {};
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredBusinesses = widget.businesses.where((business) {
      final name = business['business_name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) &&
             !widget.alreadySharedWith.contains(business['id']);
    }).toList();

    return AlertDialog(
      title: const Text('Share with Businesses'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search businesses...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 16),
            if (widget.alreadySharedWith.isNotEmpty) ...[
              const Text(
                'Already shared with:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.businesses
                  .where((b) => widget.alreadySharedWith.contains(b['id']))
                  .map((b) => ListTile(
                        leading: CircleAvatar(
                          backgroundImage: b['photo_url'] != null
                              ? NetworkImage(b['photo_url'])
                              : null,
                          child: b['photo_url'] == null
                              ? const Icon(Icons.business)
                              : null,
                        ),
                        title: Text(b['business_name'] ?? 'Unknown Business'),
                        dense: true,
                        enabled: false,
                      )),
              const Divider(),
            ],
            Expanded(
              child: filteredBusinesses.isEmpty
                  ? const Center(
                      child: Text('No businesses found'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredBusinesses.length,
                      itemBuilder: (context, index) {
                        final business = filteredBusinesses[index];
                        final businessId = business['id'];
                        final businessName = business['business_name'] ?? 'Unknown Business';

                        return CheckboxListTile(
                          value: _selectedBusinesses.contains(businessId),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedBusinesses.add(businessId);
                              } else {
                                _selectedBusinesses.remove(businessId);
                              }
                            });
                          },
                          title: Text(businessName),
                          secondary: CircleAvatar(
                            backgroundImage: business['photo_url'] != null
                                ? NetworkImage(business['photo_url'])
                                : null,
                            child: business['photo_url'] == null
                                ? const Icon(Icons.business)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedBusinesses.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedBusinesses.toList()),
          child: const Text('Share'),
        ),
      ],
    );
  }
} 