import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';
import 'example.dart';

void main() {
  runApp(SelfTestRoot(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self Test Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String username = '';
  String password = '';
  String message = '';

  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: username);
    _passwordController = TextEditingController(text: password);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (username.isNotEmpty && password.isNotEmpty) {
      setState(() {
        message = 'Login successful!';
      });
    } else {
      setState(() {
        message = 'Please fill all fields';
      });
    }
  }

  void _onUsernameChanged(String value) {
    setState(() {
      username = value;
    });
    _usernameController.text = value;
  }

  void _onPasswordChanged(String value) {
    setState(() {
      password = value;
    });
    _passwordController.text = value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SelfTestableWidget(
              id: 'username_field',
              onTextChange: _onUsernameChanged,
              child: TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                onChanged: _onUsernameChanged,
              ),
            ),
            const SizedBox(height: 16),
            SelfTestableWidget(
              id: 'password_field',
              onTextChange: _onPasswordChanged,
              child: TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                onChanged: _onPasswordChanged,
              ),
            ),
            const SizedBox(height: 16),
            SelfTestableWidget(
              id: 'login_button',
              onTap: _onLoginPressed,
              child: ElevatedButton(
                onPressed: _onLoginPressed,
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 16),
            Text(message),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                debugPrint('[SelfTest] Activating self-test mode...');
                SelfTestManager().setSelfTestModeActive(true);
                // No snackbar here. restartWidgetTree rebuilds everything
                // below SelfTestRoot, MaterialApp and its ScaffoldMessenger
                // included, so a snackbar shown around this call is torn down
                // in the same frame. The restart is what makes the widgets
                // re-register, so it is the snackbar that has to go.
                SelfTestManager().restartWidgetTree();
              },
              child: const Text('Activate Self-Test Mode'),
            ),
            // Survives the restart, unlike a snackbar, because it is derived
            // from the manager rather than held in this widget's state.
            Text(
              SelfTestManager().isSelfTestModeActive
                  ? 'Self-test mode activated'
                  : 'Self-test mode off',
            ),
            ElevatedButton(
              onPressed: () async {
                debugPrint('[SelfTest] ===== STARTING TEST =====');
                SelfTestManager().enterText('username_field', 'testuser');
                SelfTestManager().enterText('password_field', 'testpass');
                await SelfTestManager().waitForAnimations();
                SelfTestManager().trigger('login_button');
                await SelfTestManager().waitForAnimations();
                debugPrint('[SelfTest] ===== TEST COMPLETED =====');
              },
              child: const Text('Run Test'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ExampleWidget(),
                  ),
                );
              },
              child: const Text('Open Example Widget'),
            ),
          ],
        ),
      ),
    );
  }
}
