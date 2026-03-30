import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayu/shared/services/file_picker_service.dart';
import 'package:vayu/core/providers/auth_providers.dart';
import 'package:vayu/core/providers/video_providers.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/ads/data/services/ad_service.dart';
import 'package:vayu/features/video/core/data/services/video_service.dart';

class MockAuthService extends Mock implements AuthService {}
class MockVideoService extends Mock implements VideoService {}
class MockFilePickerService extends Mock implements FilePickerService {}
class MockAdService extends Mock implements AdService {}

class TestAppWrapper extends StatelessWidget {
  final Widget child;
  final MockAuthService mockAuthService;
  final MockVideoService mockVideoService;
  final MockFilePickerService mockFilePickerService;
  final MockAdService mockAdService;

  const TestAppWrapper({
    super.key,
    required this.child,
    required this.mockAuthService,
    required this.mockVideoService,
    required this.mockFilePickerService,
    required this.mockAdService,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
        videoServiceProvider.overrideWithValue(mockVideoService),
        filePickerServiceProvider.overrideWithValue(mockFilePickerService),
        adServiceProvider.overrideWithValue(mockAdService),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, _) => MaterialApp(
          home: child,
        ),
      ),
    );
  }
}
