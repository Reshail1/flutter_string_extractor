# Flutter String Extractor

A command-line tool for extracting translatable strings from Flutter projects. It finds strings marked with `.tr` or `tr()` in your Dart files and generates a JSON file.

## Features

- Extracts strings marked with `.tr` (e.g., `"Hello".tr`)
- Extracts strings in `tr()` function calls (e.g., `tr("Hello")`)
- Supports both single and double quotes
- Generates a clean JSON output file

## Installation

```bash
# Install globally using pub
dart pub global activate flutter_string_extractor
```

Make sure your PATH includes the pub cache bin directory:
```bash
# Add this to your ~/.bashrc, ~/.zshrc, or similar
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

## Usage

After installation, you can run anywhere using:

```bash
flutter_string_extractor -s lib -o strings.json
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
