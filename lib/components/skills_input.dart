import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../services/skills_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _isInitialLoading = true;
  bool _isSaving = false;
  Set<String> _pendingSkills = {};  // Track skills pending addition/removal
  final TextEditingController _customSkillController = TextEditingController();
  bool _isAddingCustomSkill = false;
  String? _searchQuery;
  RealtimeChannel? _skillsSubscription;
  RealtimeChannel? _skillsTableSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupRealtimeSubscriptions();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadSkills(),
      _loadSuggestions(),
      _loadUserSkills(),
    ]);
  }

  void _setupRealtimeSubscriptions() {
    final userId = supabase.auth.currentUser!.id;
    
    // Subscribe to profile_skills changes
    _skillsSubscription = supabase.channel('profile_skills_changes');
    _skillsSubscription!
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'profile_skills',
            filter: 'profile_id=eq.$userId',
          ),
          (payload, [ref]) {
            print('Received profile_skills update: $payload');
            _loadUserSkills();
            _loadSuggestions();
          },
        )
        .subscribe();

    // Subscribe to skills table changes
    _skillsTableSubscription = supabase.channel('skills_changes');
    _skillsTableSubscription!
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'skills',
          ),
          (payload, [ref]) {
            print('Received skills update: $payload');
            _loadSkills();
          },
        )
        .subscribe();
  }

  Future<void> _loadSkills() async {
    try {
      final response = await supabase
          .from('skills')
          .select()
          .order('name');
      
      setState(() {
        _availableSkills = List<Map<String, dynamic>>.from(response);
        _isInitialLoading = false;
      });
    } catch (e) {
      print('Error loading skills: $e');
      setState(() => _isInitialLoading = false);
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

  Future<void> _loadUserSkills() async {
    try {
      final response = await supabase
          .from('profile_skills')
          .select('skill_id, skills!inner(name)')
          .eq('profile_id', supabase.auth.currentUser!.id);
      final selectedSkills = List<String>.from(response.map((s) => s['skills']['name']));
      widget.onChanged(selectedSkills);
    } catch (e) {
      print('Error loading user skills: $e');
    }
  }

  Future<void> _addCustomSkill(String skillName) async {
    setState(() => _isAddingCustomSkill = true);
    
    try {
      // Validate skill name
      if (skillName.trim().isEmpty) {
        throw Exception('Skill name cannot be empty');
      }
      
      // Use SkillsService to add the skill with embedding
      await SkillsService.addNewSkill(skillName.trim());
      
      // Reload skills to get the updated list including the new skill
      await _loadSkills();
      
      // Select the new skill
      final newSkills = List<String>.from(widget.selectedSkills)..add(skillName);
      widget.onChanged(newSkills);
      
      // Reset the custom skill input
      _customSkillController.clear();
      setState(() => _isAddingCustomSkill = false);
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Skill added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error adding custom skill: $e');
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('duplicate key') 
                ? 'This skill already exists' 
                : 'Failed to add skill. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      // If the skill already exists, just select it
      if (e.toString().contains('duplicate key')) {
        final newSkills = List<String>.from(widget.selectedSkills)..add(skillName);
        widget.onChanged(newSkills);
        _customSkillController.clear();
        setState(() => _isAddingCustomSkill = false);
      }
    }
  }

  Future<void> _toggleSkills(List<String> skillsToToggle, bool shouldAdd) async {
    if (!widget.enabled) return;

    // Update UI immediately (optimistically)
    final newSkills = List<String>.from(widget.selectedSkills);
    if (shouldAdd) {
      newSkills.addAll(skillsToToggle);
    } else {
      newSkills.removeWhere((skill) => skillsToToggle.contains(skill));
    }
    widget.onChanged(newSkills);

    // Track pending in background
    setState(() {
      _pendingSkills.addAll(skillsToToggle);
    });

    try {
      // Get all skill IDs in one query
      final skillsResponse = await supabase
          .from('skills')
          .select('id, name')
          .in_('name', skillsToToggle);
      
      final skillIdMap = {
        for (var skill in skillsResponse) skill['name'] as String: skill['id']
      };

      if (shouldAdd) {
        // Batch insert skills
        final skillsToInsert = skillsToToggle.map((skillName) => ({
          'profile_id': supabase.auth.currentUser!.id,
          'skill_id': skillIdMap[skillName],
        })).where((skill) => skill['skill_id'] != null).toList();

        await supabase
            .from('profile_skills')
            .upsert(skillsToInsert);
      } else {
        // Batch delete skills
        final skillIds = skillsToToggle
            .map((name) => skillIdMap[name])
            .where((id) => id != null)
            .toList();

        await supabase
            .from('profile_skills')
            .delete()
            .eq('profile_id', supabase.auth.currentUser!.id)
            .in_('skill_id', skillIds);
      }
    } catch (e) {
      print('Error toggling skills: $e');
      
      // Revert UI state on error
      if (shouldAdd) {
        newSkills.removeWhere((skill) => skillsToToggle.contains(skill));
      } else {
        newSkills.addAll(skillsToToggle);
      }
      widget.onChanged(newSkills);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shouldAdd ? 'Failed to add skills' : 'Failed to remove skills'
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingSkills.removeAll(skillsToToggle);
        });
      }
    }
  }

  Widget _buildSkillChip(String skillName, {bool isSuggested = false}) {
    final isSelected = widget.selectedSkills.contains(skillName);
    final isPending = _pendingSkills.contains(skillName);
    
    return Material(
      child: InkWell(
        onTap: widget.enabled ? () {
          final skillsToToggle = [skillName];
          _toggleSkills(skillsToToggle, !isSelected);
        } : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSuggested) ...[
                Icon(
                  Icons.star,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.amber,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                skillName,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                if (isPending)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.check,
                    size: 14,
                    color: Colors.white,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredSkills() {
    if (_searchQuery == null || _searchQuery!.isEmpty) {
      return _availableSkills;
    }
    return _availableSkills.where((skill) =>
      skill['name'].toString().toLowerCase().contains(_searchQuery!.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Remove duplicates between suggested and selected skills
    final suggestedSkillsFiltered = _suggestedSkills
        .where((skill) => !widget.selectedSkills.contains(skill))
        .toSet()
        .toList();

    // Get filtered skills excluding selected and suggested ones
    final filteredSkills = _getFilteredSkills()
        .where((skill) => 
          !widget.selectedSkills.contains(skill['name']) &&
          !suggestedSkillsFiltered.contains(skill['name']))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selected Skills Section
        if (widget.selectedSkills.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Your Skills',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: widget.selectedSkills.map((skill) =>
              _buildSkillChip(skill)
            ).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Search field - more compact
        if (!_isAddingCustomSkill)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search or add skills...',
                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
        const SizedBox(height: 16),

        // Suggested Skills - if any not already selected
        if (suggestedSkillsFiltered.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Suggested Skills',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: suggestedSkillsFiltered.map((skill) =>
              _buildSkillChip(skill, isSuggested: true)
            ).toList(),
          ),
          const SizedBox(height: 16),
        ],
        
        // Available Skills - excluding selected and suggested
        if (filteredSkills.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'More Skills',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: filteredSkills.map((skill) =>
              _buildSkillChip(skill['name'])
            ).toList(),
          ),
        ],

        // Custom Skill Input
        if (_isAddingCustomSkill)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customSkillController,
                    decoration: InputDecoration(
                      hintText: 'Enter a new skill',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
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
                  icon: const Icon(Icons.check, size: 20),
                  onPressed: () {
                    if (_customSkillController.text.isNotEmpty) {
                      _addCustomSkill(_customSkillController.text);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    setState(() {
                      _customSkillController.clear();
                      _isAddingCustomSkill = false;
                    });
                  },
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: TextButton.icon(
              onPressed: () {
                setState(() => _isAddingCustomSkill = true);
              },
              icon: const Icon(Icons.add, size: 18, color: Color(0xFF2196F3)),
              label: const Text(
                'Add Custom Skill',
                style: TextStyle(
                  color: Color(0xFF2196F3),
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _customSkillController.dispose();
    _skillsSubscription?.unsubscribe();
    _skillsTableSubscription?.unsubscribe();
    super.dispose();
  }
} 