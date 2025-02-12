import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/unread_messages_provider.dart';
import '../providers/connection_requests_provider.dart';
import '../core/supabase_config.dart';

class BottomNavBar extends ConsumerWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  Widget _buildIconWithNotification({
    required bool isActive,
    required bool hasNotification,
    required IconData activeIcon,
    required IconData inactiveIcon,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(isActive ? activeIcon : inactiveIcon),
        if (hasNotification)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.5,
                ),
              ),
              constraints: const BoxConstraints(
                minWidth: 12,
                minHeight: 12,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnreadMessages = ref.watch(unreadMessagesProvider).when(
      data: (hasUnread) => hasUnread,
      loading: () => false,
      error: (_, __) => false,
    );

    final hasPendingConnections = ref.watch(hasConnectionRequestsProvider).when(
      data: (hasPending) => hasPending,
      loading: () => false,
      error: (_, __) => false,
    );

    // Get current user's account type
    final currentUserId = supabase.auth.currentUser?.id;
    final Future<Map<String, dynamic>?> accountType = currentUserId != null 
        ? supabase
            .from('profiles')
            .select('account_type')
            .eq('id', currentUserId)
            .single()
            .then((response) => response as Map<String, dynamic>)
        : Future.value(null);

    return FutureBuilder<Map<String, dynamic>?>(
      future: accountType,
      builder: (context, snapshot) {
        final isBusinessAccount = snapshot.data?['account_type'] == 'business';

        return BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          items: isBusinessAccount
            ? [
                BottomNavigationBarItem(
                  icon: _buildIconWithNotification(
                    isActive: false,
                    hasNotification: hasPendingConnections,
                    activeIcon: Icons.people,
                    inactiveIcon: Icons.people_outline,
                  ),
                  activeIcon: _buildIconWithNotification(
                    isActive: true,
                    hasNotification: hasPendingConnections,
                    activeIcon: Icons.people,
                    inactiveIcon: Icons.people_outline,
                  ),
                  label: 'Connect',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.work_outline),
                  activeIcon: Icon(Icons.work),
                  label: 'Listings',
                ),
                BottomNavigationBarItem(
                  icon: _buildIconWithNotification(
                    isActive: false,
                    hasNotification: hasUnreadMessages,
                    activeIcon: Icons.chat,
                    inactiveIcon: Icons.chat_outlined,
                  ),
                  activeIcon: _buildIconWithNotification(
                    isActive: true,
                    hasNotification: hasUnreadMessages,
                    activeIcon: Icons.chat,
                    inactiveIcon: Icons.chat_outlined,
                  ),
                  label: 'Messages',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ]
            : [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle_outline),
                  activeIcon: Icon(Icons.add_circle),
                  label: 'Create',
                ),
                BottomNavigationBarItem(
                  icon: _buildIconWithNotification(
                    isActive: false,
                    hasNotification: hasPendingConnections,
                    activeIcon: Icons.people,
                    inactiveIcon: Icons.people_outline,
                  ),
                  activeIcon: _buildIconWithNotification(
                    isActive: true,
                    hasNotification: hasPendingConnections,
                    activeIcon: Icons.people,
                    inactiveIcon: Icons.people_outline,
                  ),
                  label: 'Connect',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.work_outline),
                  activeIcon: Icon(Icons.work),
                  label: 'Listings',
                ),
                BottomNavigationBarItem(
                  icon: _buildIconWithNotification(
                    isActive: false,
                    hasNotification: hasUnreadMessages,
                    activeIcon: Icons.chat,
                    inactiveIcon: Icons.chat_outlined,
                  ),
                  activeIcon: _buildIconWithNotification(
                    isActive: true,
                    hasNotification: hasUnreadMessages,
                    activeIcon: Icons.chat,
                    inactiveIcon: Icons.chat_outlined,
                  ),
                  label: 'Messages',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
        );
      },
    );
  }
} 