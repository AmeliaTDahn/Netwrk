import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/video_model.dart';
import '../../components/video_player_widget.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _businessPageController = PageController();
  final PageController _employeePageController = PageController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Reset page controllers when switching tabs
      if (_tabController.index == 0) {
        _employeePageController.jumpTo(0);
      } else {
        _businessPageController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _businessPageController.dispose();
    _employeePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Netwrk'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: theme.colorScheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Businesses'),
            Tab(text: 'Employees'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Businesses Tab
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _businessPageController,
            itemCount: businessVideos.length,
            itemBuilder: (context, index) {
              return VideoPlayerWidget(video: businessVideos[index]);
            },
          ),
          // Employees Tab
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _employeePageController,
            itemCount: employeeVideos.length,
            itemBuilder: (context, index) {
              return VideoPlayerWidget(video: employeeVideos[index]);
            },
          ),
        ],
      ),
    );
  }
} 