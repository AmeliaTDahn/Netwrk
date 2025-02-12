import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_config.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../saves/saves_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../components/banner_notification.dart';
import '../../components/edit_skills_button.dart';

// Add this enum at the top of the file
enum UserRole {
  business,
  employee,
}

// Add this at the top of the file
const Color primaryBlue = Color(0xFF2196F3);    // Light blue

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isLoading = false;
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  
  // Common fields
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();
  String? _photoUrl;
  String? _accountType;

  // Business-specific fields
  final _businessNameController = TextEditingController();
  final _industryController = TextEditingController();
  final _websiteController = TextEditingController();

  // Employee-specific fields
  final _educationController = TextEditingController();
  final _experienceYearsController = TextEditingController();

  UserRole _userRole = UserRole.employee;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        // Common fields
        _photoUrl = data['photo_url'];
        _nameController.text = data['name'] ?? '';
        _emailController.text = data['email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _locationController.text = data['location'] ?? '';
        _bioController.text = data['bio'] ?? '';
        _accountType = data['account_type'];
        
        if (_accountType == 'business') {
          // Business fields
          _businessNameController.text = data['business_name'] ?? '';
          _industryController.text = data['industry'] ?? '';
          _websiteController.text = data['website'] ?? '';
        } else {
          // Employee fields
          _educationController.text = data['education'] ?? '';
          _experienceYearsController.text = (data['experience_years'] ?? '').toString();
        }
      });
      
    } catch (e) {
      if (mounted) {
        BannerNotification.show(context, 'Error loading profile: $e');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Must be logged in to update profile');

      // Prepare common profile data
      final Map<String, dynamic> profileData = {
        'name': _nameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        'location': _locationController.text,
        'bio': _bioController.text,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add account type specific fields
      if (_accountType == 'business') {
        profileData.addAll({
          'business_name': _businessNameController.text,
          'industry': _industryController.text,
          'website': _websiteController.text,
        });
      } else {
        profileData.addAll({
          'education': _educationController.text,
          'experience_years': int.tryParse(_experienceYearsController.text) ?? 0,
        });
      }

      await supabase.from('profiles').update(profileData).eq('id', userId);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isLoading = false;
        });
        BannerNotification.show(context, 'Profile updated successfully');
      }
    } catch (e) {
      if (mounted) {
        BannerNotification.show(context, 'Error updating profile: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildProfileField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? 'Not specified' : value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    if (!_isEditing) {
      return _buildProfileField(label, controller.text);
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024, // Limit image size
      maxHeight: 1024,
      imageQuality: 85, // Compress image
    );
    
    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final userId = supabase.auth.currentUser?.id;
        if (userId == null) return;

        final fileExtension = image.path.split('.').last;
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        
        // Try to upload the file
        try {
          await supabase.storage.from('avatars').upload(
            fileName,
            File(image.path),
          );
        } catch (uploadError) {
          if (uploadError.toString().contains('Bucket not found')) {
            throw Exception(
              'Storage not configured. Please contact support to enable profile pictures.'
            );
          }
          throw Exception(
            'Failed to upload image. Please try again or contact support.'
          );
        }
        
        final photoUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

        await supabase.from('profiles').update({
          'photo_url': photoUrl,
        }).eq('id', userId);

        setState(() => _photoUrl = photoUrl);
        
        if (mounted) {
          BannerNotification.show(context, 'Profile picture updated successfully');
        }
      } catch (e) {
        if (mounted) {
          BannerNotification.show(context, e.toString().replaceAll('Exception:', '').trim());
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: () {
              if (_isEditing) {
                _updateProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                context.go('/signin');
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Picture
                    Center(
                      child: GestureDetector(
                        onTap: _isEditing ? _pickImage : null,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundImage: _photoUrl != null
                                  ? NetworkImage(_photoUrl!)
                                  : null,
                              child: _photoUrl == null
                                  ? const Icon(Icons.person, size: 50)
                                  : null,
                            ),
                            if (_isEditing)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Account Type Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        child: Text(
                          _accountType == 'business' ? 'Business Account' : 'Employee Account',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Common Fields
                    _buildTextField(
                      controller: _nameController,
                      label: 'Name',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      enabled: false,
                    ),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone',
                    ),
                    _buildTextField(
                      controller: _locationController,
                      label: 'Location',
                    ),
                    _buildTextField(
                      controller: _bioController,
                      label: 'Bio',
                      maxLines: 3,
                    ),

                    // Account Type Specific Fields
                    if (_accountType == 'business') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Business Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _businessNameController,
                        label: 'Business Name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your business name';
                          }
                          return null;
                        },
                      ),
                      _buildTextField(
                        controller: _industryController,
                        label: 'Industry',
                      ),
                      _buildTextField(
                        controller: _websiteController,
                        label: 'Website',
                      ),
                      if (!_isEditing)
                        ElevatedButton.icon(
                          onPressed: () {
                            context.push('/listings');
                          },
                          icon: const Icon(Icons.work),
                          label: const Text('Manage Job Listings'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                    ] else ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Professional Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _educationController,
                        label: 'Education',
                      ),
                      _buildTextField(
                        controller: _experienceYearsController,
                        label: 'Years of Experience',
                        keyboardType: TextInputType.number,
                      ),
                    ],

                    // Add skills section for employee accounts
                    if (_accountType == 'employee') ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Skills',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          EditSkillsButton(
                            userId: supabase.auth.currentUser!.id,
                            onSkillsUpdated: () {
                              setState(() {
                                // Trigger rebuild to refresh skills
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: Future(() async {
                          final response = await supabase
                              .from('profile_skills')
                              .select('skills(name)')
                              .eq('profile_id', supabase.auth.currentUser!.id);
                          return List<Map<String, dynamic>>.from(response);
                        }),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox();
                          }

                          final skills = snapshot.data!
                              .map((skill) => skill['skills']['name'] as String)
                              .toList();

                          if (skills.isEmpty) {
                            return Text(
                              'No skills added yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            );
                          }

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: skills.map((skill) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2196F3), // The blue color from the screenshot
                                  borderRadius: BorderRadius.circular(50), // Pill shape
                                ),
                                child: Text(
                                  skill,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    _businessNameController.dispose();
    _industryController.dispose();
    _websiteController.dispose();
    _educationController.dispose();
    _experienceYearsController.dispose();
    super.dispose();
  }
} 