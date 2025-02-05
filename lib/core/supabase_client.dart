import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Load from .env file
final String supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

// Get Supabase client instance
final supabase = Supabase.instance.client;

// Initialize Supabase
Future<void> initializeSupabase() async {
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    authFlowType: AuthFlowType.pkce,
    debug: true,
  );
}

// Validate configuration
void validateConfig() {
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw Exception('Missing Supabase configuration. Please check your .env file.');
  }
  
  if (!supabaseUrl.startsWith('https://')) {
    throw Exception('Invalid Supabase URL format. URL must start with https://');
  }
  
  try {
    Uri.parse(supabaseUrl);
  } catch (e) {
    throw Exception('Invalid Supabase URL format: $e');
  }
}

class AuthService {
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    print('Attempting to sign in with URL: ${dotenv.env['SUPABASE_URL']}'); // Debug print
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    final AuthResponse res = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
        'display_name': displayName ?? username,
      },
    );

    if (res.user != null) {
      // Create profile record
      await supabase.from('profiles').insert({
        'id': res.user!.id,
        'username': username,
        'display_name': displayName ?? username,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    return res;
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  static User? get currentUser => supabase.auth.currentUser;
} 