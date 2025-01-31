import 'dart:convert';
import 'package:glob/glob.dart';
import 'dart:io';
import 'package:glob/list_local_fs.dart';

/// A utility class for extracting translatable strings from Flutter/Dart source files.
/// 
/// This class provides functionality to scan Dart files for strings marked with
/// either `.tr` extension method or wrapped in `tr()` function calls, which are
/// commonly used for internationalization in Flutter applications.
class FlutterStringExtractor {
  /// Extracts translatable strings from Dart files in the specified directory.
  /// 
  /// Parameters:
  /// - [directory]: The path to the directory containing Dart files to scan.
  /// - [outputFile]: The path where the JSON file containing extracted strings will be saved.
  /// 
  /// Example:
  /// ```dart
  /// FlutterStringExtractor.extractStrings('lib', 'translations.json');
  /// ```
  /// 
  /// The output JSON file will contain key-value pairs where both key and value
  /// are the same string, ready for translation:
  /// ```json
  /// {
  ///   "Hello": "Hello",
  ///   "Welcome": "Welcome"
  /// }
  /// ```
  static void extractStrings(String directory, String outputFile) {
    final glob = Glob('$directory/**.dart');
    final filePattern = RegExp(
      r'''(?:["']([^"']*)["']\.tr)|(?:tr\(["']([^"']*)["']\))''',
      multiLine: true,
    );
    final extractedStrings = <String>{};

    for (var entity in glob.listSync()) {
      if (entity is File) {
        final content = File(entity.path).readAsStringSync();
        final matches = filePattern.allMatches(content);
        for (var match in matches) {
          // Get string from either .tr or tr() syntax
          final extractedString = match.group(1) ?? match.group(2);
          if (extractedString != null && extractedString.isNotEmpty) {
            extractedStrings.add(extractedString);
          }
        }
      }
    }

    final Map<String, String> outputMap = {
      for (var str in extractedStrings) str: str
    };
    
    final jsonFile = File(outputFile);
    jsonFile.writeAsStringSync(
      JsonEncoder.withIndent('  ').convert(outputMap),
      flush: true,
    );
  }
}
