import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

/// A login screen written by someone who has never heard of this package.
///
/// No `SelfTestRoot`, no `SelfTestableWidget`, no `@SelfTestButton`, no
/// generated controller, no import of `self_test` at all. Driving this is the
/// whole point of universal locators: before them, a widget had to be wrapped
/// and registered before the package could touch it, which meant the package
/// could only test apps that had already been changed to suit it.
class PlainLogin extends StatefulWidget {
  const PlainLogin({super.key});

  @override
  State<PlainLogin> createState() => _PlainLoginState();
}

class _PlainLoginState extends State<PlainLogin> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _message = '';
  bool _remember = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() {
      if (_username.text.isEmpty || _password.text.isEmpty) {
        _message = 'Fill in both fields';
      } else if (_password.text.length < 6) {
        _message = 'Password too short';
      } else {
        _message = 'Welcome, ${_username.text}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: Column(
          children: [
            TextField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            SwitchListTile(
              title: const Text('Remember me'),
              value: _remember,
              onChanged: (value) => setState(() => _remember = value),
            ),
            ElevatedButton(onPressed: _submit, child: const Text('Sign in')),
            Text(_message),
            IconButton(
              tooltip: 'Reset',
              onPressed: () {
                _username.clear();
                _password.clear();
                setState(() => _message = '');
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  final manager = SelfTestManager();

  tearDown(manager.clearClock);

  testWidgets('drives an app that knows nothing about self_test', (
    tester,
  ) async {
    await tester.pumpWidget(const PlainLogin());

    // The label is beside the field, not around it. Resolving from the word on
    // screen to the field it belongs to is what an agent actually asks for.
    await manager.typeInto(const SelfTestLocator.text('Username'), 'ada');
    await manager.typeInto(const SelfTestLocator.text('Password'), 'short');
    await manager.tap(const SelfTestLocator.text('Sign in'));
    await tester.pump();

    expect(
      manager.exists(const SelfTestLocator.text('Password too short')),
      isTrue,
      reason: 'the app validated what was really typed',
    );

    await manager.typeInto(
      const SelfTestLocator.text('Password'),
      'long enough',
    );
    await manager.tap(const SelfTestLocator.text('Sign in'));
    await tester.pump();

    expect(manager.exists(const SelfTestLocator.text('Welcome, ada')), isTrue);
  });

  testWidgets('flips a switch and reads the screen back', (tester) async {
    await tester.pumpWidget(const PlainLogin());

    await manager.tap(const SelfTestLocator.text('Remember me'));
    await tester.pump();

    final switchState = manager.find(const SelfTestLocator.type('Switch'));
    expect(switchState.isEnabled, isTrue);
    expect(
      (switchState.element.widget as Switch).value,
      isTrue,
      reason: 'tapping the tile toggled the real switch',
    );
  });

  testWidgets('uses a tooltip to reach a button with no text', (tester) async {
    await tester.pumpWidget(const PlainLogin());

    await manager.typeInto(const SelfTestLocator.text('Username'), 'ada');
    await manager.typeInto(
      const SelfTestLocator.text('Password'),
      'longenough',
    );
    await manager.tap(const SelfTestLocator.text('Sign in'));
    await tester.pump();
    expect(manager.exists(const SelfTestLocator.text('Welcome, ada')), isTrue);

    await manager.tap(const SelfTestLocator.tooltip('Reset'));
    await tester.pump();

    expect(manager.exists(const SelfTestLocator.text('Welcome, ada')), isFalse);
    expect(
      manager.readText(const SelfTestLocator.text('Username')),
      'Username',
    );
  });

  testWidgets('describes the screen well enough to choose an action', (
    tester,
  ) async {
    await tester.pumpWidget(const PlainLogin());

    final screen = manager.describeScreen();
    final actionable = screen
        .where((snapshot) => snapshot.isInteractive)
        .map((snapshot) => snapshot.typeName)
        .toSet();

    expect(actionable, containsAll(<String>['TextField', 'ElevatedButton']));
    expect(
      screen.any((s) => s.tooltip == 'Reset'),
      isTrue,
      reason: 'an icon-only button is invisible to a text-only description',
    );
    expect(
      screen.every((s) => s.isOnScreen),
      isTrue,
      reason: 'nothing off screen is offered as an action',
    );
  });
}
