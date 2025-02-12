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
} 