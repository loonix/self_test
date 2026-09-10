import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

/// Example of integrating self_test with MCP server.
///
/// This shows the minimal setup required to enable AI-powered testing.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the bridge in debug mode only
  if (kDebugMode) {
    final bridge = SelfTestBridge(router: _router, port: 9999);
    await bridge.start();
    debugPrint('SelfTestBridge started on port 9999');
  }

  // Enable self-test mode
  SelfTestManager().setSelfTestModeActive(kDebugMode);

  runApp(const MyApp());
}

// GoRouter configuration
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SelfTestRoot(
      child: ScreenshotBoundary(
        child: MaterialApp.router(
          title: 'Self Test Example',
          routerConfig: _router,
        ),
      ),
    );
  }
}

// Example screens with semantic labels for stable test IDs

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Semantic label provides stable test ID
            Semantics(
              label: 'login_button',
              child: ElevatedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Go to Login'),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'settings_button',
              child: ElevatedButton(
                onPressed: () => context.go('/settings'),
                child: const Text('Go to Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Text input with semantic label
            Semantics(
              label: 'email_input',
              child: TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'password_input',
              child: TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              label: 'submit_button',
              child: ElevatedButton(
                onPressed: _handleLogin,
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'back_button',
              child: TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleLogin() {
    // Handle login logic
    debugPrint('Login: ${_emailController.text}');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Semantics(
            label: 'notifications_toggle',
            child: SwitchListTile(
              title: const Text('Notifications'),
              value: true,
              onChanged: (value) {},
            ),
          ),
          Semantics(
            label: 'dark_mode_toggle',
            child: SwitchListTile(
              title: const Text('Dark Mode'),
              value: false,
              onChanged: (value) {},
            ),
          ),
          Semantics(
            label: 'logout_button',
            child: ListTile(
              title: const Text('Logout'),
              leading: const Icon(Icons.logout),
              onTap: () => context.go('/'),
            ),
          ),
        ],
      ),
    );
  }
}
