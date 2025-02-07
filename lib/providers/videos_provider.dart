import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_model.dart';
import '../core/supabase_config.dart';

final videosProvider = FutureProvider<List<VideoModel>>((ref) async {
  final response = await supabase
      .from('videos')
      .select('''
        id,
        video_url,
        title,
        user_id,
        created_at,
        profiles:user_id (
          id,
          display_name,
          photo_url
        )
      ''')
      .order('created_at', ascending: false)
      .limit(10);  // Load fewer videos initially

  return response.map((video) => VideoModel.fromJson(video)).toList();
}); 