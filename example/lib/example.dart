import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

// The annotations below drive self_test_gen:
//   dart run build_runner build
// generates lib/example.g.dart, a standalone library holding
// ExampleStateTestController. Do NOT import it from here: importing a file
// that does not exist yet leaves this library unresolvable, the analyzer then
// sees no annotations, and the generator produces nothing. Import it from the
// test instead, see test/controller_test.dart.

class ExampleWidget extends StatefulWidget {
  const ExampleWidget({super.key});

  @override
  State<ExampleWidget> createState() => ExampleState();
}

class ExampleState extends State<ExampleWidget> {
  String username = '';

  @SelfTestButton('login_btn')
  void onLoginPressed() {
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
      appBar: AppBar(title: const Text('Example Widget')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SelfTestableWidget(
              id: 'username_field',
              onTextChange: onUsernameChanged,
              child: TextField(
                decoration: const InputDecoration(labelText: 'Username'),
                onChanged: onUsernameChanged,
              ),
            ),
            const SizedBox(height: 16),
            SelfTestableWidget(
              id: 'login_btn',
              onTap: onLoginPressed,
              child: ElevatedButton(
                onPressed: onLoginPressed,
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Current username: $username'),
          ],
        ),
      ),
    );
  }
}
