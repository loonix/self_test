import 'package:flutter/material.dart';

/// A custom rating widget that displays stars for rating selection.
/// This demonstrates how to create custom widgets that work with the self-testing framework.
class CustomRatingWidget extends StatefulWidget {
  final int maxRating;
  final int initialRating;
  final ValueChanged<int>? onRatingChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final double size;

  const CustomRatingWidget({
    Key? key,
    this.maxRating = 5,
    this.initialRating = 0,
    this.onRatingChanged,
    this.activeColor = Colors.amber,
    this.inactiveColor = Colors.grey,
    this.size = 30.0,
  }) : super(key: key);

  @override
  _CustomRatingWidgetState createState() => _CustomRatingWidgetState();
}

class _CustomRatingWidgetState extends State<CustomRatingWidget> {
  late int _currentRating;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;
  }

  void _onStarTap(int rating) {
    setState(() {
      _currentRating = rating;
    });
    widget.onRatingChanged?.call(rating);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        widget.maxRating,
        (index) => GestureDetector(
          onTap: () => _onStarTap(index + 1),
          child: Icon(
            index < _currentRating ? Icons.star : Icons.star_border,
            color: index < _currentRating
                ? widget.activeColor
                : widget.inactiveColor,
            size: widget.size,
          ),
        ),
      ),
    );
  }
}
