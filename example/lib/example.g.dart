import 'package:self_test/self_test.dart';

class ExampleStateTestController {
  void tap_login_btn() {
    SelfTestManager().trigger('login_btn');
  }

  void enterText_username_field(String text) {
    SelfTestManager().enterText('username_field', text);
  }

  void expectExists_login_btn() {
    if (!SelfTestManager().activeTestNodes.containsKey('login_btn')) {
      throw Exception('TestNode with id "login_btn" does not exist');
    }
  }

  void expectNotExists_login_btn() {
    if (SelfTestManager().activeTestNodes.containsKey('login_btn')) {
      throw Exception('TestNode with id "login_btn" should not exist');
    }
  }

  void expectExists_username_field() {
    if (!SelfTestManager().activeTestNodes.containsKey('username_field')) {
      throw Exception('TestNode with id "username_field" does not exist');
    }
  }

  void expectNotExists_username_field() {
    if (SelfTestManager().activeTestNodes.containsKey('username_field')) {
      throw Exception('TestNode with id "username_field" should not exist');
    }
  }

  void expectText_username_field(String expectedText) {
    final node = SelfTestManager().activeTestNodes['username_field'];
    if (node == null) {
      throw Exception('TestNode with id "username_field" does not exist');
    }
    if (node.currentText != expectedText) {
      throw Exception('Expected text "$expectedText" but found "${node.currentText}" for id "username_field"');
    }
  }
}
