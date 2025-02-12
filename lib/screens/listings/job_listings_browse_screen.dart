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

  RangeValues _salaryRange = const RangeValues(0, 500000);
  bool _showFilters = false;

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

      final response = await supabase
          .from('job_listings')
          .select('''
            *,
            profiles!business_id (
              id,
              business_name,
              photo_url,
              location,
              industry
            ),
            job_applications!job_listing_id (
              id,
              status,
              applicant_id
            )
          ''')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      setState(() {
        _listings = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading listings: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _filterListings(List<Map<String, dynamic>> listings) {
    return listings.where((listing) {
      final business = listing['profiles'] as Map<String, dynamic>;
      final minSalary = listing['min_salary'] as num? ?? 0;
      final maxSalary = listing['max_salary'] as num? ?? minSalary;
      
      // Filter by search text
      final searchText = _searchController.text.toLowerCase();
      final matchesSearch = listing['title'].toString().toLowerCase().contains(searchText) ||
          business['business_name'].toString().toLowerCase().contains(searchText) ||
          listing['description'].toString().toLowerCase().contains(searchText);

      // Filter by employment type
      final matchesType = _selectedEmploymentType == 'All' ||
          listing['employment_type'] == _selectedEmploymentType;

      // Filter by salary range
      final matchesSalary = maxSalary >= _salaryRange.start &&
          minSalary <= _salaryRange.end;

      return matchesSearch &&
          matchesType &&
          matchesSalary;
    }).toList();
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

  Widget _buildFilterSheet() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[300]!,
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filter Jobs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Salary Range',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          RangeSlider(
            values: _salaryRange,
            min: 0,
            max: 500000,
            divisions: 50,
            labels: RangeLabels(
              '\$${_salaryRange.start.round()}',
              '\$${_salaryRange.end.round()}',
            ),
            onChanged: (values) {
              setState(() {
                _salaryRange = values;
              });
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _salaryRange = const RangeValues(0, 500000);
                      _selectedEmploymentType = 'All';
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Column(
        children: [
          Row(
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
                  onChanged: (value) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: _showFilters ? Theme.of(context).primaryColor : null,
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => _buildFilterSheet(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._employmentTypes.map((type) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: _selectedEmploymentType == type,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedEmploymentType = type);
                      }
                    },
                  ),
                )),
              ],
            ),
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
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
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
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    listing['location'],
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
    final userId = supabase.auth.currentUser?.id;
    final applications = listing['job_applications'] as List;
    final hasApplied = applications.any((app) => app['applicant_id'] == userId);
    final applicationStatus = hasApplied 
        ? applications.firstWhere((app) => app['applicant_id'] == userId)['status']
        : null;
    
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
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // Close the bottom sheet
                          context.push('/business-profile/${business['id']}');
                        },
                        child: CircleAvatar(
                          radius: 30,
                          backgroundImage: business['photo_url'] != null
                              ? NetworkImage(business['photo_url'])
                              : null,
                          child: business['photo_url'] == null
                              ? const Icon(Icons.business, size: 30)
                              : null,
                        ),
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
                            InkWell(
                              onTap: () {
                                Navigator.pop(context); // Close the bottom sheet
                                context.push('/business-profile/${business['id']}');
                              },
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      business['business_name'] ?? 'Unknown Business',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ],
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
                  if (hasApplied) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _getStatusColor(applicationStatus!).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getStatusColor(applicationStatus),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Application Status',
                            style: TextStyle(
                              color: _getStatusColor(applicationStatus),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            applicationStatus[0].toUpperCase() + applicationStatus.substring(1),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(applicationStatus),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close the bottom sheet
                          context.push(
                            '/submit-application/${listing['id']}?title=${Uri.encodeComponent(listing['title'])}&business=${Uri.encodeComponent(business['business_name'] ?? 'Unknown Business')}&description=${Uri.encodeComponent(listing['description'] ?? '')}&requirements=${Uri.encodeComponent(listing['requirements'] ?? '')}',
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
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
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
            // Add TabBar for filtering
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey[200]!,
                    width: 1,
                  ),
                ),
              ),
              child: TabBar(
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Applied'),
                ],
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 16,
                ),
                indicatorColor: Colors.black,
                indicatorWeight: 2,
              ),
            ),
            _buildSearchBar(),
            // Add TabBarView for content
            Expanded(
              child: TabBarView(
                children: [
                  // All listings tab
                  RefreshIndicator(
                    onRefresh: () async {
                      await _loadListings();
                    },
                    child: _buildListingsView(),
                  ),
                  // Applied listings tab
                  RefreshIndicator(
                    onRefresh: () async {
                      await _loadListings();
                    },
                    child: _buildAppliedListingsView(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredListings = _filterListings(_listings);

    if (filteredListings.isEmpty) {
      return Center(
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
            if (_searchController.text.isNotEmpty ||
                _selectedEmploymentType != 'All' ||
                _salaryRange != const RangeValues(0, 500000))
              TextButton(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _selectedEmploymentType = 'All';
                    _salaryRange = const RangeValues(0, 500000);
                  });
                },
                child: const Text('Clear Filters'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredListings.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        return _buildListingCard(filteredListings[index]);
      },
    );
  }

  Widget _buildAppliedListingsView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final userId = supabase.auth.currentUser?.id;
    final appliedListings = _listings.where((listing) {
      final applications = listing['job_applications'] as List;
      return applications.any((app) => app['applicant_id'] == userId);
    }).toList();

    if (appliedListings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No applications yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start applying to jobs to see them here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: appliedListings.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        return _buildListingCard(appliedListings[index]);
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
} 