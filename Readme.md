# Flutter String Extractor

A Dart package for extracting strings marked for translation from your Flutter project. It searches through Dart files in a specified directory and its subdirectories, extracts strings marked with `.tr`, and outputs these strings to a JSON file.

## Installation

Add the `flutter_string_extractor` package to your `pubspec.yaml` file:

```yaml
dependencies:
  flutter_string_extractor: <latest_version>
```
Then, run flutter pub get to fetch the package.


```dart
import 'package:flutter_string_extractor/flutter_string_extractor.dart';

void main() {
  String directory = 'lib'; // Directory to search for Dart files
  String outputFile = 'extracted_strings.json'; // File to output the extracted strings

  FlutterStringExtractor.extractStrings(directory, outputFile);
}
```

This code will search through all Dart files in the lib directory and its subdirectories, extract strings marked with .tr, and output these strings to extracted_strings.json in the following format:

```json
{
  "Hello": "Hello",
  "Goodbye": "Goodbye",
  ...
}
```

## Contributing
Contributions are always welcome! Please read our contributing guide to learn about our development process, how to propose bugfixes and improvements, and how to build and test your changes.

## License
This package is licensed under the MIT license.
