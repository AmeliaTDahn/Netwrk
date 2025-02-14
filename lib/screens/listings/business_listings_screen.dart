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
    print('\n=== Starting Business Listings Load ===');
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        print('Error: No authenticated user found');
        return;
      }
      print('Current User ID: $userId');

      // Get user profile to verify business status
      print('\nFetching user profile...');
      final userProfile = await supabase
          .from('profiles')
          .select('account_type, business_name')
          .eq('id', userId)
          .single();
      print('User Profile: ${userProfile.toString()}');
      print('Account Type: ${userProfile['account_type']}');

      print('\nAttempting to load owned listings...');
      // Load owned listings with a simpler query
      final ownedResponse = await supabase
          .from('job_listings')
          .select('''
            *,
            profiles!business_id (
              business_name,
              photo_url
            ),
            job_applications (
              id,
              status,
              applicant_id,
              video_url,
              resume_url,
              cover_note,
              created_at
            )
          ''')
          .eq('business_id', userId)
          .order('created_at', ascending: false);

      print('Owned Listings Response: ${ownedResponse.length} listings found');
      if (ownedResponse.isEmpty) {
        print('No owned listings found. Raw response: $ownedResponse');
      } else {
        print('First owned listing: ${ownedResponse[0]}');
      }

      // Get signed URLs for all videos
      final allVideoUrls = ownedResponse
          .expand((listing) => (listing['job_applications'] as List)
          .where((app) => app['video_url'] != null)
          .map((app) => app['video_url'] as String))
          .toSet();

      print('\n=== Video URL Processing ===');
      print('Total video URLs found: ${allVideoUrls.length}');
      allVideoUrls.forEach((url) => print('Video URL: $url'));

      print('\nFetching signed URLs for ${allVideoUrls.length} videos');
      Map<String, String> signedUrls = {};
      for (var videoUrl in allVideoUrls) {
        try {
          print('\nProcessing video URL: $videoUrl');
          final storagePath = videoUrl.split('applications/').last;
          print('Storage path: $storagePath');
          
          final signedUrl = await supabase.storage
              .from('applications')
              .createSignedUrl(storagePath, 3600);
          print('Generated signed URL: $signedUrl');
          
          signedUrls[videoUrl] = signedUrl;
        } catch (e) {
          print('Error getting signed URL for $videoUrl: $e');
        }
      }

      print('\n=== Signed URLs Summary ===');
      print('Total signed URLs generated: ${signedUrls.length}');
      signedUrls.forEach((original, signed) {
        print('Original: $original');
        print('Signed: $signed\n');
      });

      // If we need applicant profiles, load them separately
      final applicantIds = ownedResponse
          .expand((listing) => (listing['job_applications'] as List)
          .map((app) {
            print('\nExtracting applicant ID from application:');
            print('Application: ${app['id']}');
            print('Applicant ID: ${app['applicant_id']}');
            return app['applicant_id'];
          }))
          .toSet()
          .toList();

      Map<String, dynamic> applicantProfiles = {};
      if (applicantIds.isNotEmpty) {
        print('\n=== Loading Applicant Profiles ===');
        print('Applicant IDs to load: $applicantIds');
        
        // First fetch basic profile information without skills
        print('\nExecuting profiles query...');
        final applicantsResponse = await supabase
            .from('profiles')
            .select('''
              id,
              name,
              photo_url,
              education,
              experience_years
            ''')
            .in_('id', applicantIds);

        // Then fetch skills separately
        print('\nFetching skills for profiles...');
        final skillsResponse = await supabase
            .from('profile_skills')
            .select('''
              profile_id,
              skills (
                name
              )
            ''')
            .in_('profile_id', applicantIds);

        // Create a map of profile_id to skills
        final skillsMap = Map.fromEntries(
          (skillsResponse as List).map((ps) => MapEntry(
            ps['profile_id'],
            (ps['skills'] != null ? [ps['skills']['name'].toString()] : <String>[])
          ))
        );
        
        print('\nTransforming profiles data...');
        applicantProfiles = Map.fromEntries(
          (applicantsResponse as List).map((profile) {
            print('\nProcessing profile: ${profile['id']}');
            
            final result = {
              ...Map<String, dynamic>.from(profile),
              'skills': skillsMap[profile['id']] ?? <String>[]
            };
            print('Final profile data: $result');
            return MapEntry(profile['id'], result);
          })
        );
        
        print('\n=== Applicant Profiles Processing Complete ===');
        print('Total profiles processed: ${applicantProfiles.length}');
        print('Sample profile IDs: ${applicantProfiles.keys.take(3).toList()}');
      }

      print('\nAttempting to load shared listings...');
      // Load shared listings with a simpler query
      final sharedResponse = await supabase
          .from('shared_listings')
          .select('''
            *,
            job_listings!inner (
              *,
              profiles!business_id (
                business_name,
                photo_url
              ),
              job_applications (
                id,
                status,
                applicant_id,
                video_url,
                resume_url,
                cover_note,
                created_at
              )
            )
          ''')
          .eq('shared_with', userId)
          .order('shared_at', ascending: false);

      // Get signed URLs for shared listing videos
      final sharedVideoUrls = sharedResponse
          .expand((shared) => (shared['job_listings']['job_applications'] as List)
          .where((app) => app['video_url'] != null)
          .map((app) => app['video_url'] as String))
          .toSet();

      print('\nFetching signed URLs for ${sharedVideoUrls.length} shared videos');
      for (var videoUrl in sharedVideoUrls) {
        if (!signedUrls.containsKey(videoUrl)) {
          try {
            final storagePath = videoUrl.split('applications/').last;
            final signedUrl = await supabase.storage
                .from('applications')
                .createSignedUrl(storagePath, 3600);
            signedUrls[videoUrl] = signedUrl;
          } catch (e) {
            print('Error getting signed URL for shared video $videoUrl: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          print('\n=== Building Listings State ===');
          // Add applicant profiles and signed video URLs to job applications
          _listings = (ownedResponse as List).map((listing) {
            print('\nProcessing listing: ${listing['id']}');
            print('Applications count: ${(listing['job_applications'] as List).length}');
            
            final applications = ((listing['job_applications'] ?? []) as List).map((app) {
              print('\n=== Processing Application ===');
              print('Application ID: ${app['id']}');
              print('Applicant ID: ${app['applicant_id']}');
              print('Original video URL: ${app['video_url']}');
              
              final profile = applicantProfiles[app['applicant_id']];
              print('Found profile: $profile');
              
              final signedVideoUrl = app['video_url'] != null ? signedUrls[app['video_url']] : null;
              print('Signed video URL: $signedVideoUrl');
              
              final mappedApp = {
                ...Map<String, dynamic>.from(app),
                'profiles': profile,
                'signed_video_url': signedVideoUrl,
              };
              print('Final mapped application: $mappedApp');
              return mappedApp;
            }).toList();
            
            print('\n=== Applications Summary for Listing ===');
            print('Total applications: ${applications.length}');
            print('Applications with videos: ${applications.where((app) => app['signed_video_url'] != null).length}');
            
            final mappedListing = Map<String, dynamic>.from({
              ...listing,
              'job_applications': applications
            });
            print('Final listing structure: $mappedListing');
            return mappedListing;
          }).toList();

          // Add applicant profiles and signed video URLs to shared listings
          _sharedListings = (sharedResponse as List).map((shared) {
            print('\nProcessing shared listing');
            final listing = shared['job_listings'];
            final applications = ((listing['job_applications'] ?? []) as List).map((app) {
              print('\n=== Processing Application ===');
              print('Application ID: ${app['id']}');
              print('Applicant ID: ${app['applicant_id']}');
              print('Original video URL: ${app['video_url']}');
              
              final profile = applicantProfiles[app['applicant_id']];
              print('Found profile: $profile');
              
              final signedVideoUrl = app['video_url'] != null ? signedUrls[app['video_url']] : null;
              print('Signed video URL: $signedVideoUrl');
              
              final mappedApp = {
                ...Map<String, dynamic>.from(app),
                'profiles': profile,
                'signed_video_url': signedVideoUrl,
              };
              print('Final mapped application: $mappedApp');
              return mappedApp;
            }).toList();
            
            final mappedListing = Map<String, dynamic>.from({
              ...Map<String, dynamic>.from(listing),
              'job_applications': applications,
              'shared_by': listing['profiles'],
              'shared_at': shared['shared_at']
            });
            print('Final shared listing structure: $mappedListing');
            return mappedListing;
          }).toList();
          
          _isLoading = false;
        });
        print('\nState Updated:');
        print('Total Owned Listings: ${_listings.length}');
        print('Total Shared Listings: ${_sharedListings.length}');
        print('Total Videos with Signed URLs: ${signedUrls.length}');
        
        // Print sample of final data structure
        if (_listings.isNotEmpty) {
          print('\nSample listing structure:');
          final sampleListing = _listings[0];
          print('Listing ID: ${sampleListing['id']}');
          if ((sampleListing['job_applications'] as List).isNotEmpty) {
            final sampleApp = sampleListing['job_applications'][0];
            print('Sample application:');
            print('- Application ID: ${sampleApp['id']}');
            print('- Profiles data: ${sampleApp['profiles']}');
            print('- Video URL: ${sampleApp['signed_video_url']}');
          }
        }
      }

    } catch (e, stackTrace) {
      print('\n=== Error Loading Listings ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      
      // Try to get more details about the error if it's a PostgrestException
      if (e is PostgrestException) {
        print('Postgrest Error Details:');
        print('Code: ${e.code}');
        print('Message: ${e.message}');
        print('Details: ${e.details}');
        print('Hint: ${e.hint}');
      }

      if (mounted) {
        BannerNotification.show(context, 'Error loading listings: $e');
        setState(() => _isLoading = false);
      }
    } finally {
      print('\n=== Finished Business Listings Load ===\n');
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
    final sharedBy = listing['business'];
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