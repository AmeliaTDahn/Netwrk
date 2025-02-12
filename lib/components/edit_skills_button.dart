import 'package:flutter/material.dart';
import 'skills_input.dart';
import '../core/supabase_config.dart';

class EditSkillsButton extends StatefulWidget {
  final String userId;
  final VoidCallback onSkillsUpdated;

  const EditSkillsButton({
    super.key,
    required this.userId,
    required this.onSkillsUpdated,
  });

  @override
  State<EditSkillsButton> createState() => _EditSkillsButtonState();
}

class _EditSkillsButtonState extends State<EditSkillsButton> {
  List<String> _selectedSkills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSkills();
  }

  Future<void> _loadCurrentSkills() async {
    try {
      final response = await supabase
          .from('profile_skills')
          .select('skills(name)')
          .eq('profile_id', widget.userId);

      final skills = List<Map<String, dynamic>>.from(response)
          .map((skill) => skill['skills']['name'] as String)
          .toList();

      setState(() {
        _selectedSkills = skills;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading skills: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateSkills(List<String> newSkills) async {
    try {
      // Get skill IDs for the selected skills
      final skillsResponse = await supabase
          .from('skills')
          .select()
          .in_('name', newSkills);
      
      final skills = List<Map<String, dynamic>>.from(skillsResponse);
      
      // Delete existing skills
      await supabase
          .from('profile_skills')
          .delete()
          .eq('profile_id', widget.userId);
      
      // Add new skills
      final skillsToAdd = skills.map((skill) => {
        'profile_id': widget.userId,
        'skill_id': skill['id'],
      }).toList();

      if (skillsToAdd.isNotEmpty) {
        await supabase.from('profile_skills').upsert(skillsToAdd);
      }

      widget.onSkillsUpdated();
    } catch (e) {
      print('Error updating skills: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.edit),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Skills',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    SkillsInput(
                      selectedSkills: _selectedSkills,
                      onChanged: (skills) {
                        setState(() => _selectedSkills = skills);
                      },
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await _updateSkills(_selectedSkills);
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save Skills'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
} 