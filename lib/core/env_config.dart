import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static String get openAiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  
  static Future<void> load() async {
    await dotenv.load(fileName: ".env");
  }
} 