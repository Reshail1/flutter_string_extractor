# Flutter String Extractor

A command-line tool for extracting translatable strings from Flutter projects. It finds strings marked with `.tr` or `tr()` in your Dart files and generates a JSON file.

## Features

- Extracts strings marked with `.tr` (e.g., `"Hello".tr`)
- Extracts strings in `tr()` function calls (e.g., `tr("Hello")`)
- Supports both single and double quotes
- Generates a clean JSON output file

## Installation

You can install the tool globally using:

```bash
dart pub global activate --source path .
```

## Usage

After global activation, you can run the tool anywhere using:

```bash
flutter_string_extractor -s lib -o strings.json
```

Or use it directly with dart run:

```bash
dart run bin/main.dart -s lib -o strings.json
```

## Running the Tool

### Direct Usage

1. Clone the repository
2. Navigate to the project directory
3. Run using one of these commands:

```bash
# Using dart run
dart run bin/main.dart -s lib -o strings.json

# With full options
dart run bin/main.dart --src-dir=lib --output-file=strings.json

# Get help
dart run bin/main.dart --help
```

### Options

- `-s, --src-dir`: Source directory to scan (default: "lib")
- `-o, --output-file`: Output JSON file path (default: "strings.json")
- `-h, --help`: Show usage information

### Example Output

The tool will generate a JSON file like this:

```json
{
  "Hello": "Hello",
  "Welcome back": "Welcome back",
  "Settings": "Settings"
}
```

## Using as a Library

You can also use this as a library in your Dart code:

```dart
import 'package:flutter_string_extractor/flutter_string_extractor.dart';

void main() {
  FlutterStringExtractor.extractStrings('lib', 'strings.json');
}
```

## License

MIT License
