import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  test('Text assertions work through SelfTestManager', () {
    // Activate test mode
    SelfTestManager().setTestMode(true);

    // Create a test node with text input
    String? capturedText;
    final node = TestNode(
      id: 'username_field',
      onTextChange: (text) => capturedText = text,
    );
    SelfTestManager().registerTestNode(node);

    // Test entering text and asserting it
    SelfTestManager().enterText('username_field', 'testuser');
    expect(node.currentText, 'testuser');

    // Test that the node tracks text correctly
    SelfTestManager().enterText('username_field', 'newuser');
    expect(node.currentText, 'newuser');

    // Clean up
    SelfTestManager().unregisterTestNode('username_field');
  });

  test('Text assertions with multiple nodes', () {
    SelfTestManager().setTestMode(true);

    // Create multiple test nodes
    String? usernameText;
    String? passwordText;
    final usernameNode = TestNode(
      id: 'username_field',
      onTextChange: (text) => usernameText = text,
    );
    final passwordNode = TestNode(
      id: 'password_field',
      onTextChange: (text) => passwordText = text,
    );
    SelfTestManager().registerTestNode(usernameNode);
    SelfTestManager().registerTestNode(passwordNode);

    // Enter text in both
    SelfTestManager().enterText('username_field', 'testuser');
    SelfTestManager().enterText('password_field', 'testpass');

    // Verify both have correct text
    expect(usernameNode.currentText, 'testuser');
    expect(passwordNode.currentText, 'testpass');

    // Clean up
    SelfTestManager().unregisterTestNode('username_field');
    SelfTestManager().unregisterTestNode('password_field');
  });
}
