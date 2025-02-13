import 'package:supabase_flutter/supabase_flutter.dart';

class JobListing {
  final String id;
  final String businessId;
  final String title;
  final String description;
  final String requirements;
  final DateTime createdAt;
  final bool isActive;
  final String? location;
  final String? salary;
  final String? interviewMessageTemplate;
  final List<String> videoApplicationTips;

  JobListing({
    required this.id,
    required this.businessId,
    required this.title,
    required this.description,
    required this.requirements,
    required this.createdAt,
    required this.isActive,
    this.location,
    this.salary,
    this.interviewMessageTemplate,
    this.videoApplicationTips = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'title': title,
      'description': description,
      'requirements': requirements,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
      'location': location,
      'salary': salary,
      'interview_message_template': interviewMessageTemplate,
      'video_application_tips': videoApplicationTips,
    };
  }

  factory JobListing.fromMap(Map<String, dynamic> map) {
    return JobListing(
      id: map['id'] ?? '',
      businessId: map['business_id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      requirements: map['requirements'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      isActive: map['is_active'] ?? true,
      location: map['location'],
      salary: map['salary'],
      interviewMessageTemplate: map['interview_message_template'],
      videoApplicationTips: List<String>.from(map['video_application_tips'] ?? []),
    );
  }
} 