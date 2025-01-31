import 'dart:convert';
import 'package:glob/glob.dart';
import 'dart:io';
import 'package:glob/list_local_fs.dart';

class FlutterStringExtractor {
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
