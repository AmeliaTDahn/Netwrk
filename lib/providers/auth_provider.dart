import 'dart:io';
import 'dart:async';
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
        emailRedirectTo: 'io.supabase.netwrk://login-callback/',
      );

      if (response.user == null) {
        throw Exception('Sign up failed - no user returned');
      }

      // Only create profile if email confirmation is not required or email is already confirmed
      if (response.user!.emailConfirmedAt != null) {
        await _createProfile(response.user!.id, username, email);
      }

    } catch (error) {
      print('Sign up error: $error');
      if (error is PostgrestException) {
        throw Exception('Database error: ${error.message}');
      } else if (error is AuthException) {
        throw Exception('Auth error: ${error.message}');
      } else {
        throw Exception('Unexpected error during sign up: $error');
      }
    }
  }

  // Separate method for creating profile
  Future<void> _createProfile(String userId, String username, String email) async {
    final profile = {
      'id': userId,
      'username': username,
      'display_name': username,
      'contact_email': email,
      'role': 'employee',
      'skills': '',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase
          .from('profiles')
          .insert(profile)
          .select()
          .single();
    } catch (e) {
      print('Error creating profile: $e');
      throw Exception('Failed to create profile: $e');
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Sign in failed - no user returned');
      }

      // Check if email is confirmed
      if (response.user!.emailConfirmedAt == null) {
        throw Exception('Please confirm your email before signing in');
      }

      // Create profile if it doesn't exist
      try {
        await _supabase
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .single();
      } catch (e) {
        await _createProfile(response.user!.id, email.split('@')[0], email);
      }

    } catch (error) {
      if (error is PostgrestException) {
        throw Exception('Database error: ${error.message}');
      } else if (error is AuthException) {
        throw Exception('Auth error: ${error.message}');
      } else {
        throw Exception(error.toString());
      }
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