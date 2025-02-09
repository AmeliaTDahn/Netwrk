import 'package:flutter/material.dart';

class SkillsInput extends StatefulWidget {
  final List<String> skills;
  final Function(List<String>) onChanged;

  const SkillsInput({
    super.key,
    required this.skills,
    required this.onChanged,
  });

  @override
  State<SkillsInput> createState() => _SkillsInputState();
}

class _SkillsInputState extends State<SkillsInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...widget.skills.map((skill) => Chip(
              label: Text(skill),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () {
                final newSkills = List<String>.from(widget.skills)..remove(skill);
                widget.onChanged(newSkills);
              },
            )),
            Container(
              width: 200,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  hintText: 'Add a skill...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    final newSkills = List<String>.from(widget.skills)..add(value.trim());
                    widget.onChanged(newSkills);
                    _controller.clear();
                    _focusNode.requestFocus();
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
} 