import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../core/env_config.dart';
import '../core/supabase_client.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

class AIService {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
  static const String _whisperUrl = 'https://api.openai.com/v1/audio/transcriptions';
  
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
      final userName = userProfile['name'] as String?;
      final userSkills = List<String>.from(userProfile['skills'] ?? []);
      final userExperience = List<Map<String, dynamic>>.from(userProfile['experience'] ?? []);
      final userEducation = List<Map<String, dynamic>>.from(userProfile['education'] ?? []);
      final yearsOfExperience = userProfile['years_of_experience'];

      // Format experience details with dates and descriptions
      final formattedExperience = userExperience.map((exp) {
        final startDate = DateTime.parse(exp['start_date']).year.toString();
        final endDate = exp['is_current'] 
            ? 'Present'
            : exp['end_date'] != null 
                ? DateTime.parse(exp['end_date']).year.toString()
                : 'Present';
        
        return '''
          Company: ${exp['company']}
          Role: ${exp['role']}
          Period: $startDate - $endDate
          Description: ${exp['description']}
        ''';
      }).join('\n\n');

      // Format education details
      final formattedEducation = userEducation.map((edu) => '''
        Institution: ${edu['institution']}
        Degree: ${edu['degree']}
        Field: ${edu['field_of_study']}
      ''').join('\n');

      final prompt = '''
You are creating highly personalized video application tips for ${userName ?? 'a candidate'} applying to a specific job.
Your task is to analyze the candidate's actual experience and match it against the job requirements.
CRITICAL: You must ONLY suggest demonstrating skills and experiences that are EXPLICITLY listed in the candidate's profile.
Even if a skill is required by the job, if it's not in the candidate's profile, DO NOT suggest demonstrating it.
Your role is to find matches between the profile and requirements, NOT to suggest ways to demonstrate required skills they don't have.

Job Details:
Title: $jobTitle

Description:
$description

Requirements:
$requirements

Candidate's Profile:
IMPORTANT: This profile contains the ONLY skills and experiences you can suggest demonstrating.
If a required skill is not listed here, you MUST NOT suggest demonstrating it.
Your job is to find matches between these skills and the requirements, not to suggest ways to demonstrate missing skills.

Skills They Have:
${userSkills.join(', ')}

Their Work Experience:
$formattedExperience

Their Education:
$formattedEducation

Years of Experience: $yearsOfExperience

Instructions:
1. Start by identifying which job requirements match skills/experiences in their profile
2. COMPLETELY IGNORE job requirements that don't match anything in their profile
3. Only suggest demonstrating skills that are explicitly listed in their profile
4. If a critical job requirement isn't matched in their profile, simply note the gap - do not suggest ways to demonstrate skills they don't have
5. Focus on their actual, documented strengths that align with the role

Generate 3 sections:

1. "Skills You Can Demonstrate:"
List ONLY the skills from their profile that match job requirements.
Each skill mentioned must be explicitly present in their Skills, Experience, or Education sections.
Do not include any required skills that aren't in their profile.

2. "Relevant Experience You Have:"
Only discuss experiences from their profile that match job requirements.
Each experience must be directly linked to their work history or education.
Ignore job requirements that don't match their documented experience.

3. "Your Matching Strengths:"
Focus only on strengths explicitly shown in their profile that match the role.
Each strength must be evidenced by specific entries in their profile.
If a job requirement has no matching strength in their profile, do not mention it.

Format: Return exactly 3 sections, each with a header followed by a colon and detailed explanation.
Every suggestion must be based on explicit matches between their profile and the job requirements.
If there are few matches between their profile and the requirements, acknowledge this fact rather than suggesting ways to demonstrate skills they don't have.
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
              'content': '''You are a precise career coach who creates highly personalized video application tips.
Never use words like "maybe" or "perhaps" - only make definitive statements based on the candidate's actual experience.
If they have specific experience, tell them to highlight it.
If they don't have specific experience, tell them to focus on their transferable skills and genuine interest.
Every piece of advice must be based on verified information from their profile.''',
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
          'temperature': 0.3, // Lower temperature for more precise responses
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

  /// Transcribes a video application and stores the transcription in Supabase
  /// Returns the transcription ID and match rating if successful
  static Future<Map<String, dynamic>> transcribeAndStoreVideoApplication({
    required String videoPath,
    required String applicationId,
    required String listingId,
    required String userId,
  }) async {
    try {
      print('=== Starting Transcription Process ===');
      print('Input parameters:');
      print('- Video path: $videoPath');
      print('- Application ID: $applicationId');
      print('- Listing ID: $listingId');
      print('- User ID: $userId');
      
      // Verify video file exists
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        print('ERROR: Video file not found at path: $videoPath');
        throw Exception('Video file not found at path: $videoPath');
      }
      print('✓ Video file exists and is accessible');
      
      // Extract audio from video
      print('\n=== Audio Extraction Phase ===');
      print('Starting audio extraction from video...');
      final audioFile = await _extractAudioFromVideo(videoPath);
      print('✓ Audio extracted successfully to: ${audioFile.path}');
      print('Audio file size: ${await audioFile.length()} bytes');
      
      // Create multipart request
      print('\n=== Whisper API Request Phase ===');
      print('Preparing Whisper API request...');
      final request = http.MultipartRequest('POST', Uri.parse(_whisperUrl));
      request.headers.addAll({
        'Authorization': 'Bearer ${EnvConfig.openAiKey}',
      });
      
      // Add the audio file
      print('Adding audio file to request...');
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        filename: 'audio.m4a'
      ));
      
      // Add parameters
      request.fields.addAll({
        'model': 'whisper-1',
        'response_format': 'json',
        'language': 'en'
      });
      print('✓ Request prepared with all required fields');
      
      // Send request and get response
      print('\n=== Whisper API Response Phase ===');
      print('Sending request to Whisper API...');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      print('Whisper API response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        print('ERROR: Whisper API error response:');
        print(responseBody);
        throw Exception('Failed to transcribe video: $responseBody');
      }
      
      final transcriptionData = jsonDecode(responseBody);
      final transcription = transcriptionData['text'];
      print('✓ Transcription received successfully');
      print('Transcription length: ${transcription.length} characters');
      print('First 100 characters: ${transcription.substring(0, min<int>(100, transcription.length as int))}...');
      
      // Store in Supabase
      print('\n=== Supabase Storage Phase ===');
      print('Preparing to store transcription in Supabase...');
      print('Data to insert:');
      print('- Application ID: $applicationId');
      print('- Listing ID: $listingId');
      print('- User ID: $userId');
      print('- Transcription length: ${transcription.length}');
      
      try {
        print('Executing Supabase insert...');
        final result = await supabase.from('video_transcriptions').insert({
          'application_id': applicationId,
          'listing_id': listingId,
          'user_id': userId,
          'transcription': transcription,
          'created_at': DateTime.now().toIso8601String(),
        }).select('id').single();
        
        print('✓ Transcription stored successfully');
        print('Generated transcription ID: ${result['id']}');
        
        // Verify the stored transcription
        print('\n=== Verification Phase ===');
        print('Verifying stored transcription...');
        final storedTranscription = await supabase
            .from('video_transcriptions')
            .select('transcription')
            .eq('id', result['id'])
            .single();
            
        print('✓ Verified stored transcription exists');
        print('Stored transcription length: ${storedTranscription['transcription'].length}');
        
        // Clean up
        print('\n=== Cleanup Phase ===');
        print('Cleaning up temporary audio file...');
        await audioFile.delete();
        print('✓ Temporary audio file deleted');
        
        // Analyze the transcription
        print('\n=== Starting Match Analysis ===');
        final analysis = await analyzeApplicationTranscription(
          transcription: transcription,
          applicationId: applicationId,
          listingId: listingId,
          userId: userId,
        );
        
        print('\n=== Process Complete ===');
        print('Transcription and analysis completed successfully');
        print('Match rating: ${analysis['rating']}');
        
        return {
          'transcriptionId': result['id'],
          'matchRating': analysis['rating'],
          'matchAnalysis': analysis['analysis'],
        };
      } catch (supabaseError) {
        print('\nERROR: Supabase operation failed:');
        print('Error details: $supabaseError');
        print('Stack trace:');
        print(StackTrace.current);
        rethrow;
      }
    } catch (e, stackTrace) {
      print('\n=== ERROR IN TRANSCRIPTION PROCESS ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      
      // Check FFmpeg installation
      try {
        print('\nChecking FFmpeg installation...');
        final session = await FFmpegKit.execute('-version');
        final returnCode = await session.getReturnCode();
        print('FFmpegKit version check result:');
        print(returnCode);
      } catch (ffmpegKitError) {
        print('ERROR: FFmpegKit not found or not properly installed');
        print('FFmpegKit error: $ffmpegKitError');
      }
      
      rethrow;
    }
  }
  
  /// Helper method to extract audio from video file
  /// Returns a temporary File containing the audio in mp3 format
  static Future<File> _extractAudioFromVideo(String videoPath) async {
    try {
      final tempDir = Directory.systemTemp;
      final outputPath = '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      print('Starting audio extraction...');
      print('Input video path: $videoPath');
      print('Output audio path: $outputPath');
      
      // Use ffmpeg_kit_flutter to extract audio
      // Using AAC encoding which is widely supported and included in the default build
      final session = await FFmpegKit.execute(
        '-i "$videoPath" -vn -c:a aac -ar 44100 -ac 2 -b:a 192k "$outputPath"'
      );
      
      final returnCode = await session.getReturnCode();
      final logs = await session.getLogs();
      
      // Print all logs for debugging
      print('\nFFmpeg Logs:');
      for (final log in logs) {
        print('${log.getLevel()}: ${log.getMessage()}');
      }
      
      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (!await outputFile.exists()) {
          throw Exception('Output audio file was not created');
        }
        
        print('✓ Audio extraction successful');
        print('Audio file size: ${await outputFile.length()} bytes');
        
        return outputFile;
      } else {
        // Format logs into a readable string
        final logMessages = logs.map((log) => log.getMessage()).join('\n');
        throw Exception('FFmpeg process failed with error code: $returnCode\nLogs:\n$logMessages');
      }
    } catch (e) {
      print('Error extracting audio: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> analyzeApplicationTranscription({
    required String transcription,
    required String applicationId,
    required String listingId,
    required String userId,
  }) async {
    try {
      print('\n=== Starting Application Analysis ===');
      print('Fetching job listing and applicant profile data...');

      // Fetch job listing details
      final jobListing = await supabase
          .from('job_listings')
          .select('''
            title,
            description,
            requirements,
            business_id,
            profiles (
              business_name
            )
          ''')
          .eq('id', listingId)
          .single();

      // Fetch applicant profile
      final applicantProfile = await supabase
          .from('profiles')
          .select('''
            name,
            experience_years,
            education,
            bio
          ''')
          .eq('id', userId)
          .single();

      // Fetch user's skills
      final skillsResponse = await supabase
          .from('profile_skills')
          .select('''
            skills (
              name
            )
          ''')
          .eq('profile_id', userId);

      // Extract skill names from the response and properly cast to List<String>
      final List<String> skills = (skillsResponse as List<dynamic>)
          .map((record) => (record['skills'] as Map<String, dynamic>)['name'] as String)
          .toList();

      print('✓ Data fetched successfully');
      print('Skills found: ${skills.join(', ')}');
      print('Preparing analysis request...');

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${EnvConfig.openAiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an expert AI recruiter tasked with analyzing video application transcriptions.
Your goal is to evaluate how well a candidate matches a job listing based on their video application, work experience, and profile.

You must provide:
1. A match rating from 1.0 to 10.0 (one decimal point)
2. A detailed analysis explaining the rating

Rules for rating:
- Use a scale of 1.0 (no match) to 10.0 (perfect match)
- Consider both hard skills and soft skills
- Weight factors in this order:
  1. Relevant work experience (most important)
  2. Video content and communication
  3. Skills and education
- Look for specific examples of relevant work experience
- Compare years of experience against job requirements
- Consider the quality and relevance of past roles
- Evaluate how they presented their experience in the video
- Consider communication skills demonstrated
- Be objective and fair in your assessment
- A 10.0 is rare, but possible if the candidate is a near-perfect fit
- Don't be afraid to give a 10.0, or high rating, if the candidate is a near-perfect fit

Keep your analysis focused on:
1. How their work experience matches the role
2. Specific examples from their background
3. How they presented their experience in the video
4. Any gaps between their experience and requirements

Your response must be in JSON format with two fields:
{
  "rating": number between 1.0 and 10.0,
  "analysis": detailed explanation string
}'''
            },
            {
              'role': 'user',
              'content': '''Please analyze this video application:

Job Details:
Title: ${jobListing['title']}
Description: ${jobListing['description']}
Requirements: ${jobListing['requirements']}

Applicant Profile:
Name: ${applicantProfile['name']}
Skills: ${skills.join(', ')}
Years of Experience: ${applicantProfile['experience_years']}
Education: ${applicantProfile['education']}
Bio: ${applicantProfile['bio']}

Video Application Transcription:
$transcription

Analyze how well this candidate matches the job requirements based on their video application and profile.
Provide a rating from 1.0 to 10.0 and a detailed analysis.
Remember to focus more heavily on what they demonstrated in the video than what's in their profile.'''
            }
          ],
          'response_format': { 'type': 'json_object' },
          'temperature': 0.3,
        }),
      );

      if (response.statusCode != 200) {
        print('ERROR: Failed to analyze application');
        print('Response: ${response.body}');
        throw Exception('Failed to analyze application: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final result = jsonDecode(data['choices'][0]['message']['content']);
      
      print('✓ Analysis completed successfully');
      print('Match rating: ${result['rating']}');
      
      // Store the results
      print('\n=== Storing Analysis Results ===');
      final storedResult = await supabase
          .from('application_match_ratings')
          .insert({
            'application_id': applicationId,
            'listing_id': listingId,
            'user_id': userId,
            'match_rating': result['rating'],
            'analysis_text': result['analysis'],
          })
          .select('id')
          .single();
          
      print('✓ Analysis results stored successfully');
      print('Generated rating ID: ${storedResult['id']}');
      
      return {
        'rating': result['rating'],
        'analysis': result['analysis'],
        'id': storedResult['id']
      };
    } catch (e, stackTrace) {
      print('\n=== ERROR IN APPLICATION ANALYSIS ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
} 