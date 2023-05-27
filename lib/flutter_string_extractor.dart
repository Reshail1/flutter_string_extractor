import 'package:glob/glob.dart';
import 'dart:io';

class FlutterStringExtractor {
  static void extractStrings(String directory, String outputFile) {
    final glob = Glob(directory + '/**.dart');
    final filePattern = RegExp(r'"([^"]*)"\.tr|\'([^\']*)\'\.tr');
    final extractedStrings = <String>{};

    for (var entity in glob.listSync()) {
      if (entity is File) {
        final content = entity.readAsStringSync();
        final matches = filePattern.allMatches(content);
        for (var match in matches) {
          // Extract the string inside quotes
          final extractedString = match.group(1) ?? match.group(2);
          extractedStrings.add(extractedString!);
        }
      }
    }

    final jsonFile = File(outputFile);
    jsonFile.writeAsStringSync('{\n');
    for (var extractedString in extractedStrings) {
      jsonFile.writeAsStringSync('  "$extractedString": "$extractedString",\n', mode: FileMode.append);
    }
    jsonFile.writeAsStringSync('}\n', mode: FileMode.append);
  }
}
