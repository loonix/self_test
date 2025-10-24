# Self Test Example

This example demonstrates the self-testing framework for Flutter applications, including how to create and register custom recording builders for third-party or custom widgets.

## Features Demonstrated

### Built-in Widget Support
The framework comes with built-in support for common Flutter widgets:
- TextField, TextFormField
- Buttons (ElevatedButton, TextButton, OutlinedButton, IconButton, FloatingActionButton)
- Form controls (Checkbox, Radio, Switch, Slider)
- List tiles (CheckboxListTile, RadioListTile, SwitchListTile, ListTile)

### Automatic Activation
In debug builds, self-test mode is **automatically activated** when the app starts. This means:
- The recording overlay is immediately available
- All testable widgets are registered without manual activation
- Users can start recording tests right away
- In release builds, the framework remains inactive for optimal performance

### Custom Widget Extensibility

This example includes a custom `CustomRatingWidget` that demonstrates how to extend the framework for unsupported widgets.

#### Creating a Custom Widget
```dart
class CustomRatingWidget extends StatefulWidget {
  // ... widget implementation
}
```

#### Creating a Recording Builder
```dart
Widget buildRecordingCustomRatingWidget(Widget child, SelfTestableWidget selfTestableWidget) {
  final customRatingWidget = child as CustomRatingWidget;
  return _RecordingCustomRatingWidget(
    originalWidget: customRatingWidget,
    selfTestableWidget: selfTestableWidget,
  );
}
```

#### Registering the Builder
```dart
void main() {
  // Register custom recording builder
  SelfTestManager().registerRecordingBuilder<CustomRatingWidget>(buildRecordingCustomRatingWidget);
  runApp(MyApp());
}
```

#### Using the Custom Widget
```dart
SelfTestableWidget(
  id: 'app_rating',
  onTextChange: (rating) => print('Rated: $rating'),
  child: CustomRatingWidget(
    initialRating: 3,
    onRatingChanged: (rating) => print('Rating changed to: $rating'),
  ),
)
```

## Testing the Custom Component

1. Run the app and activate self-test mode
2. Record interactions with the rating widget
3. Use the programmatic test button to see automated rating selection
4. Export tests to Dart or JSON format

## How It Works

The custom rating widget creates individual testable elements for each star:
- `app_rating_star_1` - First star
- `app_rating_star_2` - Second star
- `app_rating_star_3` - Third star
- `app_rating_star_4` - Fourth star
- `app_rating_star_5` - Fifth star

This allows precise recording and replay of user interactions with complex custom widgets.
