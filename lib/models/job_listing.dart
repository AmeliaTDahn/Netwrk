import 'package:supabase_flutter/supabase_flutter.dart';

class JobListing {
  final String id;
  final String businessId;
  final String title;
  final String description;
  final String requirements;
  final DateTime createdAt;
  final bool isActive;
  final String location;
  final String salary;

  JobListing({
    required this.id,
    required this.businessId,
    required this.title,
    required this.description,
    required this.requirements,
    required this.createdAt,
    required this.isActive,
    required this.location,
    required this.salary,
  });

  factory JobListing.fromMap(Map<String, dynamic> map) {
    return JobListing(
      id: map['id'],
      businessId: map['business_id'],
      title: map['title'],
      description: map['description'],
      requirements: map['requirements'],
      createdAt: DateTime.parse(map['created_at']),
      isActive: map['is_active'],
      location: map['location'],
      salary: map['salary'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'business_id': businessId,
      'title': title,
      'description': description,
      'requirements': requirements,
      'is_active': isActive,
      'location': location,
      'salary': salary,
    };
  }
} 