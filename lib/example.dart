import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

part 'example.self_test.g.dart';

class ExampleState extends State<ExampleWidget> {
  @SelfTestButton('login_btn')
  void onLoginPressed() {
    // login logic
  }

  @SelfTestInput('username_field')
  void onUsernameChanged(String value) {
    // handle username
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(onChanged: onUsernameChanged),
        ElevatedButton(onPressed: onLoginPressed, child: Text('Login')),
      ],
    );
  }
}

class ExampleWidget extends StatefulWidget {
  @override
  State<ExampleWidget> createState() => ExampleState();
}
