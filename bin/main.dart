#!/usr/bin/env dart

import 'dart:io';
import 'package:flutter_string_extractor/flutter_string_extractor.dart';
import 'package:args/args.dart';

void main(List<String> arguments) {
  final argParser = ArgParser()
    ..addOption('src-dir',
        abbr: 's',
        defaultsTo: 'lib',
        help: 'Source directory to scan for Dart files')
    ..addOption('output-file',
        abbr: 'o', defaultsTo: 'strings.json', help: 'Output JSON file path')
    ..addFlag('help', abbr: 'h', help: 'Show usage information');

  try {
    final argResults = argParser.parse(arguments);

    if (argResults['help']) {
      print('Usage: flutter_string_extractor [options]\n');
      print(argParser.usage);
      exit(0);
    }

    final directory = argResults['src-dir'];
    final outputFile = argResults['output-file'];

    print('Scanning directory: $directory');
    FlutterStringExtractor.extractStrings(directory, outputFile);
    print('Extracted strings have been saved to: $outputFile');
  } catch (e) {
    print('Error: $e');
    print('\nUsage:');
    print(argParser.usage);
    exit(1);
  }
}
