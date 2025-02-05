import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Load from .env file
final String supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

// Throw error if keys are missing or invalid
void validateConfig() {
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw Exception('Missing Supabase configuration. Please check your .env file.');
  }
  
  // Validate URL format
  if (!supabaseUrl.startsWith('https://')) {
    throw Exception('Invalid Supabase URL format. URL must start with https://');
  }
  
  // Validate URL structure
  try {
    Uri.parse(supabaseUrl);
  } catch (e) {
    throw Exception('Invalid Supabase URL format: $e');
  }
}

// Easy access to Supabase client
final supabase = Supabase.instance.client;

class SupabaseConfig {
  static SupabaseClient get client => Supabase.instance.client;
  static const String scheme = 'io.supabase.netwrk';
} 