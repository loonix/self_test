import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import '../lib/custom_rating_widget.dart';
import '../lib/custom_rating_builder.dart';

void main() {
  testWidgets('Custom rating widget builder registration works',
      (WidgetTester tester) async {
    // Register the custom builder
    SelfTestManager().registerRecordingBuilder<CustomRatingWidget>(
        buildRecordingCustomRatingWidget);

    // Activate test mode BEFORE building widgets
    SelfTestManager().setTestMode(true);

    // Build a test widget with the custom rating widget
    await tester.pumpWidget(
      SelfTestRoot(
        child: MaterialApp(
          home: Scaffold(
            body: SelfTestableWidget(
              id: 'test_rating',
              child: CustomRatingWidget(
                initialRating: 2,
                maxRating: 5,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Debug: print all active nodes
    debugPrint(
        'Active nodes: ${SelfTestManager().activeTestNodes.keys.toList()}');

    // Check that individual star elements are registered
    expect(SelfTestManager().activeTestNodes.containsKey('test_rating_star_1'),
        true);
    expect(SelfTestManager().activeTestNodes.containsKey('test_rating_star_2'),
        true);
    expect(SelfTestManager().activeTestNodes.containsKey('test_rating_star_3'),
        true);
    expect(SelfTestManager().activeTestNodes.containsKey('test_rating_star_4'),
        true);
    expect(SelfTestManager().activeTestNodes.containsKey('test_rating_star_5'),
        true);

    // Test triggering a star tap
    await SelfTestManager().trigger('test_rating_star_4');
    await tester.pumpAndSettle();

    // Verify the rating changed (this would be reflected in the widget state)
    // The actual verification would depend on the widget's implementation

    // Clean up
    SelfTestManager().setTestMode(false);
  });
}
