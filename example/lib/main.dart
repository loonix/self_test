import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SelfTestRoot(
      navigatorKey: navigatorKey,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Self Test Example',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: LoginPage(),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
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
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            SelfTestableWidget(
              id: 'username_field',
              onTextChange: _onUsernameChanged,
              child: TextField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username'),
                onChanged: _onUsernameChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'password_field',
              onTextChange: _onPasswordChanged,
              child: TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                onChanged: _onPasswordChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'login_button',
              onTap: _onLoginPressed,
              child: ElevatedButton(
                onPressed: _onLoginPressed,
                child: Text('Login'),
              ),
            ),
            SizedBox(height: 16),
            Text(message),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                debugPrint('[SelfTest] Activating self-test mode...');
                SelfTestManager().setSelfTestModeActive(true);
                SelfTestManager().restartWidgetTree();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Self-test mode activated')),
                );
              },
              child: Text('Activate Self-Test Mode'),
            ),
            ElevatedButton(
              onPressed: () async {
                debugPrint('[SelfTest] ===== STARTING PROGRAMMATIC TEST =====');
                // Activate test mode to register widgets
                SelfTestManager().setTestMode(true);
                SelfTestManager().restartWidgetTree();
                await Future.delayed(const Duration(milliseconds: 100)); // Wait for registration

                // Example test
                SelfTestManager().enterText('username_field', 'testuser');
                SelfTestManager().enterText('password_field', 'testpass');
                await SelfTestManager().waitForAnimations();
                SelfTestManager().trigger('login_button');
                await SelfTestManager().waitForAnimations();

                // Deactivate test mode
                SelfTestManager().setTestMode(false);
                SelfTestManager().restartWidgetTree();
                debugPrint('[SelfTest] ===== TEST COMPLETED =====');
              },
              child: Text('Run Programmatic Test'),
            ),
          ],
        ),
      ),
    );
  }
}
