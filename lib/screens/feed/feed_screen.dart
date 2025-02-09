import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/video_model.dart';
import '../../components/video_player_widget.dart';
import '../../core/supabase_config.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _businessPageController = PageController(initialPage: 0);
  final PageController _employeePageController = PageController(initialPage: 0);
  List<Map<String, dynamic>> _businessVideos = [];
  List<Map<String, dynamic>> _employeeVideos = [];
  bool _isLoading = true;
  int _currentBusinessIndex = 0;
  int _currentEmployeeIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadVideos();
    
    // Add listeners to page controllers
    _businessPageController.addListener(_onBusinessPageChanged);
    _employeePageController.addListener(_onEmployeePageChanged);
    
    _tabController.addListener(() {
      // Pause current video when switching tabs
      if (_tabController.index == 0) {
        _employeePageController.jumpTo(0);
      } else {
        _businessPageController.jumpTo(0);
      }
    });
  }

  void _onBusinessPageChanged() {
    final newIndex = _businessPageController.page?.round() ?? 0;
    if (newIndex != _currentBusinessIndex) {
      setState(() => _currentBusinessIndex = newIndex);
    }
  }

  void _onEmployeePageChanged() {
    final newIndex = _employeePageController.page?.round() ?? 0;
    if (newIndex != _currentEmployeeIndex) {
      setState(() => _currentEmployeeIndex = newIndex);
    }
  }

  Future<void> _loadVideos() async {
    try {
      setState(() => _isLoading = true);
      
      // Fetch videos for both categories
      final businessVideos = await _fetchVideos('business');
      final employeeVideos = await _fetchVideos('employee');

      if (mounted) {
        setState(() {
          _businessVideos = businessVideos;
          _employeeVideos = employeeVideos;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading videos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading videos: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchVideos(String category) async {
    try {
      final response = await supabase
          .from('videos')
          .select('''
            id,
            url,
            title,
            description,
            category,
            created_at,
            user_id,
            profiles!inner (
              id,
              username,
              display_name,
              photo_url,
              role
            )
          ''')
          .eq('category', category)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching $category videos: $e');
      rethrow;
    }
  }

  // Add refresh functionality
  Future<void> _refresh() async {
    await _loadVideos();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Netwrk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Businesses Tab
                  _businessVideos.isEmpty
                      ? const Center(child: Text('No business videos yet'))
                      : PageView.builder(
                          key: const PageStorageKey('business_videos'),
                          scrollDirection: Axis.vertical,
                          controller: _businessPageController,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          itemCount: _businessVideos.length,
                          itemBuilder: (context, index) {
                            final isVisible = index == _currentBusinessIndex && 
                                           _tabController.index == 0;
                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: isVisible ? 1.0 : 0.8,
                              child: Transform.scale(
                                scale: isVisible ? 1.0 : 0.95,
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width,
                                  height: MediaQuery.of(context).size.height,
                                  child: VideoPlayerWidget(
                                    key: ValueKey('business_${_businessVideos[index]['id']}'),
                                    video: VideoModel.fromJson(_businessVideos[index]),
                                    autoPlay: isVisible,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  // Employees Tab
                  _employeeVideos.isEmpty
                      ? const Center(child: Text('No employee videos yet'))
                      : PageView.builder(
                          key: const PageStorageKey('employee_videos'),
                          scrollDirection: Axis.vertical,
                          controller: _employeePageController,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          itemCount: _employeeVideos.length,
                          itemBuilder: (context, index) {
                            final isVisible = index == _currentEmployeeIndex && 
                                           _tabController.index == 1;
                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: isVisible ? 1.0 : 0.8,
                              child: Transform.scale(
                                scale: isVisible ? 1.0 : 0.95,
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width,
                                  height: MediaQuery.of(context).size.height,
                                  child: VideoPlayerWidget(
                                    key: ValueKey('employee_${_employeeVideos[index]['id']}'),
                                    video: VideoModel.fromJson(_employeeVideos[index]),
                                    autoPlay: isVisible,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _businessPageController.removeListener(_onBusinessPageChanged);
    _employeePageController.removeListener(_onEmployeePageChanged);
    _businessPageController.dispose();
    _employeePageController.dispose();
    super.dispose();
  }
} 