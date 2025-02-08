import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';

class ListingsScreen extends StatefulWidget {
  const ListingsScreen({super.key});

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  List<Map<String, dynamic>> _listings = [];
  
  // Controllers for the add/edit listing form
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _salaryController = TextEditingController();
  final _requirementsController = TextEditingController();
  String _employmentType = 'Full-time'; // Default value

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('job_listings')
          .select()
          .eq('business_id', userId)
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

  Future<void> _addListing() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('job_listings').insert({
        'business_id': userId,
        'title': _titleController.text,
        'description': _descriptionController.text,
        'location': _locationController.text,
        'salary': _salaryController.text,
        'requirements': _requirementsController.text,
        'employment_type': _employmentType,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context); // Close the add listing dialog
        _loadListings(); // Refresh the listings
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job listing added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding listing: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleListingStatus(String listingId, bool currentStatus) async {
    try {
      await supabase
          .from('job_listings')
          .update({'is_active': !currentStatus})
          .eq('id', listingId);

      _loadListings(); // Refresh the listings
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating listing: $e')),
        );
      }
    }
  }

  Future<void> _deleteListing(String listingId) async {
    try {
      await supabase
          .from('job_listings')
          .delete()
          .eq('id', listingId);

      _loadListings(); // Refresh the listings
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job listing deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting listing: $e')),
        );
      }
    }
  }

  void _showAddListingDialog() {
    // Reset form controllers
    _titleController.clear();
    _descriptionController.clear();
    _locationController.clear();
    _salaryController.clear();
    _requirementsController.clear();
    _employmentType = 'Full-time';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a location';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _salaryController,
                  decoration: const InputDecoration(
                    labelText: 'Salary Range',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a salary range';
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
                  items: const [
                    DropdownMenuItem(value: 'Full-time', child: Text('Full-time')),
                    DropdownMenuItem(value: 'Part-time', child: Text('Part-time')),
                    DropdownMenuItem(value: 'Contract', child: Text('Contract')),
                    DropdownMenuItem(value: 'Internship', child: Text('Internship')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _employmentType = value);
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
            onPressed: _addListing,
            child: const Text('Add Listing'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Job Listings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadListings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _listings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.work_outline,
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
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showAddListingDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Job Listing'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _listings.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final listing = _listings[index];
                    final isActive = listing['is_active'] ?? false;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ExpansionTile(
                        title: Text(
                          listing['title'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(listing['employment_type']),
                        trailing: Row(
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
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildListingDetail(
                                  'Description',
                                  listing['description'],
                                ),
                                const SizedBox(height: 8),
                                _buildListingDetail(
                                  'Location',
                                  listing['location'],
                                ),
                                const SizedBox(height: 8),
                                _buildListingDetail(
                                  'Salary',
                                  listing['salary'],
                                ),
                                const SizedBox(height: 8),
                                _buildListingDetail(
                                  'Requirements',
                                  listing['requirements'],
                                ),
                                const SizedBox(height: 8),
                                _buildListingDetail(
                                  'Status',
                                  isActive ? 'Active' : 'Inactive',
                                  color: isActive ? Colors.green : Colors.red,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildListingDetail(String label, String? value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value ?? 'Not specified',
          style: TextStyle(
            fontSize: 14,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _salaryController.dispose();
    _requirementsController.dispose();
    super.dispose();
  }
} 