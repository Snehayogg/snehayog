import 'dart:io';

void main(List<String> args) {
  final target = args.isNotEmpty ? args[0] : 'test';
  final outputFile = args.length > 1 ? args[1] : 'test/all_tests_suite.dart';
  final isIntegration = target.contains('integration_test');

  final testDir = Directory(target);
  if (!testDir.existsSync()) {
    print('Error: directory $target not found');
    exit(1);
  }

  final testFiles = <String>[];
  _findTestFiles(testDir, testFiles);

  // Exclude the suite file itself and helpers
  testFiles.removeWhere((path) => 
    path.endsWith(outputFile) || 
    path.endsWith('test_app_wrapper.dart') ||
    path.contains('robots/') // Exclude robots helper directory
  );

  if (testFiles.isEmpty) {
    print('No test files found in $target.');
    return;
  }

  final buffer = StringBuffer();
  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// ignore_for_file: unused_import');
  buffer.writeln();
  buffer.writeln("import 'package:flutter_test/flutter_test.dart';");
  if (isIntegration) {
    buffer.writeln("import 'package:integration_test/integration_test.dart';");
  }

  for (var i = 0; i < testFiles.length; i++) {
    final path = testFiles[i].replaceAll('\\', '/');
    // For imports, we need the path relative to the test file's location
    // Since we're putting the suite in the root of the target dir (usually)
    // we can use relative paths from the target dir.
    final relativePath = path.replaceFirst('$target/', '');
    buffer.writeln("import '$relativePath' as test_$i;");
  }

  buffer.writeln();
  buffer.writeln('void main() {');
  if (isIntegration) {
    buffer.writeln('  IntegrationTestWidgetsFlutterBinding.ensureInitialized();');
  }
  
  for (var i = 0; i < testFiles.length; i++) {
    final path = testFiles[i].replaceAll('\\', '/');
    buffer.writeln('  group(\'$path\', () => test_$i.main());');
  }
  buffer.writeln('}');

  final output = File(outputFile);
  output.writeAsStringSync(buffer.toString());
  print('✅ Generated $outputFile with ${testFiles.length} tests.');
}

void _findTestFiles(Directory dir, List<String> testFiles) {
  for (final entity in dir.listSync()) {
    if (entity is Directory) {
      _findTestFiles(entity, testFiles);
    } else if (entity is File && entity.path.endsWith('_test.dart')) {
      testFiles.add(entity.path);
    }
  }
}
