import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';

class SaveButton extends ConsumerStatefulWidget {
  final String videoId;

  const SaveButton({
    super.key,
    required this.videoId,
  });

  @override
  ConsumerState<SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends ConsumerState<SaveButton> {
  bool _isSaved = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
  }

  Future<void> _checkIfSaved() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('saves')
          .select()
          .eq('user_id', userId)
          .eq('video_id', widget.videoId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isSaved = response != null;
        });
      }
    } catch (e) {
      print('Error checking save status: $e');
    }
  }

  Future<void> _toggleSave() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (_isSaved) {
        // Remove save
        await supabase
            .from('saves')
            .delete()
            .eq('user_id', userId)
            .eq('video_id', widget.videoId);
      } else {
        // Add save
        await supabase
            .from('saves')
            .insert({
              'user_id': userId,
              'video_id': widget.videoId,
            });
      }

      if (mounted) {
        setState(() {
          _isSaved = !_isSaved;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error toggling save: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: Colors.white,
            ),
      onPressed: _toggleSave,
    );
  }
} 