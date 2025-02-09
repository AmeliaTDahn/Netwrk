import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import './feed/feed_screen.dart';
import './create/create_screen.dart';
import './profile/profile_screen.dart';
import './messages/messages_screen.dart';
import './connect/connect_screen.dart';
import './employee/employee_screen.dart';
import './listings/business_listings_screen.dart';
import './listings/job_listings_browse_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_config.dart';
import '../components/bottom_nav_bar.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final int? initialConnectTab;

  const MainScreen({
    super.key,
    this.initialIndex = 0,
    this.initialConnectTab,
  });

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late int _selectedIndex;
  String? _accountType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadAccountType();
  }

  Future<void> _loadAccountType() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await supabase
          .from('profiles')
          .select('account_type')
          .eq('id', userId)
          .single();

      setState(() {
        _accountType = data['account_type'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Widget> get _screens {
    if (_accountType == 'business') {
      return [
        ConnectScreen(initialTab: widget.initialConnectTab),
        const BusinessListingsScreen(),
        const MessagesScreen(),
        const ProfileScreen(),
      ];
    }
    return [
      const CreateScreen(),
      ConnectScreen(initialTab: widget.initialConnectTab),
      const JobListingsBrowseScreen(),
      const MessagesScreen(),
      const ProfileScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    if (_accountType == 'business') {
      switch (index) {
        case 0:
          context.go('/connect');
          break;
        case 1:
          context.go('/listings');
          break;
        case 2:
          context.go('/messages');
          break;
        case 3:
          context.go('/profile');
          break;
      }
    } else {
      switch (index) {
        case 0:
          context.go('/create');
          break;
        case 1:
          context.go('/connect');
          break;
        case 2:
          context.go('/browse-jobs');
          break;
        case 3:
          context.go('/messages');
          break;
        case 4:
          context.go('/profile');
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    Widget body;
    if (_accountType == 'business') {
      switch (_selectedIndex) {
        case 0:
          body = const ConnectScreen();
          break;
        case 1:
          body = const BusinessListingsScreen();
          break;
        case 2:
          body = const MessagesScreen();
          break;
        case 3:
          body = const ProfileScreen();
          break;
        default:
          body = const SizedBox.shrink();
      }
    } else {
      switch (_selectedIndex) {
        case 0:
          body = const CreateScreen();
          break;
        case 1:
          body = const ConnectScreen();
          break;
        case 2:
          body = const JobListingsBrowseScreen();
          break;
        case 3:
          body = const MessagesScreen();
          break;
        case 4:
          body = const ProfileScreen();
          break;
        default:
          body = const SizedBox.shrink();
      }
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
} 