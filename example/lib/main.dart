import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';
import 'custom_rating_widget.dart';
import 'custom_rating_builder.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Register custom recording builder for our custom rating widget
  SelfTestManager().registerRecordingBuilder<CustomRatingWidget>(buildRecordingCustomRatingWidget);

  // Automatically activate self-test mode in debug builds
  if (kDebugMode || kProfileMode) {
    debugPrint('[SelfTest] Automatically activating self-test mode in debug build');
    SelfTestManager().setSelfTestModeActive(true);
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SelfTestRoot(
      navigatorKey: navigatorKey,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Self Test Example',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: LoginPage(),
        routes: {
          '/profile': (context) => ProfilePage(),
          '/settings': (context) => SettingsPage(),
          '/list': (context) => ListPage(),
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String username = '';
  String password = '';
  String email = '';
  bool rememberMe = false;
  String gender = 'male';
  String country = 'usa';
  int appRating = 3; // Add state for app rating
  String message = '';

  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: username);
    _passwordController = TextEditingController(text: password);
    _emailController = TextEditingController(text: email);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (username.isNotEmpty && password.isNotEmpty) {
      setState(() {
        message = 'Login successful!';
      });
    } else {
      setState(() {
        message = 'Please fill all fields';
      });
    }
  }

  void _onUsernameChanged(String value) {
    setState(() {
      username = value;
    });
    _usernameController.text = value;
  }

  void _onPasswordChanged(String value) {
    setState(() {
      password = value;
    });
    _passwordController.text = value;
  }

  void _onEmailChanged(String value) {
    setState(() {
      email = value;
    });
    _emailController.text = value;
  }

  void _onRememberMeChanged(bool? value) {
    setState(() {
      rememberMe = value ?? false;
    });
  }

  void _onGenderChanged(String? value) {
    if (value != null) {
      setState(() {
        gender = value;
      });
    }
  }

  void _onCountryChanged(String? value) {
    if (value != null) {
      setState(() {
        country = value;
      });
    }
  }

  void _onAppRatingChanged(int rating) {
    setState(() {
      appRating = rating;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelfTestableWidget(
              id: 'username_field',
              onTextChange: _onUsernameChanged,
              child: TextField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username'),
                onChanged: _onUsernameChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'password_field',
              onTextChange: _onPasswordChanged,
              child: TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                onChanged: _onPasswordChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'email_field',
              onTextChange: _onEmailChanged,
              child: TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                onChanged: _onEmailChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'remember_checkbox',
              onTap: () => _onRememberMeChanged(!rememberMe),
              child: CheckboxListTile(
                title: Text('Remember me'),
                value: rememberMe,
                onChanged: _onRememberMeChanged,
              ),
            ),
            SizedBox(height: 16),
            Text('Gender:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SelfTestableWidget(
              id: 'gender_male',
              onTap: () => _onGenderChanged('male'),
              child: RadioListTile<String>(
                title: Text('Male'),
                value: 'male',
                groupValue: gender,
                onChanged: _onGenderChanged,
              ),
            ),
            SelfTestableWidget(
              id: 'gender_female',
              onTap: () => _onGenderChanged('female'),
              child: RadioListTile<String>(
                title: Text('Female'),
                value: 'female',
                groupValue: gender,
                onChanged: _onGenderChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'country_dropdown',
              onTextChange: (text) => setState(() => country = text),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Country'),
                value: country,
                items: [
                  DropdownMenuItem(value: 'usa', child: Text('United States')),
                  DropdownMenuItem(value: 'canada', child: Text('Canada')),
                  DropdownMenuItem(value: 'uk', child: Text('United Kingdom')),
                  DropdownMenuItem(value: 'germany', child: Text('Germany')),
                ],
                onChanged: _onCountryChanged,
              ),
            ),
            SizedBox(height: 16),
            Text('Rate our app:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            SelfTestableWidget(
              id: 'app_rating',
              onTextChange: (rating) => setState(() => appRating = int.parse(rating)),
              child: CustomRatingWidget(
                initialRating: appRating,
                onRatingChanged: (rating) {
                  _onAppRatingChanged(rating);
                  debugPrint('User rated the app: $rating stars');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Thanks for rating us $rating stars!')),
                  );
                },
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'login_button',
              onTap: _onLoginPressed,
              child: ElevatedButton(
                onPressed: _onLoginPressed,
                child: Text('Login'),
              ),
            ),
            SizedBox(height: 16),
            Text(message),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SelfTestableWidget(
                    id: 'go_to_profile',
                    onTap: () => Navigator.pushNamed(context, '/profile'),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/profile'),
                      child: Text('Go to Profile'),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: SelfTestableWidget(
                    id: 'go_to_settings',
                    onTap: () => Navigator.pushNamed(context, '/settings'),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/settings'),
                      child: Text('Go to Settings'),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'go_to_list',
              onTap: () => Navigator.pushNamed(context, '/list'),
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/list'),
                child: Text('Go to Scrollable List (100 items)'),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                debugPrint('[SelfTest] ===== STARTING STAR RATING TEST =====');
                // Activate test mode to register widgets
                SelfTestManager().setTestMode(true);
                SelfTestManager().restartWidgetTree();
                await Future.delayed(const Duration(milliseconds: 100)); // Wait for registration

                // Test the custom rating widget - rate 3 stars
                debugPrint('[SelfTest] Testing custom rating widget - rating 3 stars...');
                SelfTestManager().trigger('app_rating_star_3'); // Rate 3 stars
                await SelfTestManager().waitForAnimations();

                // Wait a bit and then rate 5 stars
                await Future.delayed(const Duration(milliseconds: 500));
                debugPrint('[SelfTest] Changing rating to 5 stars...');
                SelfTestManager().trigger('app_rating_star_5'); // Rate 5 stars
                await SelfTestManager().waitForAnimations();

                // Deactivate test mode (don't restart widget tree to preserve state)
                SelfTestManager().setTestMode(false);
                debugPrint('[SelfTest] ===== STAR RATING TEST COMPLETED =====');
              },
              child: Text('Test Star Rating'),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                debugPrint('[SelfTest] ===== RECORDING STAR RATING TEST =====');
                // Start recording a new test script
                await SelfTestManager().startRecording('Star Rating Test');

                // The user can now interact with the app to record steps
                // For demonstration, we'll programmatically add some steps
                await Future.delayed(const Duration(milliseconds: 500));

                // Simulate clicking on star 4
                SelfTestManager().trigger('app_rating_star_4');
                await SelfTestManager().waitForAnimations();

                await Future.delayed(const Duration(milliseconds: 500));

                // Stop recording
                SelfTestManager().stopRecording();
                debugPrint('[SelfTest] ===== STAR RATING TEST RECORDING COMPLETED =====');
              },
              child: Text('Record Star Rating Test'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String firstName = '';
  String lastName = '';
  String age = '';
  String bio = '';
  bool isStudent = false;
  bool notifications = true;
  String favoriteColor = 'blue';
  double experience = 3.0;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _ageController;
  late TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: firstName);
    _lastNameController = TextEditingController(text: lastName);
    _ageController = TextEditingController(text: age);
    _bioController = TextEditingController(text: bio);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _onFirstNameChanged(String value) {
    setState(() => firstName = value);
  }

  void _onLastNameChanged(String value) {
    setState(() => lastName = value);
  }

  void _onAgeChanged(String value) {
    setState(() => age = value);
  }

  void _onBioChanged(String value) {
    setState(() => bio = value);
  }

  void _onStudentChanged(bool? value) {
    setState(() => isStudent = value ?? false);
  }

  void _onNotificationsChanged(bool? value) {
    setState(() => notifications = value ?? false);
  }

  void _onColorChanged(String? value) {
    if (value != null) {
      setState(() => favoriteColor = value);
    }
  }

  void _onExperienceChanged(double value) {
    setState(() => experience = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        leading: SelfTestableWidget(
          id: 'back_from_profile',
          onTap: () => Navigator.pop(context),
          child: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Personal Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'first_name_field',
              onTextChange: _onFirstNameChanged,
              child: TextField(
                controller: _firstNameController,
                decoration: InputDecoration(labelText: 'First Name'),
                onChanged: _onFirstNameChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'last_name_field',
              onTextChange: _onLastNameChanged,
              child: TextField(
                controller: _lastNameController,
                decoration: InputDecoration(labelText: 'Last Name'),
                onChanged: _onLastNameChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'age_field',
              onTextChange: _onAgeChanged,
              child: TextField(
                controller: _ageController,
                decoration: InputDecoration(labelText: 'Age'),
                keyboardType: TextInputType.number,
                onChanged: _onAgeChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'bio_field',
              onTextChange: _onBioChanged,
              child: TextField(
                controller: _bioController,
                decoration: InputDecoration(labelText: 'Bio'),
                maxLines: 3,
                onChanged: _onBioChanged,
              ),
            ),
            SizedBox(height: 24),
            Text('Preferences', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'student_checkbox',
              onTap: () => _onStudentChanged(!isStudent),
              child: CheckboxListTile(
                title: Text('Are you a student?'),
                value: isStudent,
                onChanged: _onStudentChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'notifications_checkbox',
              onTap: () => _onNotificationsChanged(!notifications),
              child: CheckboxListTile(
                title: Text('Enable notifications'),
                value: notifications,
                onChanged: _onNotificationsChanged,
              ),
            ),
            SizedBox(height: 16),
            Text('Favorite Color:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SelfTestableWidget(
              id: 'color_red',
              onTap: () => _onColorChanged('red'),
              child: RadioListTile<String>(
                title: Text('Red'),
                value: 'red',
                groupValue: favoriteColor,
                onChanged: _onColorChanged,
              ),
            ),
            SelfTestableWidget(
              id: 'color_blue',
              onTap: () => _onColorChanged('blue'),
              child: RadioListTile<String>(
                title: Text('Blue'),
                value: 'blue',
                groupValue: favoriteColor,
                onChanged: _onColorChanged,
              ),
            ),
            SelfTestableWidget(
              id: 'color_green',
              onTap: () => _onColorChanged('green'),
              child: RadioListTile<String>(
                title: Text('Green'),
                value: 'green',
                groupValue: favoriteColor,
                onChanged: _onColorChanged,
              ),
            ),
            SizedBox(height: 16),
            Text('Years of Experience: ${experience.round()}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SelfTestableWidget(
              id: 'experience_slider',
              onTextChange: (text) => setState(() => experience = double.parse(text)),
              child: Slider(
                value: experience,
                min: 0,
                max: 10,
                divisions: 10,
                label: experience.round().toString(),
                onChanged: _onExperienceChanged,
              ),
            ),
            SizedBox(height: 24),
            SelfTestableWidget(
              id: 'save_profile_button',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Profile saved!')),
                );
              },
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Profile saved!')),
                  );
                },
                child: Text('Save Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool darkMode = false;
  bool soundEnabled = true;
  bool vibration = true;
  String language = 'en';
  String theme = 'light';
  double volume = 0.7;

  void _onDarkModeChanged(bool? value) {
    setState(() => darkMode = value ?? false);
  }

  void _onSoundChanged(bool? value) {
    setState(() => soundEnabled = value ?? false);
  }

  void _onVibrationChanged(bool? value) {
    setState(() => vibration = value ?? false);
  }

  void _onLanguageChanged(String? value) {
    if (value != null) {
      setState(() => language = value);
    }
  }

  void _onThemeChanged(String? value) {
    if (value != null) {
      setState(() => theme = value);
    }
  }

  void _onVolumeChanged(double value) {
    setState(() => volume = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        leading: SelfTestableWidget(
          id: 'back_from_settings',
          onTap: () => Navigator.pop(context),
          child: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'dark_mode_switch',
              onTap: () => _onDarkModeChanged(!darkMode),
              child: SwitchListTile(
                title: Text('Dark Mode'),
                value: darkMode,
                onChanged: _onDarkModeChanged,
              ),
            ),
            SizedBox(height: 16),
            Text('Theme:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SelfTestableWidget(
              id: 'theme_light',
              onTap: () => _onThemeChanged('light'),
              child: RadioListTile<String>(
                title: Text('Light'),
                value: 'light',
                groupValue: theme,
                onChanged: _onThemeChanged,
              ),
            ),
            SelfTestableWidget(
              id: 'theme_dark',
              onTap: () => _onThemeChanged('dark'),
              child: RadioListTile<String>(
                title: Text('Dark'),
                value: 'dark',
                groupValue: theme,
                onChanged: _onThemeChanged,
              ),
            ),
            SelfTestableWidget(
              id: 'theme_system',
              onTap: () => _onThemeChanged('system'),
              child: RadioListTile<String>(
                title: Text('System'),
                value: 'system',
                groupValue: theme,
                onChanged: _onThemeChanged,
              ),
            ),
            SizedBox(height: 24),
            Text('Audio & Feedback', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'sound_switch',
              onTap: () => _onSoundChanged(!soundEnabled),
              child: SwitchListTile(
                title: Text('Sound Effects'),
                value: soundEnabled,
                onChanged: _onSoundChanged,
              ),
            ),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'vibration_switch',
              onTap: () => _onVibrationChanged(!vibration),
              child: SwitchListTile(
                title: Text('Vibration'),
                value: vibration,
                onChanged: _onVibrationChanged,
              ),
            ),
            SizedBox(height: 16),
            Text('Volume: ${(volume * 100).round()}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SelfTestableWidget(
              id: 'volume_slider',
              onTextChange: (text) => setState(() => volume = double.parse(text)),
              child: Slider(
                value: volume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                label: '${(volume * 100).round()}%',
                onChanged: _onVolumeChanged,
              ),
            ),
            SizedBox(height: 24),
            Text('Language & Region', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SelfTestableWidget(
              id: 'language_dropdown',
              onTextChange: (text) => setState(() => language = text),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Language'),
                value: language,
                items: [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'es', child: Text('Español')),
                  DropdownMenuItem(value: 'fr', child: Text('Français')),
                  DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                ],
                onChanged: _onLanguageChanged,
              ),
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SelfTestableWidget(
                    id: 'reset_settings_button',
                    onTap: () {
                      setState(() {
                        darkMode = false;
                        soundEnabled = true;
                        vibration = true;
                        language = 'en';
                        theme = 'light';
                        volume = 0.7;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Settings reset!')),
                      );
                    },
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          darkMode = false;
                          soundEnabled = true;
                          vibration = true;
                          language = 'en';
                          theme = 'light';
                          volume = 0.7;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Settings reset!')),
                        );
                      },
                      child: Text('Reset to Defaults'),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: SelfTestableWidget(
                    id: 'save_settings_button',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Settings saved!')),
                      );
                    },
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Settings saved!')),
                        );
                      },
                      child: Text('Save Settings'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ListPage extends StatefulWidget {
  @override
  _ListPageState createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final int itemCount = 100;
  final Set<int> selectedItems = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      if (selectedItems.contains(index)) {
        selectedItems.remove(index);
      } else {
        selectedItems.add(index);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Item ${index + 1} ${selectedItems.contains(index) ? 'selected' : 'deselected'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scrollable List (${selectedItems.length} selected)'),
        leading: SelfTestableWidget(
          id: 'back_from_list',
          onTap: () => Navigator.pop(context),
          child: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          if (selectedItems.isNotEmpty)
            SelfTestableWidget(
              id: 'clear_selection_button',
              onTap: () {
                setState(() => selectedItems.clear());
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Selection cleared')),
                );
              },
              child: IconButton(
                icon: Icon(Icons.clear_all),
                onPressed: () {
                  setState(() => selectedItems.clear());
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selection cleared')),
                  );
                },
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: List.generate(itemCount, (index) {
            final isSelected = selectedItems.contains(index);
            return SelfTestableWidget(
              id: 'list_item_$index',
              onTap: () => _onItemTapped(index),
              child: ListTile(
                title: Text('Item ${index + 1}'),
                subtitle: Text('This is a scrollable list item'),
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? Colors.green : Colors.grey,
                ),
                trailing: Text('${index + 1}'),
                tileColor: isSelected ? Colors.blue.withOpacity(0.1) : null,
                onTap: () => _onItemTapped(index),
              ),
            );
          }),
        ),
      ),
      floatingActionButton: SelfTestableWidget(
        id: 'scroll_to_top_button',
        onTap: () {
          // Scroll to top
          _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        },
        child: FloatingActionButton(
          onPressed: () {
            // Scroll to top
            _scrollController.animateTo(
              0,
              duration: Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          },
          child: Icon(Icons.arrow_upward),
          tooltip: 'Scroll to top',
        ),
      ),
    );
  }
}
