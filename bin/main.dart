#!/usr/bin/env dart

import 'dart:io';

import 'package:flutter_string_extractor/ai_string_extractor.dart';
import 'package:flutter_string_extractor/flutter_string_extractor.dart';
import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  final argParser = ArgParser()
    ..addOption(
      'src-dir',
      abbr: 's',
      defaultsTo: 'lib',
      help: 'Source directory to scan for Dart files',
    )
    ..addOption(
      'output-file',
      abbr: 'o',
      defaultsTo: 'strings.json',
      help: 'Output JSON file path',
    )
    ..addFlag(
      'all-strings',
      negatable: false,
      help: 'Discover unmarked static literals too (review non-UI strings)',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Print the merged JSON without changing files',
    )
    ..addFlag(
      'replace',
      negatable: false,
      help: 'Explicitly discard existing translations and stale keys',
    )
    ..addFlag(
      'include-generated',
      negatable: false,
      help: 'Include generated Dart files (cache/build directories stay excluded)',
    )
    ..addMultiOption(
      'exclude',
      splitCommas: false,
      help:
          'Repeatable glob relative to the source directory, e.g. "screens/**"',
    )
    ..addMultiOption(
      'function',
      splitCommas: false,
      help: 'Additional translator method name whose first argument is the key',
    )
    ..addMultiOption(
      'getter',
      splitCommas: false,
      help: 'Additional String translation getter or extension method name',
    )
    ..addOption(
      'from-arb',
      help: 'Import messages from an ARB catalog (gen-l10n / Flutter Intl)',
    )
    ..addOption(
      'ai-provider',
      allowed: ['openai', 'claude', 'gemini', 'local'],
      help: 'Opt in to cloud or local AI discovery and translation',
    )
    ..addMultiOption(
      'languages',
      help: 'AI target locales, comma-separated or repeated (e.g. de,fr,ar)',
    )
    ..addOption(
      'source-language',
      defaultsTo: 'en',
      help: 'Source locale for AI translation',
    )
    ..addOption(
      'model',
      help: 'Provider model ID; defaults to a low-cost model',
    )
    ..addOption(
      'ai-base-url',
      help: 'Local OpenAI-compatible base URL (default http://127.0.0.1:11434/v1)',
    )
    ..addOption(
      'ai-timeout',
      help: 'Request timeout: 1–3600 seconds (cloud 60; local 180)',
    )
    ..addOption(
      'context',
      defaultsTo: '',
      help: 'App domain, audience, tone and terminology (max 2,000 characters; no secrets)',
    )
    ..addOption(
      'output-dir',
      defaultsTo: 'assets/translations',
      help: 'AI catalog directory: <locale>.json',
    )
    ..addOption(
      'max-ai-requests',
      defaultsTo: '100',
      help: 'Hard limit on provider calls per AI run',
    )
    ..addFlag(
      'accept-ai',
      negatable: false,
      help:
          'Accept AI mistakes, provider data sharing, and possible API charges',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information',
    );

  try {
    final argResults = argParser.parse(arguments);

    if (argResults['help'] as bool) {
      print('Usage: flutter_string_extractor [options]\n');
      print(argParser.usage);
      return;
    }

    if (argResults.rest.isNotEmpty) {
      throw FormatException(
        'Unexpected positional arguments: ${argResults.rest.join(' ')}',
      );
    }
    final directory = argResults['src-dir'] as String;
    final outputFile = argResults['output-file'] as String;
    final providerName = argResults['ai-provider'] as String?;
    if (providerName == null &&
        [
          'languages',
          'source-language',
          'model',
          'ai-base-url',
          'ai-timeout',
          'context',
          'output-dir',
          'max-ai-requests',
          'accept-ai',
        ].any(argResults.wasParsed)) {
      throw FormatException(
        'AI options require --ai-provider openai, claude, gemini, or local.',
      );
    }
    if (providerName != null) {
      if (argResults.wasParsed('ai-base-url') && providerName != 'local') {
        throw FormatException('--ai-base-url requires --ai-provider local.');
      }
      final timeoutArgument = argResults['ai-timeout'] as String?;
      final timeoutSeconds = timeoutArgument == null
          ? null
          : int.tryParse(timeoutArgument);
      if (timeoutArgument != null &&
          (timeoutSeconds == null ||
              timeoutSeconds < 1 ||
              timeoutSeconds > 3600)) {
        throw FormatException(
          '--ai-timeout must be an integer from 1 to 3600 seconds.',
        );
      }
      if (argResults.wasParsed('output-file') ||
          argResults['replace'] as bool) {
        throw FormatException(
          'AI mode preserves translations and uses --output-dir; omit --replace and --output-file.',
        );
      }
      final maxRequests = int.tryParse(argResults['max-ai-requests'] as String);
      if (maxRequests == null || maxRequests < 1) {
        throw FormatException('--max-ai-requests must be a positive integer.');
      }
      final provider = AiProvider.values.byName(providerName);
      stderr.writeln(
        'AI disclaimer: ${provider == AiProvider.local ? AiStringExtractor.localDisclaimer : AiStringExtractor.disclaimer}',
      );
      stderr.writeln(
        'Provider: ${provider.name}; model: ${argResults['model'] ?? provider.defaultModel}.',
      );
      try {
        final result = await AiStringExtractor.extract(
          argResults.wasParsed('src-dir') ? directory : '.',
          argResults['output-dir'] as String,
          provider: provider,
          languages: argResults['languages'] as List<String>,
          sourceLanguage: argResults['source-language'] as String,
          model: argResults['model'] as String?,
          baseUrl: argResults['ai-base-url'] as String?,
          timeout: timeoutSeconds == null
              ? null
              : Duration(seconds: timeoutSeconds),
          projectContext: argResults['context'] as String,
          dryRun: argResults['dry-run'] as bool,
          acceptAi: argResults['accept-ai'] as bool,
          maxRequests: maxRequests,
          includeGenerated: argResults['include-generated'] as bool,
          exclude: argResults['exclude'] as List<String>,
          functions: argResults['function'] as List<String>,
          getters: argResults['getter'] as List<String>,
          sourceArb: argResults['from-arb'] as String?,
        );
        for (final warning in result.warnings) {
          stderr.writeln('Warning: $warning');
        }
        if (argResults['dry-run'] as bool) {
          stdout.write(result.previewJson);
          stderr.writeln(
            'Local candidate preview only; AI selection and translation have not run; no API calls or files changed.',
          );
        } else {
          stderr.writeln(
            'Scanned ${result.filesScanned} Dart files; selected ${result.messages.length} messages; added ${result.translatedCount} translations using ${result.requestCount} AI requests.',
          );
          for (final file in result.outputFiles) {
            stderr.writeln('Catalog: $file');
          }
          stderr.writeln(
            'Review the translations and connect your widgets to your localization package. Dart source files were not rewritten.',
          );
        }
      } on ArgumentError catch (error) {
        stderr.writeln('Error: ${error.message}');
        exitCode = 1;
      } on Exception catch (error) {
        stderr.writeln('Error: $error');
        exitCode = 1;
      }
      return;
    }
    ExtractionResult result;
    try {
      result = FlutterStringExtractor.extractStrings(
        directory,
        outputFile,
        allStrings: argResults['all-strings'] as bool,
        dryRun: argResults['dry-run'] as bool,
        replace: argResults['replace'] as bool,
        includeGenerated: argResults['include-generated'] as bool,
        exclude: argResults['exclude'] as List<String>,
        functions: argResults['function'] as List<String>,
        getters: argResults['getter'] as List<String>,
        sourceArb: argResults['from-arb'] as String?,
      );
    } on Exception catch (error) {
      stderr.writeln('Error: $error');
      exitCode = 1;
      return;
    } on ArgumentError catch (error) {
      stderr.writeln('Error: ${error.message}');
      exitCode = 1;
      return;
    }
    for (final warning in result.warnings) {
      stderr.writeln('Warning: $warning');
    }
    if (argResults['dry-run'] as bool) {
      stdout.write(result.json);
    }
    stderr.writeln(
      'Scanned ${result.filesScanned} Dart files; found '
      '${result.extractedCount} unique messages; added ${result.addedCount} entries.',
    );
    stderr.writeln(
      (argResults['dry-run'] as bool)
          ? 'Preview only; no files changed.'
          : 'Saved translations to: $outputFile',
    );
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}\n\n${argParser.usage}');
    exitCode = 64;
  }
}
