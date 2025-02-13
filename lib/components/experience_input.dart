import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/supabase_config.dart';

class ExperienceInput extends StatefulWidget {
  final bool enabled;

  const ExperienceInput({
    super.key,
    this.enabled = true,
  });

  @override
  State<ExperienceInput> createState() => _ExperienceInputState();
}

class _ExperienceInputState extends State<ExperienceInput> {
  List<Map<String, dynamic>> _experiences = [];
  bool _isLoading = true;
  bool _isAddingExperience = false;

  // Controllers for the add/edit form
  final _companyController = TextEditingController();
  final _roleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isCurrent = false;
  Map<String, dynamic>? _editingExperience;

  @override
  void initState() {
    super.initState();
    _loadExperiences();
  }

  Future<void> _loadExperiences() async {
    try {
      final response = await supabase
          .from('profile_experience')
          .select()
          .eq('profile_id', supabase.auth.currentUser!.id)
          .order('start_date', ascending: false);
      
      setState(() {
        _experiences = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading experiences: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load work experience'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveExperience() async {
    if (_companyController.text.isEmpty || 
        _roleController.text.isEmpty || 
        _startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final experienceData = {
        'profile_id': supabase.auth.currentUser!.id,
        'company': _companyController.text,
        'role': _roleController.text,
        'description': _descriptionController.text,
        'start_date': _startDate!.toIso8601String(),
        'end_date': _isCurrent ? null : _endDate?.toIso8601String(),
        'is_current': _isCurrent,
      };

      if (_editingExperience != null) {
        // Update existing experience
        await supabase
            .from('profile_experience')
            .update(experienceData)
            .eq('id', _editingExperience!['id']);
      } else {
        // Insert new experience
        await supabase
            .from('profile_experience')
            .insert(experienceData);
      }

      // Reset form and reload experiences
      _resetForm();
      await _loadExperiences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Work experience saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving experience: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save work experience'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteExperience(Map<String, dynamic> experience) async {
    try {
      await supabase
          .from('profile_experience')
          .delete()
          .eq('id', experience['id']);
      
      await _loadExperiences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Work experience deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error deleting experience: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete work experience'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editExperience(Map<String, dynamic> experience) {
    setState(() {
      _editingExperience = experience;
      _companyController.text = experience['company'];
      _roleController.text = experience['role'];
      _descriptionController.text = experience['description'] ?? '';
      _startDate = DateTime.parse(experience['start_date']);
      _endDate = experience['end_date'] != null 
          ? DateTime.parse(experience['end_date'])
          : null;
      _isCurrent = experience['is_current'] ?? false;
      _isAddingExperience = true;
    });
  }

  void _resetForm() {
    setState(() {
      _editingExperience = null;
      _companyController.clear();
      _roleController.clear();
      _descriptionController.clear();
      _startDate = null;
      _endDate = null;
      _isCurrent = false;
      _isAddingExperience = false;
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
          ? _startDate ?? DateTime.now()
          : _endDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Widget _buildExperienceCard(Map<String, dynamic> experience) {
    final startDate = DateFormat.yMMMM().format(DateTime.parse(experience['start_date']));
    final endDate = experience['is_current'] 
        ? 'Present'
        : experience['end_date'] != null 
            ? DateFormat.yMMMM().format(DateTime.parse(experience['end_date']))
            : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        experience['role'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        experience['company'],
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.enabled) ...[
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editExperience(experience),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteExperience(experience),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$startDate - $endDate',
              style: const TextStyle(color: Colors.grey),
            ),
            if (experience['description'] != null && experience['description'].isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(experience['description']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _companyController,
              decoration: const InputDecoration(
                labelText: 'Company *',
                hintText: 'Enter company name',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _roleController,
              decoration: const InputDecoration(
                labelText: 'Role *',
                hintText: 'Enter your job title',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _selectDate(context, true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_startDate != null 
                        ? 'Start: ${DateFormat.yMMMM().format(_startDate!)}'
                        : 'Select Start Date *'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _isCurrent ? null : () => _selectDate(context, false),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_isCurrent 
                        ? 'Present'
                        : _endDate != null 
                            ? 'End: ${DateFormat.yMMMM().format(_endDate!)}'
                            : 'Select End Date'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _isCurrent,
                  onChanged: (value) {
                    setState(() {
                      _isCurrent = value ?? false;
                      if (_isCurrent) {
                        _endDate = null;
                      }
                    });
                  },
                ),
                const Text('I currently work here'),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe your responsibilities and achievements',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _resetForm,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _saveExperience,
                  child: Text(_editingExperience != null ? 'Update' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Work Experience',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.enabled && !_isAddingExperience)
              TextButton.icon(
                onPressed: () {
                  setState(() => _isAddingExperience = true);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Experience'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isAddingExperience)
          _buildExperienceForm(),
        if (_experiences.isEmpty && !_isAddingExperience)
          const Center(
            child: Text(
              'No work experience added yet',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ...List.generate(_experiences.length, (index) =>
            _buildExperienceCard(_experiences[index])
          ),
      ],
    );
  }

  @override
  void dispose() {
    _companyController.dispose();
    _roleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
} 