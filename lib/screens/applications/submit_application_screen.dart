import 'package:flutter/material.dart';
import '../../components/application_coach_section.dart';
import '../../services/ai_service.dart';
import '../../core/supabase_config.dart';

class SubmitApplicationScreen extends StatefulWidget {
  final Map<String, dynamic> jobListing;
  
  const SubmitApplicationScreen({
    super.key,
    required this.jobListing,
  });

  @override
  State<SubmitApplicationScreen> createState() => _SubmitApplicationScreenState();
}

class _SubmitApplicationScreenState extends State<SubmitApplicationScreen> {
  bool _isCoachExpanded = true;
  bool _isLoadingTips = true;
  List<String> _tips = [];

  @override
  void initState() {
    super.initState();
    _loadPersonalizedTips();
  }

  Future<void> _loadPersonalizedTips() async {
    try {
      setState(() => _isLoadingTips = true);

      // Fetch user's profile data
      final userId = supabase.auth.currentUser!.id;
      final profileResponse = await supabase
          .from('profiles')
          .select('''
            *,
            profile_skills!inner (
              skills!inner (
                name
              )
            ),
            experience:profile_experience (
              company,
              role,
              description
            ),
            education:profile_education (
              institution,
              degree,
              field_of_study
            )
          ''')
          .eq('id', userId)
          .single();

      // Transform profile data for AI service
      final userProfile = {
        'skills': profileResponse['profile_skills']
            ?.map((s) => s['skills']['name'])
            .toList() ?? [],
        'experience': profileResponse['experience'] ?? [],
        'education': profileResponse['education'] ?? [],
      };

      // Generate personalized tips
      final tips = await AIService.generateVideoApplicationTips(
        jobTitle: widget.jobListing['title'],
        description: widget.jobListing['description'],
        requirements: widget.jobListing['requirements'],
        userProfile: userProfile,
      );

      if (mounted) {
        setState(() {
          _tips = tips;
          _isLoadingTips = false;
        });
      }
    } catch (e) {
      print('Error loading personalized tips: $e');
      if (mounted) {
        setState(() => _isLoadingTips = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load personalized tips. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessName = widget.jobListing['profiles']['business_name'] ?? 'Unknown Business';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Application'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Header section with job title and business name
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Applying for ${widget.jobListing['title']}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'at $businessName',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // AI Application Coach section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _isLoadingTips
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : ApplicationCoachSection(
                    tips: _tips,
                    isExpanded: _isCoachExpanded,
                    onToggle: () {
                      setState(() {
                        _isCoachExpanded = !_isCoachExpanded;
                      });
                    },
                  ),
          ),

          // Rest of your application form goes here
          // ...
        ],
      ),
      floatingActionButton: _isLoadingTips
          ? null
          : FloatingActionButton(
              onPressed: _loadPersonalizedTips,
              child: const Icon(Icons.refresh),
            ),
    );
  }
} 