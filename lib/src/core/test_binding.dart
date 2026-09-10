import 'package:flutter/widgets.dart';

/// Whether the app is running under `flutter_test` rather than on a device.
///
/// `WidgetsBinding.instance` is a [WidgetsFlutterBinding] in a real app and a
/// `TestWidgetsFlutterBinding` under `flutter_test`, so this tells the two
/// apart without the core taking a dependency on `flutter_test`.
///
/// Two behaviours hang on it, both of which made the package unusable from a
/// widget test:
///
/// - the recording controls are a live overlay, and `pumpAndSettle` on a tree
///   containing them never returns
/// - a real `Future.delayed` never completes inside a `testWidgets` body,
///   because the test owns the clock and only `pump` advances it
bool get isRunningUnderTest =>
    WidgetsBinding.instance is! WidgetsFlutterBinding;
