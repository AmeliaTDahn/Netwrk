import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../services/skills_service.dart';

class SkillsInput extends StatefulWidget {
  final List<String> selectedSkills;
  final Function(List<String>) onChanged;
  final bool enabled;

  const SkillsInput({
    super.key,
    required this.selectedSkills,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<SkillsInput> createState() => _SkillsInputState();
}

class _SkillsInputState extends State<SkillsInput> {
  List<Map<String, dynamic>> _availableSkills = [];
  List<String> _suggestedSkills = [];
  bool _isLoading = true;
  final TextEditingController _customSkillController = TextEditingController();
  bool _isAddingCustomSkill = false;

  @override
  void initState() {
    super.initState();
    _loadSkills();
    _loadSuggestions();
  }

  Future<void> _loadSkills() async {
    try {
      final response = await supabase
          .from('skills')
          .select()
          .order('name');
      
      setState(() {
        _availableSkills = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading skills: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final suggestions = await SkillsService.getSuggestedSkills(
        supabase.auth.currentUser!.id
      );
      setState(() {
        _suggestedSkills = suggestions;
      });
    } catch (e) {
      print('Error loading suggestions: $e');
    }
  }

  Future<void> _addCustomSkill(String skillName) async {
    try {
      // First try to insert the new skill into the skills table
      final response = await supabase
          .from('skills')
          .insert({
            'name': skillName,
          })
          .select()
          .single();
      
      // Add the new skill to available skills
      setState(() {
        _availableSkills.add(response);
        _availableSkills.sort((a, b) => a['name'].compareTo(b['name']));
        
        // Select the new skill
        final newSkills = List<String>.from(widget.selectedSkills)..add(skillName);
        widget.onChanged(newSkills);
        
        // Reset the custom skill input
        _customSkillController.clear();
        _isAddingCustomSkill = false;
      });
    } catch (e) {
      // If the skill already exists, just select it
      if (e.toString().contains('duplicate key')) {
        final newSkills = List<String>.from(widget.selectedSkills)..add(skillName);
        widget.onChanged(newSkills);
        _customSkillController.clear();
        _isAddingCustomSkill = false;
      } else {
        print('Error adding custom skill: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSuggestions(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableSkills.map((skill) {
            final isSelected = widget.selectedSkills.contains(skill['name']);
            return FilterChip(
              label: Text(
                skill['name'],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
              selected: isSelected,
              onSelected: widget.enabled ? (selected) {
                final newSkills = List<String>.from(widget.selectedSkills);
                if (selected) {
                  newSkills.add(skill['name']);
                } else {
                  newSkills.remove(skill['name']);
                }
                widget.onChanged(newSkills);
              } : null,
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF2196F3),
              checkmarkColor: Colors.white,
              showCheckmark: true,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
                side: BorderSide(
                  color: isSelected 
                      ? Colors.transparent
                      : Colors.grey.shade300,
                  width: 1,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (_isAddingCustomSkill)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customSkillController,
                  decoration: const InputDecoration(
                    hintText: 'Enter a new skill',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _addCustomSkill(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {
                  if (_customSkillController.text.isNotEmpty) {
                    _addCustomSkill(_customSkillController.text);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _customSkillController.clear();
                    _isAddingCustomSkill = false;
                  });
                },
              ),
            ],
          )
        else
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _isAddingCustomSkill = true);
            },
            icon: const Icon(Icons.add, color: Color(0xFF2196F3)),
            label: const Text(
              'Add Custom Skill',
              style: TextStyle(
                color: Color(0xFF2196F3),
                fontSize: 16,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[100],
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestions() {
    if (_suggestedSkills.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggested Skills',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestedSkills.map((skill) {
            final isSelected = widget.selectedSkills.contains(skill);
            return FilterChip(
              label: Text(
                skill,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
              selected: isSelected,
              onSelected: widget.enabled ? (selected) {
                final newSkills = List<String>.from(widget.selectedSkills);
                if (selected) {
                  newSkills.add(skill);
                } else {
                  newSkills.remove(skill);
                }
                widget.onChanged(newSkills);
              } : null,
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF2196F3),
              avatar: const Icon(Icons.star, size: 16),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Colors.grey.shade300,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  void dispose() {
    _customSkillController.dispose();
    super.dispose();
  }
} 