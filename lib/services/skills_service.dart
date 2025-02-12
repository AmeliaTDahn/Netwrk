import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SkillsService {
  static const String _openaiApiUrl = 'https://api.openai.com/v1/embeddings';

  // Update how we get the OpenAI API key
  static String get _openaiApiKey {
    final key = dotenv.env['OPENAI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('OPENAI_API_KEY not found in environment variables');
    }
    print('OpenAI API Key length: ${key.length}');  // Don't print the actual key
    return key;
  }

  // Get embedding using OpenAI's text-embedding-3-small model
  static Future<List<double>> _getEmbedding(String skillName, String category) async {
    try {
      final context = '''
      Skill Analysis:
      Name: $skillName
      Category: $category
      Professional Context: This is a professional skill in the $category field.
      When someone has this skill, they typically also have related skills in the same or complementary fields.
      For example, someone with this $category skill might also have experience with other $category skills or related professional capabilities.
      
      Question: What other professional skills in the $category field or related fields are commonly used together with $skillName?
      ''';

      print('=== Getting Embedding ===');
      print('Skill: $skillName');
      print('Category: $category');
      print('API Key length: ${_openaiApiKey.length}');

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/embeddings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_openaiApiKey}',
        },
        body: jsonEncode({
          'model': 'text-embedding-3-small',
          'input': context,
          'encoding_format': 'float',
        }),
      );

      print('Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        print('Error response: ${response.body}');
        throw Exception('Failed to get embedding: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (data['data'] == null || data['data'].isEmpty) {
        print('No embedding data in response: $data');
        throw Exception('No embedding data returned');
      }

      final embedding = List<double>.from(data['data'][0]['embedding']);
      print('Got embedding of length: ${embedding.length}');
      print('First 5 values: ${embedding.take(5).toList()}');
      print('Last 5 values: ${embedding.skip(embedding.length - 5).take(5).toList()}');
      print('Contains non-zero values: ${embedding.any((v) => v != 0)}');

      return embedding;
    } catch (e, stackTrace) {
      print('Error getting embedding: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Update skill embedding in the database
  static Future<void> updateSkillEmbedding(int skillId, String skillName, String category) async {
    try {
      print('Starting embedding update for $skillName...');
      final embedding = await _getEmbedding(skillName, category);
      
      // Verify embedding is not all zeros
      bool allZeros = embedding.every((value) => value == 0);
      if (allZeros) {
        throw Exception('Generated embedding is all zeros');
      }
      
      print('Got valid embedding of length ${embedding.length} for $skillName');
      print('First few values: ${embedding.take(5).toList()}');
      
      // Convert embedding to Postgres vector format
      final vectorString = embedding.join(',');
      
      // Update using raw SQL to ensure proper vector format
      await supabase
          .rpc('update_skill_embedding', 
              params: {
                'skill_id': skillId,
                'embedding_vector': vectorString
              });
      
      print('Updated embedding in database for $skillName');
    } catch (e) {
      print('Error updating skill embedding for $skillName: $e');
      rethrow;
    }
  }

  // Update embeddings for all skills that don't have them
  static Future<void> updateAllSkillEmbeddings() async {
    try {
      final skills = await supabase
          .from('skills')
          .select('id, name, category');

      print('Updating embeddings for ${skills.length} skills');

      for (final skill in skills) {
        try {
          await updateSkillEmbedding(
            skill['id'] as int,
            skill['name'] as String,
            skill['category'] as String,
          );
          print('Updated embedding for: ${skill['name']}');
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          print('Error updating embedding for ${skill['name']}: $e');
        }
      }
    } catch (e) {
      print('Error updating all skill embeddings: $e');
    }
  }

  // Get skill suggestions for a user using vector similarity
  static Future<List<String>> getSuggestedSkills(String userId, {
    int limit = 5,
    double similarityThreshold = 0.7, // Lowered threshold for testing
  }) async {
    try {
      print('Getting suggestions for user: $userId');
      
      // First check if user has any skills
      final userSkills = await supabase
          .from('profile_skills')
          .select('skill_id, skills!inner(name)')
          .eq('profile_id', userId);
      
      print('User has ${userSkills.length} skills: ${userSkills.map((s) => s['skills']['name']).toList()}');

      if (userSkills.isEmpty) {
        print('User has no skills, returning empty suggestions');
        return [];
      }

      final response = await supabase
          .rpc('get_skill_suggestions', 
              params: {
                'user_id': userId,
                'match_count': limit,
                'similarity_threshold': similarityThreshold,
              });
      
      print('Raw suggestion response: $response');
      
      if (response == null || response.isEmpty) {
        print('No suggestions returned from database');
        return [];
      }

      // Print detailed information about each suggestion
      for (var row in response) {
        print('''
Suggestion details:
- Suggested skill: ${row['skill_name']}
- Category: ${row['category']}
- Similarity score: ${row['similarity']}
- Based on user's skill: ${row['based_on']}
''');
      }
      
      final suggestions = List<String>.from(
        response.map((row) => row['skill_name'] as String)
      );
      
      print('Final suggestions list: $suggestions');
      return suggestions;
    } catch (e) {
      print('Error getting skill suggestions: $e');
      print('Error stack trace: ${StackTrace.current}');
      return [];
    }
  }

  // When adding a new custom skill
  static Future<void> addNewSkill(String skillName) async {
    try {
      // First insert the skill
      final response = await supabase
          .from('skills')
          .insert({'name': skillName})
          .select()
          .single();
      
      // Then generate and update its embedding
      await updateSkillEmbedding(
        response['id'] as int,
        skillName,
        response['category'] as String,
      );
    } catch (e) {
      print('Error adding new skill: $e');
    }
  }

  // Add a method to reset and regenerate all embeddings
  static Future<void> resetAndRegenerateEmbeddings() async {
    try {
      // First, clear all existing embeddings
      await supabase
          .from('skills')
          .update({'embedding': null});
      
      print('Cleared existing embeddings');
      
      // Then regenerate all embeddings
      await updateAllSkillEmbeddings();
      
      print('Regenerated all embeddings');
    } catch (e) {
      print('Error resetting embeddings: $e');
    }
  }

  // Add this method to force regenerate all embeddings
  static Future<void> forceRegenerateAllEmbeddings() async {
    try {
      print('Step 1: Clearing embeddings...');
      await supabase
          .from('skills')
          .update({'embedding': null});
      
      print('Step 2: Getting all skills...');
      final skills = await supabase
          .from('skills')
          .select('id, name, category');
      
      print('Found ${skills.length} skills to update');
      
      for (final skill in skills) {
        print('Processing skill: ${skill['name']} (${skill['category']})');
        try {
          print('Getting embedding...');
          final embedding = await _getEmbedding(skill['name'], skill['category']);
          print('Got embedding, updating database...');
          
          await supabase
              .from('skills')
              .update({'embedding': embedding})
              .eq('id', skill['id']);
          
          print('Successfully updated embedding for: ${skill['name']}');
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          print('Error processing ${skill['name']}: $e');
        }
      }
      print('Completed embedding generation');
    } catch (e) {
      print('Error in forceRegenerateAllEmbeddings: $e');
    }
  }

  // Add this test function
  static Future<void> testSimilarityQueries() async {
    try {
      print('\n=== Testing Similarity Queries ===');
      
      // Get a test skill (Python)
      final pythonSkill = await supabase
          .from('skills')
          .select('id, name, category, embedding')
          .eq('name', 'Python')
          .single();
      
      print('Python embedding: ${pythonSkill['embedding']}');
      
      // Find similar skills directly using vector similarity
      final similarSkills = await supabase
          .rpc('get_similar_skills',
              params: {
                'query_embedding': pythonSkill['embedding'],
                'match_threshold': 0.7,
                'match_count': 5
              });
      
      print('\nSimilar skills to Python:');
      for (var skill in similarSkills) {
        print('- ${skill['name']} (${skill['category']}) - similarity: ${skill['similarity']}');
      }
      
    } catch (e) {
      print('Error testing similarity: $e');
    }
  }

  static Future<void> debugSkillSimilarity(String skillName) async {
    try {
      print('\n=== Debugging Similarity for $skillName ===');
      
      // Get the skill's embedding
      final skill = await supabase
          .from('skills')
          .select('id, name, category, embedding')
          .eq('name', skillName)
          .single();
          
      print('Skill embedding exists: ${skill['embedding'] != null}');
      
      // Test similarity directly
      final similar = await supabase
          .rpc('test_similarity', 
              params: {'skill_name': skillName});
              
      print('\nSimilar skills to $skillName:');
      for (var row in similar) {
        print('- ${row['similar_skill']} (${row['category']}) - similarity: ${row['similarity']}');
      }
    } catch (e) {
      print('Error in debug: $e');
    }
  }
} 