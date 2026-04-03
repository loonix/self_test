import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  test('Text assertions work through SelfTestManager', () {
    SelfTestManager().setTestMode(true);

    final node = TestNode(
      id: 'username_field',
      onTextChange: (text) {},
    );
    SelfTestManager().registerTestNode(node);

    SelfTestManager().enterText('username_field', 'testuser');
    expect(node.currentText, 'testuser');

    SelfTestManager().enterText('username_field', 'newuser');
    expect(node.currentText, 'newuser');

    SelfTestManager().unregisterTestNode('username_field');
  });

  test('Text assertions with multiple nodes', () {
    SelfTestManager().setTestMode(true);

    final usernameNode = TestNode(
      id: 'username_field',
      onTextChange: (text) {},
    );
    final passwordNode = TestNode(
      id: 'password_field',
      onTextChange: (text) {},
    );
    SelfTestManager().registerTestNode(usernameNode);
    SelfTestManager().registerTestNode(passwordNode);

    SelfTestManager().enterText('username_field', 'testuser');
    SelfTestManager().enterText('password_field', 'testpass');

    expect(usernameNode.currentText, 'testuser');
    expect(passwordNode.currentText, 'testpass');

    SelfTestManager().unregisterTestNode('username_field');
    SelfTestManager().unregisterTestNode('password_field');
  });
}
