import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

void main() {
  runApp(SelfTestRoot(child: MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self Test Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginPage(),
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
  }

  void _onPasswordChanged(String value) {
    setState(() {
      password = value;
    });
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
                decoration: InputDecoration(labelText: 'Username'),
                onChanged: _onUsernameChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'password_field',
              onTextChange: _onPasswordChanged,
              child: TextField(
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
                // Example test
                SelfTestManager().enterText('username_field', 'testuser');
                SelfTestManager().enterText('password_field', 'testpass');
                await SelfTestManager().waitForAnimations();
                SelfTestManager().trigger('login_button');
                await SelfTestManager().waitForAnimations();
              },
              child: Text('Run Test'),
            ),
          ],
        ),
      ),
    );
  }
}
