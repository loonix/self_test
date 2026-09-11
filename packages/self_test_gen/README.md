# self_test_gen

`build_runner` code generator for [`self_test`](https://pub.dev/packages/self_test).

It turns `@SelfTestButton` and `@SelfTestInput` annotations into a typed test
controller, so a test says `controller.tapLoginBtn()` instead of repeating a
string id that nothing checks.

This package holds only the generator. It lives apart from `self_test` so that
`analyzer`, `source_gen` and `build` stay out of your app: they are build-time
tools, and shipping them as runtime dependencies dragged the whole analyzer
into every consumer.

## Install

```yaml
dependencies:
  self_test: ^0.2.0

dev_dependencies:
  build_runner: ^2.4.9
  self_test_gen: ^0.2.0
```

## Use

Annotate the state class, or the handlers inside it:

```dart
class _LoginFormState extends State<LoginForm> {
  @SelfTestButton('login_btn')
  void _submit() { /* ... */ }

  @SelfTestInput('username_field')
  void _onUsernameChanged(String value) { /* ... */ }
}
```

Generate:

```bash
dart run build_runner build
```

You get `login_form.g.dart` next to the source, with one controller per
annotated class:

```dart
class LoginFormStateTestController {
  void tapLoginBtn();
  void enterUsernameField(String text);
  void expectUsernameFieldText(String expectedText);
  void expectLoginBtnExists();
  void expectLoginBtnDoesNotExist();
}
```

Import it from your test. **Do not** write a `part` directive for it and do not
import it from the file it was generated from: the builder emits a standalone
library, and importing it from its own source makes that library unresolvable,
at which point the generator sees no annotations and silently produces nothing.

## What the names look like

Method names are camelCase derived from the id, so generated code passes the
same lints as hand-written code: `login_btn` becomes `tapLoginBtn()`. The id
itself is used verbatim in the call to `SelfTestManager`, because that is the
key the widget registered itself under.

A private class generates a public controller: `_LoginFormState` becomes
`LoginFormStateTestController`, which a test in another library can actually
name.

## Supported versions

Verified against Flutter 3.35.0 (Dart 3.9.0) and Flutter 3.47.2 (Dart 3.13.2),
both ends of the range CI runs. Generated output is byte-identical under
either.

## License

MIT, see [LICENSE](LICENSE).
