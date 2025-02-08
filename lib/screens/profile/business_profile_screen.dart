import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_config.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  final String? userId;
  
  const BusinessProfileScreen({
    super.key,
    this.userId,
  });

  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isEditing = false;
  String? _photoUrl;
  File? _imageFile;
  
  // Business profile fields
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _industryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBusinessProfile();
  }

  Future<void> _loadBusinessProfile() async {
    try {
      final userId = widget.userId ?? supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        _businessNameController.text = response['business_name'] ?? '';
        _emailController.text = response['email'] ?? '';
        _phoneController.text = response['phone'] ?? '';
        _websiteController.text = response['website'] ?? '';
        _descriptionController.text = response['description'] ?? '';
        _locationController.text = response['location'] ?? '';
        _industryController.text = response['industry'] ?? '';
        _photoUrl = response['photo_url'];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userId = widget.userId ?? supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Upload new image if selected
      String? newPhotoUrl = _photoUrl;
      if (_imageFile != null) {
        final fileExtension = _imageFile!.path.split('.').last;
        final fileName = '${DateTime.now().toIso8601String()}.$fileExtension';
        
        await supabase.storage.from('avatars').upload(
          fileName,
          _imageFile!,
        );
        
        newPhotoUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      // Update profile
      await supabase.from('profiles').update({
        'business_name': _businessNameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        'website': _websiteController.text,
        'description': _descriptionController.text,
        'location': _locationController.text,
        'industry': _industryController.text,
        if (newPhotoUrl != null) 'photo_url': newPhotoUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Widget _buildProfileImage() {
    final hasImage = _imageFile != null || _photoUrl != null;
    final imageWidget = hasImage
        ? CircleAvatar(
            radius: 50,
            backgroundImage: _imageFile != null
                ? FileImage(_imageFile!)
                : NetworkImage(_photoUrl!) as ImageProvider,
          )
        : const CircleAvatar(
            radius: 50,
            child: Icon(Icons.business, size: 50),
          );

    return Stack(
      children: [
        imageWidget,
        if (!_isEditing)
          const SizedBox()
        else
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              radius: 18,
              child: IconButton(
                icon: const Icon(Icons.edit, size: 18),
                color: Colors.white,
                onPressed: _pickImage,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentUser = widget.userId == null || 
                         widget.userId == supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Profile'),
        actions: [
          if (isCurrentUser)
            IconButton(
              icon: Icon(_isEditing ? Icons.save : Icons.edit),
              onPressed: () {
                if (_isEditing) {
                  _updateProfile();
                } else {
                  setState(() => _isEditing = true);
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildProfileImage(),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _businessNameController,
                      decoration: const InputDecoration(
                        labelText: 'Business Name',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _isEditing,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your business name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Business Email',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _isEditing,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your business email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Business Phone',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _isEditing,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _websiteController,
                      decoration: const InputDecoration(
                        labelText: 'Website',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _isEditing,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _isEditing,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _industryController,
                      decoration: const InputDecoration(
                        labelText: 'Industry',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _isEditing,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Business Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      enabled: _isEditing,
                    ),
                    const SizedBox(height: 24),
                    if (isCurrentUser)
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
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _industryController.dispose();
    super.dispose();
  }
} 