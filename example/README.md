# Flutter String Extractor Example

This example demonstrates how to use the Flutter String Extractor to extract translatable strings from your Flutter project.

## Usage

```dart
import 'package:flutter_string_extractor/flutter_string_extractor.dart';

void main() {
  // Extract strings from the lib directory
  FlutterStringExtractor.extractStrings('lib', 'translations.json');
}
```

## Source Code Examples

In your Flutter project, mark strings for translation using either:

```dart
// Using .tr extension
Text("Hello".tr);
Text('Welcome back'.tr);

// Using tr() function
Text(tr("Settings"));
Text(tr('Logout'));
```

Running the extractor will generate a JSON file with all these strings:

```json
{
  "Hello": "Hello",
  "Welcome back": "Welcome back",
  "Settings": "Settings",
  "Logout": "Logout"
}
```
