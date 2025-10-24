import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';
import 'custom_rating_widget.dart';

/// Recording builder for CustomRatingWidget.
/// This demonstrates how to create custom recording builders for third-party or custom widgets.
Widget buildRecordingCustomRatingWidget(Widget child, SelfTestableWidget selfTestableWidget) {
  final customRatingWidget = child as CustomRatingWidget;

  // For rating widgets, we need to make each star individually testable
  // We'll create a wrapper that exposes each star as a separate testable element
  return _RecordingCustomRatingWidget(
    originalWidget: customRatingWidget,
    selfTestableWidget: selfTestableWidget,
  );
}

class _RecordingCustomRatingWidget extends StatefulWidget {
  final CustomRatingWidget originalWidget;
  final SelfTestableWidget selfTestableWidget;

  const _RecordingCustomRatingWidget({
    Key? key,
    required this.originalWidget,
    required this.selfTestableWidget,
  }) : super(key: key);

  @override
  _RecordingCustomRatingWidgetState createState() => _RecordingCustomRatingWidgetState();
}

class _RecordingCustomRatingWidgetState extends State<_RecordingCustomRatingWidget> {
  late int _currentRating;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.originalWidget.initialRating;
  }

  @override
  void didUpdateWidget(_RecordingCustomRatingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update rating if the original widget's initial rating changed
    if (oldWidget.originalWidget.initialRating != widget.originalWidget.initialRating) {
      _currentRating = widget.originalWidget.initialRating;
    }
  }

  void _onRatingChanged(int rating) {
    setState(() {
      _currentRating = rating;
    });
    // Update the self-testable widget's text to reflect current rating
    widget.selfTestableWidget.onTextChange?.call(rating.toString());
    // Also call the original callback
    widget.originalWidget.onRatingChanged?.call(rating);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        widget.originalWidget.maxRating,
        (index) {
          final starRating = index + 1;
          final starId = '${widget.selfTestableWidget.id}_star_$starRating';

          return SelfTestableWidget(
            id: starId,
            onTap: () => _onRatingChanged(starRating),
            child: GestureDetector(
              onTap: () => _onRatingChanged(starRating),
              child: Icon(
                index < _currentRating ? Icons.star : Icons.star_border,
                color: index < _currentRating ? widget.originalWidget.activeColor : widget.originalWidget.inactiveColor,
                size: widget.originalWidget.size,
              ),
            ),
          );
        },
      ),
    );
  }
}
