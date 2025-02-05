import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../models/video_model.dart';

final employeeVideosProvider = FutureProvider<List<Video>>((ref) async {
  final response = await SupabaseConfig.client
      .from('videos')
      .select()
      .eq('type', 'employee')
      .order('created_at', ascending: false);
      
  return (response as List).map((video) => Video.fromJson(video)).toList();
});

final businessVideosProvider = FutureProvider<List<Video>>((ref) async {
  final response = await SupabaseConfig.client
      .from('videos')
      .select()
      .eq('type', 'business')
      .order('created_at', ascending: false);
      
  return (response as List).map((video) => Video.fromJson(video)).toList();
}); 