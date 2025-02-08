import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/main_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/auth/sign_up_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/connect/connect_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/create/create_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/profile/business_profile_screen.dart';
import '../screens/connect/connection_requests_screen.dart';
import '../screens/messages/chat_screen.dart';
import '../screens/listings/listings_screen.dart';
import '../screens/listings/job_listings_browse_screen.dart';
import '../screens/listings/submit_application_screen.dart';
import '../providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/notifications/notifications_screen.dart';

class NoTransitionPage<T> extends CustomTransitionPage<T> {
  NoTransitionPage({
    required Widget child,
    LocalKey? key,
  }) : super(
          key: key,
          child: child,
          transitionsBuilder: (_, __, ___, child) => child,
          transitionDuration: Duration.zero,
        );
}

class NetwrkApp extends ConsumerWidget {
  const NetwrkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: '/signin',
      routes: [
        GoRoute(
          path: '/signin',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const SignInScreen(),
          ),
        ),
        GoRoute(
          path: '/signup',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const SignUpScreen(),
          ),
        ),
        GoRoute(
          path: '/onboarding',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const OnboardingScreen(),
          ),
        ),
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 1),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 3),
          ),
        ),
        GoRoute(
          path: '/connect',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 1),
          ),
          routes: [
            GoRoute(
              path: 'discover',
              pageBuilder: (context, state) => NoTransitionPage(
                child: const MainScreen(
                  initialIndex: 1,
                  initialConnectTab: 0, // 0 for discover tab
                ),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/messages',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 2),
          ),
        ),
        GoRoute(
          path: '/create',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 0),
          ),
        ),
        GoRoute(
          path: '/profile/:id',
          builder: (context, state) => UserProfileScreen(
            userId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/business-profile/:id',
          builder: (context, state) => BusinessProfileScreen(
            userId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/connection-requests',
          builder: (context, state) => const ConnectionRequestsScreen(),
        ),
        GoRoute(
          path: '/messages/:chatId',
          builder: (context, state) => ChatScreen(
            chatId: state.pathParameters['chatId']!,
          ),
        ),
        GoRoute(
          path: '/listings',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 1),
          ),
        ),
        GoRoute(
          path: '/browse-jobs',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 2),
          ),
        ),
        GoRoute(
          path: '/submit-application/:jobId',
          builder: (context, state) => SubmitApplicationScreen(
            jobListingId: state.pathParameters['jobId']!,
            jobTitle: state.uri.queryParameters['title'] ?? '',
            businessName: state.uri.queryParameters['business'] ?? '',
          ),
        ),
        GoRoute(
          path: '/employee',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 2),
          ),
        ),
        GoRoute(
          path: '/notifications',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const NotificationsScreen(),
          ),
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) async {
        final isAuth = authState != null;
        final isGoingToAuth = state.matchedLocation == '/signin' || 
                            state.matchedLocation == '/signup';
        final isGoingToOnboarding = state.matchedLocation == '/onboarding';

        // If not authenticated and not going to auth page, redirect to signin
        if (!isAuth && !isGoingToAuth) {
          return '/signin';
        }

        // If authenticated and going to auth page, redirect to home or onboarding
        if (isAuth && isGoingToAuth) {
          // Check if profile is complete
          try {
            final profile = await Supabase.instance.client
                .from('profiles')
                .select('account_type')
                .eq('id', authState.id)
                .single();
            
            // If profile doesn't have an account type, redirect to onboarding
            if (profile == null || profile['account_type'] == null) {
              return '/onboarding';
            }
            
            return '/';
          } catch (e) {
            // If no profile exists, redirect to onboarding
            return '/onboarding';
          }
        }

        // If authenticated but no profile, redirect to onboarding
        if (isAuth && !isGoingToOnboarding) {
          try {
            final profile = await Supabase.instance.client
                .from('profiles')
                .select('account_type')
                .eq('id', authState.id)
                .single();
            
            // If profile doesn't have an account type, redirect to onboarding
            if (profile == null || profile['account_type'] == null) {
              return '/onboarding';
            }
          } catch (e) {
            // If no profile exists, redirect to onboarding
            return '/onboarding';
          }
        }

        return null;
      },
    );

    return MaterialApp.router(
      routerConfig: router,
      title: 'Netwrk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF2196F3),    // Light blue
          secondary: const Color(0xFF1565C0),   // Dark blue
          surface: Colors.white,
          background: const Color(0xFFFAFAFA),  // Very light grey
          onBackground: Colors.black87,
        ),
        // Keep all the existing theme configurations
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          titleMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
} 