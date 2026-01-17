import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

part 'example.g.dart';

class ExampleState extends State<ExampleWidget> {
  String username = '';

  @SelfTestButton('login_btn')
  void onLoginPressed() {
    // login logic
    debugPrint('Login pressed with username: $username');
  }

  @SelfTestInput('username_field')
  void onUsernameChanged(String value) {
    setState(() {
      username = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Example Widget')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            SelfTestableWidget(
              id: 'username_field',
              onTextChange: onUsernameChanged,
              child: TextField(
                decoration: InputDecoration(labelText: 'Username'),
                onChanged: onUsernameChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'login_btn',
              onTap: onLoginPressed,
              child: ElevatedButton(
                onPressed: onLoginPressed,
                child: Text('Login'),
              ),
            ),
            SizedBox(height: 16),
            Text('Current username: $username'),
          ],
        ),
      ),
    );
  }
}

class ExampleWidget extends StatefulWidget {
  @override
  State<ExampleWidget> createState() => ExampleState();
}
