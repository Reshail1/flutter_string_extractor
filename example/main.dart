import 'package:flutter_string_extractor/flutter_string_extractor.dart';

void main() {
  // Example strings in our source code:
  // "Hello".tr
  // tr("Welcome")
  // 'Settings'.tr
  // tr('Goodbye')

  // Extract strings from the lib directory
  FlutterStringExtractor.extractStrings('lib', 'translations.json');
  
  // This will create a translations.json file with content like:
  // {
  //   "Hello": "Hello",
  //   "Welcome": "Welcome",
  //   "Settings": "Settings",
  //   "Goodbye": "Goodbye"
  // }
}
