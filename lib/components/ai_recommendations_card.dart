import 'package:flutter/material.dart';
import '../services/ai_service.dart';

class AIRecommendationsCard extends StatefulWidget {
  final String jobTitle;
  final String description;
  final String requirements;

  const AIRecommendationsCard({
    super.key,
    required this.jobTitle,
    required this.description,
    required this.requirements,
  });

  @override
  State<AIRecommendationsCard> createState() => _AIRecommendationsCardState();
}

class _AIRecommendationsCardState extends State<AIRecommendationsCard> {
  bool _isExpanded = false;
  bool _isLoading = false;
  String? _recommendations;
  String? _error;

  Future<void> _loadRecommendations() async {
    if (_recommendations != null) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final recommendations = await AIService.getVideoApplicationStrategy(
        jobTitle: widget.jobTitle,
        description: widget.description,
        requirements: widget.requirements,
      );

      if (mounted) {
        setState(() {
          _recommendations = recommendations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text(
              'AI Application Coach',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _isExpanded 
                  ? 'Tap to collapse'
                  : 'Get AI-powered recommendations for your video',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            trailing: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() => _isExpanded = !_isExpanded);
              if (_isExpanded && _recommendations == null) {
                _loadRecommendations();
              }
            },
          ),
          if (_isExpanded) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildContent(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Analyzing job listing...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            'Error getting recommendations',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadRecommendations,
            child: const Text('Try Again'),
          ),
        ],
      );
    }

    if (_recommendations == null) {
      return const Center(child: Text('No recommendations available'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recommendations for Your Video Application',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _recommendations!,
          style: const TextStyle(height: 1.5),
        ),
      ],
    );
  }
} 