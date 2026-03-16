import 'dart:io';

const List<String> dubbingPackages = [
  'sherpa_onnx:',
  'ffmpeg_kit_flutter_new_https_gpl:',
  'whisper_flutter_new:',
  'google_mlkit_translation:',
];

void main(List<String> args) {
  if (args.isEmpty || (args[0] != 'enable' && args[0] != 'disable')) {
    print('Usage: dart tool/toggle_fast_profile.dart [enable|disable]');
    print('  enable:  Restores full dependencies and real files for dubbing.');
    print(
        '  disable: Comments out heavy dependencies and uses stubs (Fast Profile).');
    return;
  }

  final disable =
      args[0] == 'disable'; // disable = true means "Enable fast profile"
  print(disable
      ? "🚀 Enabling Fast Profile (Removing Heavy Dependencies)..."
      : "📦 Restoring Full Profile (Adding Heavy Dependencies)...");

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: run this script from the frontend directory.');
    exit(1);
  }

  // 1. Update pubspec.yaml
  var lines = pubspecFile.readAsLinesSync();
  bool pubspecModified = false;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final pkg in dubbingPackages) {
      if (line.contains(pkg)) {
        if (!disable) {
          // Enable: Remove comment
          if (line.trimLeft().startsWith('#')) {
            lines[i] = line.replaceFirst('#', '');
            pubspecModified = true;
          }
        } else {
          // Disable: Add comment
          if (!line.trimLeft().startsWith('#')) {
            final textIndex = line.indexOf(pkg);
            lines[i] =
                '${line.substring(0, textIndex)}#${line.substring(textIndex)}';
            pubspecModified = true;
          }
        }
      }
    }
  }

  if (pubspecModified) {
    pubspecFile.writeAsStringSync('${lines.join('\n')}\n');
    print('✅ Updated pubspec.yaml');
  } else {
    print('ℹ️ pubspec.yaml is already up to date.');
  }

  // 2. Toggle dart files
  _toggleDartFile('lib/shared/services/local_dubbing_service.dart', disable);
  _toggleDartFile(
      'lib/shared/services/local_ai_inference_service.dart', disable);

  print('✅ Done. Please run `flutter pub get` now to apply dependencies.');
}

void _toggleDartFile(String targetFile, bool disable) {
  final file = File(targetFile);
  final realFile = File('$targetFile.real');
  final stubFile = File(targetFile.replaceAll(".dart", "_stub.dart"));

  if (disable) {
    if (realFile.existsSync()) {
      print('ℹ️ $targetFile is already using stubs.');
      return;
    }
    if (!file.existsSync()) {
      print('⚠️ Cannot find $targetFile to replace.');
      return;
    }
    // Rename real to .real
    file.renameSync(realFile.path);
    // Copy stub to original name
    stubFile.copySync(file.path);
    print('✅ Replaced $targetFile with stub');
  } else {
    // Enable mode
    if (realFile.existsSync()) {
      // We are currently using stubs. Need to restore real implementation.
      if (file.existsSync()) {
        file.deleteSync(); // Delete the stub
      }
      realFile.renameSync(file.path); // Restore the real file
      print('✅ Restored $targetFile to real implementation');
    } else {
      print('ℹ️ $targetFile is already using real implementation.');
    }
  }
}
