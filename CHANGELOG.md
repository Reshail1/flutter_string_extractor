# [2.1.0] - 2026-11-03

- Optional AI discovery and translation with user-owned OpenAI, Claude, or Gemini
  keys, configurable models, and source/target locale JSON catalogs.
- Project-wide unmarked-string discovery, local-only preview, explicit AI
  privacy/cost/accuracy consent, batched calls, and a configurable request limit.
- Preserve existing translations, validate model replies and placeholders, reject
  unsafe destinations, and finish all API work before writing catalogs.
- Filter common credential patterns, avoid logging provider error bodies, and
  enforce HTTPS endpoints, timeouts, response limits, and redirect refusal.
- Fix source-catalog protection for case aliases on case-insensitive filesystems.
- Normalize the tracked README filename and restrict the published archive to
  runtime code, user documentation, and examples; tests and CI stay on GitHub.

# [2.0.0] - 2026-10-01

## Added

- GetX argument/plural variants, Easy Localization widget/context/plural calls,
  Flutter Translate, FlutterI18n, i18n_extension, and static Intl.message support.
- ARB message import for gen-l10n, Flutter Intl, and ICU catalog messages.
- Unmarked-string discovery, preview, exclusions, generated-file opt-in, and
  configurable translation function/getter names.
- Library scan results and location diagnostics for unresolved expressions.
- Extraction, CLI, catalog preservation, and file-safety regression tests.
- Expanded API/Unicode/CLI edge cases and repeatability stress tests.
- CI across Linux, macOS, and Windows on minimum and stable Dart SDKs.
- Version-tag publishing with GitHub OIDC through the official Dart workflow.
- Published installation examples, localization FAQ, and a factual llms.txt index.

## Changed

- Use Dart's analyzer parser to decode static literals and ignore comments.
- Require Dart 3.9+ and resolve modern compatible dependencies.
- Upgrade analyzer to 12.1.0 and refresh dependency constraints and lockfile.
- Preserve existing translations, stale keys, and nested catalog structures by
  default; explicit --replace resets the catalog.
- Send diagnostics and summaries to stderr; dry-run stdout is JSON.

## Fixed

- Correct quote/escape/multiline/adjacent literal and whitespace handling.
- Reject missing source, malformed catalogs, conflicting message IDs, source
  destinations, symlinks, and non-file output before writing.
- Stage writes beside the output before replacement; preserve POSIX permissions
  and use owner-only access for newly created catalogs on macOS/Linux.

## 1.1.2

* Updated README with clearer installation and usage instructions
* Improved documentation formatting

## 1.1.1

* Applied dart format to improve code formatting
* Enhanced code style consistency

## 1.1.0

* Added comprehensive API documentation
* Added example directory with sample code
* Added detailed usage examples in README
* Enhanced CLI error messages and feedback
* Fixed SDK constraint format
* Improved file path handling

## 1.0.1

* Improved documentation
* Added example directory with usage samples
* Fixed SDK constraint format
* Enhanced error handling in CLI

## 1.0.0

* First stable release
* Command line interface with src-dir and output-file options
* Global activation support via dart pub
* Support for both .tr and tr() syntax
* Clean JSON output format
* Improved error handling and user feedback

## 0.1.1

* Added support for tr() function
* Updated Readme.md file to reflect the changes
* Added support for dart pub global activate flutter_string_extractor

## 0.1.0

* Initial release of the "flutter_string_extractor" package
* Added feature to extract strings followed by ".tr" in Dart files
* Added feature to save these strings into a JSON file
* CLI support for running the package as a script
* Added documentation and MIT license
