import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/env_config.dart';

class AIService {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
  
  static Future<String> getVideoApplicationStrategy({
    required String jobTitle,
    required String description,
    required String requirements,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${EnvConfig.openAiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-4',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an expert career coach specializing in video applications. 
              Your task is to analyze the specific job listing provided and give ONLY recommendations that are directly relevant to this particular role and company.
              
              Important rules:
              1. DO NOT provide generic video application advice that could apply to any job
              2. ONLY provide recommendations that are specifically tailored to the job title, description, and requirements provided
              3. Focus on what makes THIS role unique and how to address its specific needs
              4. Reference specific details from the job listing in your recommendations
              5. If no specific details are provided, acknowledge this and explain that you cannot provide tailored advice without more information
              
              Structure your response with:
              1. Specific skills/experiences from the job requirements to highlight
              2. Unique aspects of this role/company to address
              3. Concrete examples of how to demonstrate fit for THIS specific position'''
            },
            {
              'role': 'user',
              'content': '''Please analyze this job listing and provide specific recommendations for creating an effective video application:
              
              Job Title: $jobTitle
              
              Description:
              $description
              
              Requirements:
              $requirements
              
              Provide specific, actionable advice for creating a video application that will stand out for this role.'''
            }
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('Failed to get AI recommendations: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error getting AI recommendations: $e');
    }
  }

  static Future<List<String>> generateVideoApplicationTips({
    required String jobTitle,
    required String description,
    required String requirements,
    required Map<String, dynamic> userProfile,
  }) async {
    try {
      // Extract and format user profile information in detail
      final userSkills = List<String>.from(userProfile['skills'] ?? []);
      final userExperience = List<Map<String, dynamic>>.from(userProfile['experience'] ?? []);
      final userEducation = List<Map<String, dynamic>>.from(userProfile['education'] ?? []);

      // Format experience details
      final formattedExperience = userExperience.map((exp) => '''
        Company: ${exp['company']}
        Role: ${exp['role']}
        Description: ${exp['description']}
      ''').join('\n');

      // Format education details
      final formattedEducation = userEducation.map((edu) => '''
        Institution: ${edu['institution']}
        Degree: ${edu['degree']}
        Field: ${edu['field_of_study']}
      ''').join('\n');
      
      final prompt = '''
You are creating personalized video application tips for a specific candidate applying to a specific job.
ONLY suggest highlighting experiences and skills that are explicitly listed in the candidate's profile.
DO NOT make assumptions about experiences they might have - stick to their actual background.

Job Details:
Title: $jobTitle

Description:
$description

Requirements:
$requirements

Candidate's Detailed Profile:

Skills They Have:
${userSkills.join(', ')}

Their Work Experience:
$formattedExperience

Their Education:
$formattedEducation

Instructions:
1. ONLY reference skills, experiences, and qualifications that are explicitly listed above
2. DO NOT suggest highlighting experience they don't have
3. Make specific connections between their ACTUAL experience and the job requirements
4. If there's a gap between requirements and their experience, focus on transferable skills they DO have

Generate 3 sections:

1. "Your Relevant Experience:"
ONLY mention experience they actually have that relates to this role.
Reference specific companies and roles from their profile.

2. "Your Matching Skills:"
ONLY list skills they actually have that match the job requirements.
Explain how they gained these skills based on their listed experience.

3. "Your Unique Background:"
Focus on their actual education and experience that makes them stand out.
Make specific connections to the job requirements.

Format: Return exactly 3 sections, each with a header followed by a colon and detailed explanation.
Every suggestion must be based on their actual profile data - no assumptions.
''';

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${EnvConfig.openAiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are a precise career coach who only makes recommendations based on verified information.
Never suggest highlighting experience the candidate doesn't have.
Only reference skills and experiences explicitly listed in their profile.
If there's a mismatch between requirements and their experience, focus on transferable skills they actually possess.
Be specific and reference actual companies, roles, and experiences from their profile.''',
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
          'temperature': 0.5, // Lower temperature for more focused responses
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to generate tips: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'] as String;
      
      // Split the content into sections and clean up
      final sections = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.trim())
          .toList();

      return sections;
    } catch (e) {
      print('Error generating video tips: $e');
      rethrow;
    }
  }
} 