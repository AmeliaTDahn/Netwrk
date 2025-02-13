import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/services/skills_service.dart';
import '../lib/core/env_config.dart';

void main() async {
  // Load environment variables
  await dotenv.load();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );
  
  print('Starting skills initialization...');
  
  try {
    // Generate embeddings for skills without them
    await SkillsService.generateEmbeddingsForSkillsWithoutEmbeddings();
    print('Successfully initialized skills with embeddings');
  } catch (e) {
    print('Error initializing skills: $e');
  }
  
  // Clean up
  Supabase.instance.dispose();
} 