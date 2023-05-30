# Flutter String Extractor

A Dart package for extracting strings marked for translation from your Flutter project. It searches through Dart files in a specified directory and its subdirectories, extracts strings marked with `.tr`, and outputs these strings to a JSON file.

## Installation

### CLI
To run using cli:

1- You can add this package to your project by adding the following line to your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_string_extractor: ^0.1.1
```

2- Then, run `flutter pub get` to fetch the package.
Alternatively, you can install it globally:

```bash
dart pub global activate flutter_string_extractor
```
## Usage

After you have added the package, you can use it in your project:

```bash 
dart run flutter_string_extractor:extract --src-dir=lib --output-file=locale.json
```

Or if you installed it globally:

```bash
flutter_string_extractor ./lib output.json
```
---
## Another Approach is to use it as a script:



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
