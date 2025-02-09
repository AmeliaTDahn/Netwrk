import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';

const Color primaryBlue = Color(0xFF2196F3);    // Light blue

class SaveButton extends ConsumerStatefulWidget {
  final String videoId;
  final String? applicationId;  // Optional application ID for folder view
  final String? currentStatus;  // Optional current status for folder view

  const SaveButton({
    super.key,
    required this.videoId,
    this.applicationId,
    this.currentStatus,
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

      if (widget.applicationId != null) {
        // For folder view, check application status
        final response = await supabase
            .from('job_applications')
            .select('status')
            .eq('id', widget.applicationId)
            .single();
        
        if (mounted) {
          setState(() {
            _isSaved = response['status'] == 'saved' || 
                      response['status'] == 'interviewing_saved';
          });
        }
      } else {
        // For regular video saves
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

      if (widget.applicationId != null) {
        // For folder view, update application status
        final currentStatus = widget.currentStatus ?? 'pending';
        String newStatus;
        
        if (currentStatus == 'interviewing') {
          newStatus = _isSaved ? 'interviewing' : 'interviewing_saved';
        } else {
          newStatus = _isSaved ? 'pending' : 'saved';
        }

        await supabase
            .from('job_applications')
            .update({'status': newStatus})
            .eq('id', widget.applicationId);
      } else {
        // For regular video saves
        if (_isSaved) {
          await supabase
              .from('saves')
              .delete()
              .eq('user_id', userId)
              .eq('video_id', widget.videoId);
        } else {
          await supabase
              .from('saves')
              .insert({
                'user_id': userId,
                'video_id': widget.videoId,
              });
        }
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
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
              ),
            )
          : Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_outline,
              color: _isSaved ? primaryBlue : Colors.black,
              size: 28,
            ),
      onPressed: _toggleSave,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(8),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
  }
} 