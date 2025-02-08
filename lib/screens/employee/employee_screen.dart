import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum SortBy {
  newest,
  salary,
  distance,
}

class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _listings = [];
  final _searchController = TextEditingController();
  final _locationController = TextEditingController();
  String _selectedEmploymentType = 'All';
  final _currencyFormat = NumberFormat.currency(symbol: '\$');
  SortBy _sortBy = SortBy.newest;
  RangeValues _salaryRange = const RangeValues(0, 500000);
  double _maxDistance = 50;
  bool _showFilters = false;
  Location? _userLocation;
  final _distanceCalculator = const Distance();
  List<String> _locationSuggestions = [];
  bool _isLoadingLocation = false;
  
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

  Future<Location?> _getLocationFromAddress(String address) async {
    if (address.isEmpty) return null;
    
    try {
      setState(() => _isLoadingLocation = true);
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return locations.first;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not find location: "${address}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
    return null;
  }

  Future<void> _updateUserLocation(String address) async {
    if (address.length < 3) {
      setState(() => _userLocation = null);
      return;
    }

    final location = await _getLocationFromAddress(address);
    if (mounted) {
      setState(() {
        _userLocation = location;
      });
      if (location != null) {
        _loadListings();
      }
    }
  }

  double _calculateDistance(Location location1, Location location2) {
    return _distanceCalculator.as(
      LengthUnit.Mile,
      LatLng(location1.latitude, location1.longitude),
      LatLng(location2.latitude, location2.longitude),
    );
  }

  Future<void> _loadListings() async {
    setState(() => _isLoading = true);

    try {
      var query = supabase
          .from('job_listings')
          .select('''
            *,
            profiles (
              business_name,
              industry,
              location,
              photo_url,
              latitude,
              longitude
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

      query = query.gte('min_salary', _salaryRange.start)
                  .lte('max_salary', _salaryRange.end);

      final response = await query.order('created_at', ascending: false);
      var listings = List<Map<String, dynamic>>.from(response);

      // Filter and sort by location if user location is provided
      if (_userLocation != null && _locationController.text.isNotEmpty) {
        listings = await Future.wait(listings.map((listing) async {
          final businessLocation = listing['location']?.toString();
          if (businessLocation != null && !listing['is_remote']) {
            try {
              final locations = await locationFromAddress(businessLocation);
              if (locations.isNotEmpty) {
                final distance = _calculateDistance(_userLocation!, locations.first);
                return {
                  ...listing,
                  'distance': distance,
                };
              }
            } catch (e) {
              // Skip listings with invalid addresses
              return null;
            }
          }
          // Include remote listings with null distance
          return {...listing, 'distance': null};
        }))
        .then((listings) => listings.whereType<Map<String, dynamic>>().where((listing) {
          final distance = listing['distance'];
          return distance == null || distance <= _maxDistance;
        }).toList());
      }

      // Sort listings
      switch (_sortBy) {
        case SortBy.newest:
          listings.sort((a, b) => (b['created_at'] as String)
              .compareTo(a['created_at'] as String));
          break;
        case SortBy.salary:
          listings.sort((a, b) {
            final aMinSalary = a['min_salary'] as num? ?? 0;
            final bMinSalary = b['min_salary'] as num? ?? 0;
            return bMinSalary.compareTo(aMinSalary);
          });
          break;
        case SortBy.distance:
          if (_userLocation != null) {
            listings.sort((a, b) {
              final aDistance = a['distance'] as double?;
              final bDistance = b['distance'] as double?;
              if (aDistance == null && bDistance == null) return 0;
              if (aDistance == null) return 1;
              if (bDistance == null) return -1;
              return aDistance.compareTo(bDistance);
            });
          }
          break;
      }

      setState(() {
        _listings = listings;
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

  Widget _buildSearchBar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search and filter toggle
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search jobs...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _loadListings(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(
                      _showFilters ? Icons.filter_list_off : Icons.filter_list,
                      color: _showFilters ? Theme.of(context).primaryColor : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _showFilters = !_showFilters;
                      });
                    },
                  ),
                ],
              ),
              if (_showFilters) ...[
                const SizedBox(height: 16),
                // Location and distance
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: GooglePlaceAutoCompleteTextField(
                          textEditingController: _locationController,
                          googleAPIKey: dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '',
                          inputDecoration: InputDecoration(
                            hintText: 'Enter location...',
                            prefixIcon: const Icon(Icons.location_on),
                            suffixIcon: _isLoadingLocation
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          debounceTime: 800,
                          countries: const ["us"],  // Limit to US addresses
                          isLatLngRequired: true,
                          getPlaceDetailWithLatLng: (Prediction? prediction) {
                            if (prediction == null) return;
                            
                            final lat = prediction.lat;
                            final lng = prediction.lng;
                            
                            if (lat != null && lng != null) {
                              setState(() {
                                _userLocation = Location(
                                  latitude: double.tryParse(lat) ?? 0.0,
                                  longitude: double.tryParse(lng) ?? 0.0,
                                  timestamp: DateTime.now(),
                                );
                              });
                              _loadListings();
                            }
                          },
                          itemClick: (Prediction? prediction) {
                            if (prediction == null) return;
                            
                            final desc = prediction.description;
                            if (desc != null) {
                              _locationController.text = desc;
                              _locationController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _locationController.text.length),
                              );
                            }
                          },
                          seperatedBuilder: const Divider(),
                          containerHorizontalPadding: 10,
                          itemBuilder: (context, index, prediction) {
                            if (prediction == null) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      prediction.description ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _maxDistance,
                          items: [10, 25, 50, 100, 250].map((miles) {
                            return DropdownMenuItem(
                              value: miles.toDouble(),
                              child: Text('$miles mi'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _maxDistance = value;
                              });
                              _loadListings();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Salary range slider
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Salary Range: ${_currencyFormat.format(_salaryRange.start)} - ${_currencyFormat.format(_salaryRange.end)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RangeSlider(
                      values: _salaryRange,
                      min: 0,
                      max: 500000,
                      divisions: 100,
                      labels: RangeLabels(
                        _currencyFormat.format(_salaryRange.start),
                        _currencyFormat.format(_salaryRange.end),
                      ),
                      onChanged: (RangeValues values) {
                        setState(() {
                          _salaryRange = values;
                        });
                      },
                      onChangeEnd: (_) => _loadListings(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Employment type and sort by
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedEmploymentType,
                            isExpanded: true,
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
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<SortBy>(
                            value: _sortBy,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: SortBy.newest,
                                child: Text('Newest'),
                              ),
                              DropdownMenuItem(
                                value: SortBy.salary,
                                child: Text('Highest Salary'),
                              ),
                              DropdownMenuItem(
                                value: SortBy.distance,
                                child: Text('Nearest'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _sortBy = value;
                                });
                                _loadListings();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Showing ${_listings.length} results',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _locationController.clear();
                      _selectedEmploymentType = 'All';
                      _sortBy = SortBy.newest;
                      _salaryRange = const RangeValues(0, 500000);
                      _maxDistance = 50;
                    });
                    _loadListings();
                  },
                  child: const Text('Clear Filters'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final business = listing['profiles'] as Map<String, dynamic>;
    final minSalary = listing['min_salary'] as num?;
    final maxSalary = listing['max_salary'] as num?;
    final isRemote = listing['is_remote'] ?? false;
    final distance = listing['distance'] as double?;
    
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
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showListingDetails(listing),
        borderRadius: BorderRadius.circular(12),
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
              Row(
                children: [
                  Icon(Icons.business_center, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    business['industry'] ?? 'Various Industries',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Text(
                    salaryText,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (distance != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.directions_car, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${distance.toStringAsFixed(1)} miles away',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
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
                    isRemote ? 'Remote' : listing['location'],
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
                        // TODO: Implement apply functionality
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Application feature coming soon!'),
                          ),
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
        title: const Text('Job Listings'),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
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
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _listings.length,
                        itemBuilder: (context, index) {
                          return _buildListingCard(_listings[index]);
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
    _locationController.dispose();
    super.dispose();
  }
} 