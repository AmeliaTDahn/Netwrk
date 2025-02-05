import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

final supabaseProvider = StateProvider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) {
  return AuthNotifier(ref.watch(supabaseProvider));
});

class AuthNotifier extends StateNotifier<User?> {
  final SupabaseClient _supabase;

  AuthNotifier(this._supabase) : super(_supabase.auth.currentUser) {
    _supabase.auth.onAuthStateChange.listen((data) {
      state = data.session?.user;
    });
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
      );

      if (response.user != null) {
        await _supabase.from('users').insert({
          'id': response.user!.id,
          'email': email,
          'username': username,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (error) {
      throw Exception('Failed to sign up: $error');
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (error) {
      throw Exception('Failed to sign in: $error');
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> updateProfile({
    String? username,
    String? fullName,
    String? avatarUrl,
    String? bio,
    String? website,
  }) async {
    final user = state;
    if (user == null) throw Exception('Must be logged in to update profile');

    try {
      await _supabase
          .from('profiles')
          .update({
            if (username != null) 'username': username,
            if (fullName != null) 'full_name': fullName,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
            if (bio != null) 'bio': bio,
            if (website != null) 'website': website,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
    } catch (error) {
      throw Exception('Failed to update profile: $error');
    }
  }
} 