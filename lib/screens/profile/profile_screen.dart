import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_config.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

// Add this enum at the top of the file
enum UserRole {
  business,
  employee,
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isLoading = false;
  bool _isEditing = false;  // Add this to track edit mode
  final _formKey = GlobalKey<FormState>();
  
  // Controllers for editable fields
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _resumeUrlController = TextEditingController();
  final List<String> _skills = [];
  final _newSkillController = TextEditingController();

  // Add these variables
  String? _photoUrl;
  final _imagePicker = ImagePicker();

  // Add this variable with the other state variables
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
        _photoUrl = data['photo_url'];
        _displayNameController.text = data['display_name'] ?? '';
        _bioController.text = data['bio'] ?? '';
        _emailController.text = data['contact_email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _resumeUrlController.text = data['resume_url'] ?? '';
        _userRole = data['role'] == 'business' ? UserRole.business : UserRole.employee;
        
        // Handle skills
        final skillsString = data['skills'] as String?;
        _skills.clear();
        if (skillsString != null && skillsString.isNotEmpty) {
          _skills.addAll(skillsString.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
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

      await supabase.from('profiles').update({
        'display_name': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        'contact_email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'resume_url': _resumeUrlController.text.trim(),
        'skills': _skills.join(','),
        'role': _userRole.name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addSkill(String skill) {
    final trimmedSkill = skill.trim();
    if (trimmedSkill.isNotEmpty && !_skills.contains(trimmedSkill)) {
      setState(() {
        _skills.add(trimmedSkill);
      });
      _newSkillController.clear();
    }
  }

  Widget _buildSkillsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Professional Skills',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._skills.map((skill) => Chip(
              label: Text(skill),
              deleteIcon: const Icon(Icons.close, size: 18),
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              onDeleted: () {
                setState(() {
                  _skills.remove(skill);
                });
              },
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newSkillController,
                decoration: const InputDecoration(
                  labelText: 'Add a skill',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.add),
                  helperText: 'Press Enter or tap + to add a skill',
                ),
                onSubmitted: _addSkill,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () => _addSkill(_newSkillController.text),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      if (mounted) {
        context.go('/signin');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  // Add method to handle photo upload
  Future<void> _uploadPhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 90,
      );

      if (image == null) return;

      setState(() => _isLoading = true);

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Upload to Supabase Storage
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}${path.extension(image.path)}';
      final file = File(image.path);
      
      final response = await supabase
          .storage
          .from('profile_photos')
          .upload(fileName, file);

      // Get the public URL
      final photoUrl = supabase
          .storage
          .from('profile_photos')
          .getPublicUrl(fileName);

      // Update profile with new photo URL
      await supabase.from('profiles').upsert({
        'id': userId,
        'photo_url': photoUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      setState(() => _photoUrl = photoUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading photo: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Add method to toggle edit mode
  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        // Reset form if canceling edit
        _loadProfile();
      }
    });
  }

  // Add this widget to build the role selector
  Widget _buildRoleSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'I am a:',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRoleOption(
                  theme,
                  UserRole.business,
                  'Business',
                  Icons.business,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRoleOption(
                  theme,
                  UserRole.employee,
                  'Employee',
                  Icons.person,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleOption(
    ThemeData theme,
    UserRole role,
    String label,
    IconData icon,
  ) {
    final isSelected = _userRole == role;
    
    return InkWell(
      onTap: _isEditing ? () {
        setState(() => _userRole = role);
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? theme.colorScheme.primary : Colors.grey[600],
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? theme.colorScheme.primary : Colors.grey[800],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add this method
  Future<void> _showSignOutDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _signOut();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
        actions: [
          // Edit/Cancel button in AppBar
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: _toggleEditMode,
          ),
          // Add this IconButton
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _showSignOutDialog,
            ),
        ],
      ),
      backgroundColor: theme.colorScheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Profile Header Section
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                                child: _photoUrl == null ? const Icon(Icons.person, size: 50) : null,
                              ),
                              if (_isEditing)
                                Positioned(
                                  right: -10,
                                  bottom: -10,
                                  child: IconButton(
                                    icon: const Icon(Icons.camera_alt),
                                    onPressed: _uploadPhoto,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _displayNameController.text,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Profile Content
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _isEditing 
                          ? _buildEditForm(theme)
                          : _buildProfileView(theme),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // Add method to build the view-only profile
  Widget _buildProfileView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('About', theme),
        _buildInfoCard(
          Text(
            _bioController.text.isEmpty 
                ? 'No professional summary added yet'
                : _bioController.text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        _buildSectionTitle('Contact Information', theme),
        _buildInfoCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_emailController.text.isNotEmpty)
              _buildContactRow(
                Icons.email_outlined,
                _emailController.text,
                onTap: () => _launchUrl('mailto:${_emailController.text}'),
              ),
            if (_phoneController.text.isNotEmpty)
              _buildContactRow(
                Icons.phone_outlined,
                _phoneController.text,
                onTap: () => _launchUrl('tel:${_phoneController.text}'),
              ),
            if (_resumeUrlController.text.isNotEmpty && _resumeUrlController.text.startsWith('http'))
              _buildContactRow(
                Icons.link,
                'View Resume',
                onTap: () => _launchUrl(_resumeUrlController.text),
              ),
          ],
        )),
        
        const SizedBox(height: 24),
        _buildSectionTitle('Skills', theme),
        _buildInfoCard(
          _skills.isEmpty
              ? const Text(
                  'No skills added yet',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _skills.map((skill) => Chip(
                    label: Text(
                      skill,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  )).toList(),
                ),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('Account Type', theme),
        _buildRoleSelector(theme),
      ],
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoCard(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
        ),
      ),
      child: child,
    );
  }

  Widget _buildContactRow(IconData icon, String text, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: onTap != null ? Theme.of(context).colorScheme.primary : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  color: onTap != null ? Theme.of(context).colorScheme.primary : null,
                  decoration: onTap != null ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add this method to handle URL launching
  Future<void> _launchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  // Rename the existing form build method
  Widget _buildEditForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title - Basic Info
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Basic Information',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          // Name Field
          TextFormField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) =>
                value?.isEmpty == true ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          
          // Bio Field
          TextFormField(
            controller: _bioController,
            decoration: const InputDecoration(
              labelText: 'Professional Summary',
              prefixIcon: Icon(Icons.description_outlined),
              helperText: 'Brief description of your professional background',
              alignLabelWithHint: true,
            ),
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
          
          // Section Title - Contact
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Contact Information',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          // Contact Fields
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Contact Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _resumeUrlController,
            decoration: const InputDecoration(
              labelText: 'Resume Link',
              prefixIcon: Icon(Icons.link),
              helperText: 'Link to your resume (Google Drive, Dropbox, etc.)',
            ),
            keyboardType: TextInputType.url,
          ),
          
          // Section Title - Skills
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Professional Skills',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          // Skills Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._skills.map((skill) => Chip(
                      label: Text(
                        skill,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      side: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                      ),
                      onDeleted: () {
                        setState(() {
                          _skills.remove(skill);
                        });
                      },
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newSkillController,
                        decoration: InputDecoration(
                          hintText: 'Add a skill',
                          prefixIcon: const Icon(Icons.add),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: _addSkill,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.add_circle,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () => _addSkill(_newSkillController.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : () {
                _updateProfile().then((_) {
                  if (mounted) _toggleEditMode();
                });
              },
              icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Account Type', theme),
          _buildRoleSelector(theme),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _resumeUrlController.dispose();
    _newSkillController.dispose();
    super.dispose();
  }
} 