import 'dart:io';

import 'package:flutter_string_extractor/flutter_string_extractor.dart';

// Run: dart run example/main.dart /path/to/flutter_app/lib
void main(List<String> arguments) {
  final source = arguments.isEmpty ? 'lib' : arguments.first;
  final result = FlutterStringExtractor.extractStrings(
    source,
    'translations.json',
    dryRun: true,
  );
  stdout.write(result.json);
  for (final warning in result.warnings) {
    stderr.writeln(warning);
  }
}
