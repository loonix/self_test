import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

/// Example of integrating self_test with MCP server.
///
/// This shows the minimal setup required to enable AI-powered testing. It uses
/// the plain Navigator that every Flutter app already has, so nothing here
/// depends on a routing package.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the bridge in debug mode only
  if (kDebugMode) {
    final bridge = SelfTestBridge(navigator: _bridgeNavigator, port: 9999);
    await bridge.start();
    debugPrint('SelfTestBridge started on port 9999');
  }

  // Enable self-test mode
  SelfTestManager().setSelfTestModeActive(kDebugMode);

  runApp(const MyApp());
}

/// The key the app hands to MaterialApp, and the bridge drives.
final _navigatorKey = GlobalKey<NavigatorState>();

/// The default BridgeNavigator: it needs nothing but the key above.
final _bridgeNavigator = NavigatorStateBridgeNavigator(_navigatorKey);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SelfTestRoot(
      child: ScreenshotBoundary(
        child: MaterialApp(
          title: 'Self Test Example',
          navigatorKey: _navigatorKey,
          // Optional: lets the bridge report the whole route stack rather
          // than just the route on top.
          navigatorObservers: [_bridgeNavigator.observer],
          initialRoute: '/',
          routes: {
            '/': (_) => const HomeScreen(),
            '/login': (_) => const LoginScreen(),
            '/settings': (_) => const SettingsScreen(),
          },
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
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text('Go to Login'),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'settings_button',
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
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
                onPressed: () => Navigator.pop(context),
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
              onTap: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
