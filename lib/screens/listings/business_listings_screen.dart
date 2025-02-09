import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../applications/applications_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../components/banner_notification.dart';
import '../listings/listing_details_screen.dart';

class BusinessListingsScreen extends StatefulWidget {
  const BusinessListingsScreen({super.key});

  @override
  State<BusinessListingsScreen> createState() => _BusinessListingsScreenState();
}

class _BusinessListingsScreenState extends State<BusinessListingsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _listings = [];
  List<Map<String, dynamic>> _sharedListings = [];
  final _currencyFormat = NumberFormat.currency(symbol: '\$');
  
  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Load owned listings
      final ownedResponse = await supabase
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
          .eq('business_id', userId)
          .order('created_at', ascending: false);

      // Load shared listings
      final sharedResponse = await supabase
          .from('shared_listings')
          .select('''
            *,
            job_listings!inner (
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
              ),
              shared_by_profile:profiles!business_id (
                id,
                business_name,
                photo_url
              )
            )
          ''')
          .eq('shared_with', userId)
          .order('shared_at', ascending: false);

      setState(() {
        _listings = (ownedResponse as List).map((item) => Map<String, dynamic>.from(item)).toList();
        _sharedListings = (sharedResponse as List).map((shared) => {
              ...Map<String, dynamic>.from(shared['job_listings']),
              'shared_by': shared['shared_by'],
              'shared_at': shared['shared_at'],
            }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        BannerNotification.show(context, 'Error loading listings: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddListingDialog() {
    final _titleController = TextEditingController();
    final _descriptionController = TextEditingController();
    final _locationController = TextEditingController();
    final _requirementsController = TextEditingController();
    final _salaryController = TextEditingController();
    String _employmentType = 'Full-time';
    final _formKey = GlobalKey<FormState>();
    bool _isRemote = false;

    final List<String> _employmentTypes = [
      'Full-time',
      'Part-time',
      'Contract',
      'Internship',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Job Listing'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Job Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a job title';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Job Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a job description';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _locationController,
                          enabled: !_isRemote,
                          decoration: InputDecoration(
                            labelText: 'Location',
                            border: const OutlineInputBorder(),
                            hintText: _isRemote ? 'Remote position' : null,
                            filled: _isRemote,
                            fillColor: _isRemote ? Colors.grey.shade100 : null,
                          ),
                          validator: (value) {
                            if (!_isRemote && (value == null || value.isEmpty)) {
                              return 'Please enter a location';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          children: [
                            const Text(
                              'Remote',
                              style: TextStyle(fontSize: 12),
                            ),
                            Switch(
                              value: _isRemote,
                              onChanged: (value) {
                                setState(() {
                                  _isRemote = value;
                                  if (value) {
                                    _locationController.clear();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _salaryController,
                    decoration: const InputDecoration(
                      labelText: 'Salary',
                      border: OutlineInputBorder(),
                      prefixText: '\$',
                      hintText: 'e.g. 75000',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a salary';
                      }
                      final salary = int.tryParse(value.replaceAll(',', ''));
                      if (salary == null || salary <= 0) {
                        return 'Please enter a valid salary';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _requirementsController,
                    decoration: const InputDecoration(
                      labelText: 'Requirements',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter job requirements';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _employmentType,
                    decoration: const InputDecoration(
                      labelText: 'Employment Type',
                      border: OutlineInputBorder(),
                    ),
                    items: _employmentTypes.map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _employmentType = value;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  try {
                    final userId = supabase.auth.currentUser?.id;
                    if (userId == null) return;

                    final salary = int.parse(_salaryController.text.replaceAll(',', ''));

                    await supabase.from('job_listings').insert({
                      'business_id': userId,
                      'title': _titleController.text,
                      'description': _descriptionController.text,
                      'location': _isRemote ? 'Remote' : _locationController.text,
                      'is_remote': _isRemote,
                      'salary': salary,
                      'requirements': _requirementsController.text,
                      'employment_type': _employmentType,
                      'is_active': true,
                      'created_at': DateTime.now().toIso8601String(),
                    });

                    if (mounted) {
                      Navigator.pop(context);
                      _loadListings();
                      BannerNotification.show(context, 'Job listing added successfully');
                    }
                  } catch (e) {
                    BannerNotification.show(context, 'Error adding listing: $e');
                  }
                }
              },
              child: const Text('Add Listing'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleListingStatus(String listingId, bool currentStatus) async {
    try {
      // Update the database
      await supabase
          .from('job_listings')
          .update({'is_active': !currentStatus})
          .eq('id', listingId);

      // Update local state
      setState(() {
        final listingIndex = _listings.indexWhere((listing) => listing['id'] == listingId);
        if (listingIndex != -1) {
          _listings[listingIndex]['is_active'] = !currentStatus;
        }
      });
    } catch (e) {
      if (mounted) {
        BannerNotification.show(context, 'Error updating listing: $e');
        // Revert the local state if the update failed
        setState(() {
          final listingIndex = _listings.indexWhere((listing) => listing['id'] == listingId);
          if (listingIndex != -1) {
            _listings[listingIndex]['is_active'] = currentStatus;
          }
        });
      }
    }
  }

  Future<void> _deleteListing(String listingId) async {
    try {
      await supabase
          .from('job_listings')
          .delete()
          .eq('id', listingId);

      _loadListings();
      if (mounted) {
        BannerNotification.show(context, 'Job listing deleted successfully');
      }
    } catch (e) {
      if (mounted) {
        BannerNotification.show(context, 'Error deleting listing: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Listings'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadListings,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Listings'),
              Tab(text: 'Shared with Me'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // My Listings Tab
            RefreshIndicator(
              onRefresh: () async {
                await _loadListings();
              },
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _listings.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.work_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No job listings yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to create your first listing',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: _showAddListingDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Create Listing'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _listings.length,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemBuilder: (context, index) {
                            return _buildListingCard(_listings[index]);
                          },
                        ),
            ),
            // Shared Listings Tab
            RefreshIndicator(
              onRefresh: () async {
                await _loadListings();
              },
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _sharedListings.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.share,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No shared listings',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Listings shared with you will appear here',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _sharedListings.length,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemBuilder: (context, index) {
                            return _buildSharedListingCard(_sharedListings[index]);
                          },
                        ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddListingDialog,
          tooltip: 'Create New Listing',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final isActive = listing['is_active'] ?? false;
    final salary = listing['salary'] as num?;
    final isRemote = listing['is_remote'] ?? false;
    final applications = listing['job_applications'] as List;
    final isOwner = listing['business_id'] == supabase.auth.currentUser?.id;
    
    String salaryText = salary != null 
        ? _currencyFormat.format(salary)
        : 'Salary not specified';
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ListingDetailsScreen(listing: listing),
            ),
          ).then((_) => _loadListings()); // Refresh listings when returning
        },
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          title: Text(
            listing['title'],
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(listing['employment_type']),
              Row(
                children: [
                  Text(listing['location']),
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
              Text(salaryText),
              const SizedBox(height: 4),
              Text(
                '${applications.length} application${applications.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          trailing: isOwner ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: isActive,
                onChanged: (value) => _toggleListingStatus(
                  listing['id'],
                  isActive,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _deleteListing(listing['id']),
              ),
            ],
          ) : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                color: isActive ? Colors.green : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          isThreeLine: true,
        ),
      ),
    );
  }

  Widget _buildSharedListingCard(Map<String, dynamic> listing) {
    final isActive = listing['is_active'] ?? false;
    final salary = listing['salary'] as num?;
    final isRemote = listing['is_remote'] ?? false;
    final applications = listing['job_applications'] as List;
    final sharedBy = listing['shared_by_profile'];
    final sharedAt = DateTime.parse(listing['shared_at']);
    
    String salaryText = salary != null 
        ? _currencyFormat.format(salary)
        : 'Salary not specified';
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ListingDetailsScreen(listing: listing),
            ),
          ).then((_) => _loadListings());
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            ListTile(
              title: Text(
                listing['title'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(listing['employment_type']),
                  Row(
                    children: [
                      Text(listing['location']),
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
                  Text(salaryText),
                  const SizedBox(height: 4),
                  Text(
                    '${applications.length} application${applications.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    color: isActive ? Colors.green : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: sharedBy['photo_url'] != null
                        ? NetworkImage(sharedBy['photo_url'])
                        : null,
                    child: sharedBy['photo_url'] == null
                        ? const Icon(Icons.business, size: 12)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shared by ${sharedBy['business_name']} · ${timeago.format(sharedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 