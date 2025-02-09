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
  Map<String, dynamic> _profile = {};
  
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
        _profile = Map<String, dynamic>.from(response);
        _businessNameController.text = _profile['business_name'] ?? '';
        _emailController.text = _profile['email'] ?? '';
        _phoneController.text = _profile['phone'] ?? '';
        _websiteController.text = _profile['website'] ?? '';
        _descriptionController.text = _profile['description'] ?? '';
        _locationController.text = _profile['location'] ?? '';
        _industryController.text = _profile['industry'] ?? '';
        _photoUrl = _profile['photo_url'];
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

      // Update profile with all fields including interview message template
      await supabase.from('profiles').update({
        'business_name': _businessNameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        'website': _websiteController.text,
        'description': _descriptionController.text,
        'location': _locationController.text,
        'industry': _industryController.text,
        'interview_message_template': _profile['interview_message_template'],
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

  Widget _buildProfileField(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? 'Not specified' : value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black,
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
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey[200]!,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).primaryColor,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.all(16),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildProfileImage(),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey[200]!,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Basic Information',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
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
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _emailController,
                            label: 'Business Email',
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
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _phoneController,
                            label: 'Business Phone',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey[200]!,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Additional Information',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildTextField(
                            controller: _websiteController,
                            label: 'Website',
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _locationController,
                            label: 'Location',
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _industryController,
                            label: 'Industry',
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _descriptionController,
                            label: 'Business Description',
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (isCurrentUser)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            context.push('/listings');
                          },
                          icon: const Icon(Icons.work),
                          label: const Text('Manage Job Listings'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    // Interview Message Template Section
                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      _buildSection(
                        title: 'Interview Message Template',
                        icon: Icons.message_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This message will be automatically sent to candidates when you schedule an interview.',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: _profile['interview_message_template'] ?? 'Hi! Thanks for applying. We would like to schedule an interview with you. Please let me know your availability for this week.',
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Enter your interview message template',
                              ),
                              maxLines: 3,
                              onChanged: (value) {
                                _profile['interview_message_template'] = value;
                              },
                            ),
                          ],
                        ),
                      ),
                    ] else if (_profile['interview_message_template'] != null) ...[
                      const SizedBox(height: 24),
                      _buildSection(
                        title: 'Interview Message Template',
                        icon: Icons.message_outlined,
                        child: Text(
                          _profile['interview_message_template'],
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.5,
                          ),
                        ),
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