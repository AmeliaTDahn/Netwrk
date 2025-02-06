import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/main_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/auth/sign_up_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/create/create_screen.dart';
import '../providers/auth_provider.dart';

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
          path: '/',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 0),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 4),
          ),
        ),
        GoRoute(
          path: '/explore',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 2),
          ),
        ),
        GoRoute(
          path: '/messages',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 3),
          ),
        ),
        GoRoute(
          path: '/create',
          pageBuilder: (context, state) => NoTransitionPage(
            child: const MainScreen(initialIndex: 1),
          ),
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final isAuth = authState != null;
        final isGoingToAuth = state.matchedLocation == '/signin' || 
                            state.matchedLocation == '/signup';

        // If not authenticated and not going to auth page, redirect to signin
        if (!isAuth && !isGoingToAuth) {
          return '/signin';
        }

        // If authenticated and going to auth page, redirect to home
        if (isAuth && isGoingToAuth) {
          return '/';
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