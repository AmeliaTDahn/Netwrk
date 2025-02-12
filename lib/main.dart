import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/app.dart';
import 'core/supabase_config.dart';
import 'screens/connect/connection_requests_screen.dart';
import 'package:go_router/go_router.dart';
import 'services/skills_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load .env file and verify
  await dotenv.load();
  
  // Debug print to verify .env loading
  print('SUPABASE_URL: ${dotenv.env['SUPABASE_URL']}');
  print('SUPABASE_ANON_KEY length: ${dotenv.env['SUPABASE_ANON_KEY']?.length}');
  
  // Validate Supabase configuration
  validateConfig();
  
  // Initialize Supabase
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: true,
      authFlowType: AuthFlowType.pkce,
    );
    print('Supabase initialized successfully');
  } catch (e) {
    print('Error initializing Supabase: $e');
  }

  // Force regenerate all embeddings with new context
  print('Starting embedding generation...');
  await SkillsService.forceRegenerateAllEmbeddings();
  
  // Test similarity queries
  await SkillsService.testSimilarityQueries();
  
  // Add after forceRegenerateAllEmbeddings
  await SkillsService.debugSkillSimilarity('Carpentry');
  
  print('Finished embedding generation');

  runApp(const ProviderScope(child: NetwrkApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Netwrk'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(
          child: Text(
            'Welcome to Netwrk',
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
} 