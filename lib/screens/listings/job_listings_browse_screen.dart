import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import 'submit_application_screen.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class JobListingsBrowseScreen extends StatefulWidget {
  const JobListingsBrowseScreen({super.key});

  @override
  State<JobListingsBrowseScreen> createState() => _JobListingsBrowseScreenState();
}

class _JobListingsBrowseScreenState extends State<JobListingsBrowseScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _listings = [];
  String _selectedEmploymentType = 'All';
  final _searchController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(symbol: '\$');
  
  final List<String> _employmentTypes = [
    'All',
    'Full-time',
    'Part-time',
    'Contract',
    'Internship',
  ];

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

      var query = supabase
          .from('job_listings')
          .select('''
            *,
            profiles (
              business_name,
              industry,
              location,
              photo_url
            ),
            job_applications!left (
              status,
              applicant_id
            )
          ''')
          .eq('is_active', true);

      if (_selectedEmploymentType != 'All') {
        query = query.eq('employment_type', _selectedEmploymentType);
      }

      if (_searchController.text.isNotEmpty) {
        query = query.or(
          'title.ilike.%${_searchController.text}%,description.ilike.%${_searchController.text}%'
        );
      }

      final response = await query.order('created_at', ascending: false);

      // Filter job applications to only show the current user's application status
      final listings = List<Map<String, dynamic>>.from(response).map((listing) {
        final applications = (listing['job_applications'] as List)
            .where((app) => app['applicant_id'] == userId)
            .toList();
        return {
          ...listing,
          'job_applications': applications,
        };
      }).toList();

      setState(() {
        _listings = listings;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading listings: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search jobs...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _loadListings(),
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selectedEmploymentType,
            items: _employmentTypes.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedEmploymentType = value;
                });
                _loadListings();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final business = listing['profiles'] as Map<String, dynamic>;
    final minSalary = listing['min_salary'] as num?;
    final maxSalary = listing['max_salary'] as num?;
    final applications = listing['job_applications'] as List;
    final applicationStatus = applications.isNotEmpty ? applications[0]['status'] : null;
    
    String salaryText;
    if (minSalary != null) {
      if (maxSalary != null) {
        salaryText = '${_currencyFormat.format(minSalary)} - ${_currencyFormat.format(maxSalary)}';
      } else {
        salaryText = _currencyFormat.format(minSalary);
      }
    } else {
      salaryText = 'Salary not specified';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showListingDetails(listing),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: business['photo_url'] != null
                        ? NetworkImage(business['photo_url'])
                        : null,
                    child: business['photo_url'] == null
                        ? const Icon(Icons.business)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing['title'],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          business['business_name'] ?? 'Unknown Business',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (applicationStatus != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(applicationStatus).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _getStatusColor(applicationStatus),
                        ),
                      ),
                      child: Text(
                        applicationStatus[0].toUpperCase() + applicationStatus.substring(1),
                        style: TextStyle(
                          color: _getStatusColor(applicationStatus),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.work, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    listing['employment_type'],
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    listing['location'],
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.business_center, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    business['industry'] ?? 'Various Industries',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showListingDetails(Map<String, dynamic> listing) {
    final business = listing['profiles'] as Map<String, dynamic>;
    final minSalary = listing['min_salary'] as num?;
    final maxSalary = listing['max_salary'] as num?;
    final isRemote = listing['is_remote'] ?? false;
    
    String salaryText;
    if (minSalary != null) {
      if (maxSalary != null) {
        salaryText = '${_currencyFormat.format(minSalary)} - ${_currencyFormat.format(maxSalary)}';
      } else if (minSalary >= 500000) {
        salaryText = '\$500,000+';
      } else {
        salaryText = _currencyFormat.format(minSalary);
      }
    } else {
      salaryText = 'Salary not specified';
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: business['photo_url'] != null
                            ? NetworkImage(business['photo_url'])
                            : null,
                        child: business['photo_url'] == null
                            ? const Icon(Icons.business, size: 30)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              listing['title'],
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              business['business_name'] ?? 'Unknown Business',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildDetailSection(
                    'Employment Type',
                    listing['employment_type'],
                    Icons.work,
                  ),
                  _buildDetailSection(
                    'Location',
                    listing['location'],
                    Icons.location_on,
                  ),
                  _buildDetailSection(
                    'Industry',
                    business['industry'] ?? 'Various Industries',
                    Icons.business_center,
                  ),
                  _buildDetailSection(
                    'Salary',
                    salaryText,
                    Icons.attach_money,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Job Description',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    listing['description'],
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Requirements',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    listing['requirements'],
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close the bottom sheet
                        context.push(
                          '/submit-application/${listing['id']}?title=${Uri.encodeComponent(listing['title'])}&business=${Uri.encodeComponent(business['business_name'] ?? 'Unknown Business')}',
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Apply Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailSection(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Browse Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadListings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
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
                              'No job listings found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _loadListings,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _listings.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, index) {
                          return _buildListingCard(_listings[index]);
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
} 