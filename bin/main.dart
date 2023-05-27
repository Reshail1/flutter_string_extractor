import 'package:flutter_string_extractor/flutter_string_extractor.dart';
import 'package:args/args.dart';

void main(List<String> arguments) {
  final argParser = ArgParser()
    ..addOption('dir', abbr: 'd', defaultsTo: './')
    ..addOption('output', abbr: 'o', defaultsTo: 'strings.json');
  
  final argResults = argParser.parse(arguments);

  final directory = argResults['dir'];
  final outputFile = argResults['output'];

  FlutterStringExtractor.extractStrings(directory, outputFile);
}
