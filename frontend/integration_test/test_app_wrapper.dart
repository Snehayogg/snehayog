import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/shared/services/file_picker_service.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/core/interfaces/i_user_service.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';
import 'package:vayug/core/interfaces/i_payment_setup_service.dart';
import 'package:vayug/core/providers/user_service_providers.dart';
import 'package:vayug/core/providers/notification_providers.dart';
import 'package:vayug/core/providers/notice_providers.dart';
import 'package:vayug/core/providers/payment_providers.dart';

class MockAuthService extends Mock implements AuthService {}
class MockVideoService extends Mock implements VideoService {}
class MockFilePickerService extends Mock implements FilePickerService {}
class MockAdService extends Mock implements AdService {}
class MockUserService extends Mock implements IUserService {}
class MockNotificationService extends Mock implements INotificationService {}
class MockNoticeService extends Mock implements INoticeService {}
class MockPaymentSetupService extends Mock implements IPaymentSetupService {}

class TestAppWrapper extends StatelessWidget {
  final Widget child;
  final MockAuthService mockAuthService;
  final MockVideoService mockVideoService;
  final MockFilePickerService mockFilePickerService;
  final MockAdService mockAdService;
  final MockUserService? mockUserService;
  final MockNotificationService? mockNotificationService;
  final MockNoticeService? mockNoticeService;
  final MockPaymentSetupService? mockPaymentSetupService;

  const TestAppWrapper({
    super.key,
    required this.child,
    required this.mockAuthService,
    required this.mockVideoService,
    required this.mockFilePickerService,
    required this.mockAdService,
    this.mockUserService,
    this.mockNotificationService,
    this.mockNoticeService,
    this.mockPaymentSetupService,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
        videoServiceProvider.overrideWithValue(mockVideoService),
        filePickerServiceProvider.overrideWithValue(mockFilePickerService),
        adServiceProvider.overrideWithValue(mockAdService),
        if (mockUserService != null)
          userServiceProvider.overrideWithValue(mockUserService!),
        if (mockNotificationService != null)
          notificationServiceProvider.overrideWithValue(mockNotificationService!),
        if (mockNoticeService != null)
          noticeServiceProvider.overrideWithValue(mockNoticeService!),
        if (mockPaymentSetupService != null)
          paymentSetupServiceProvider.overrideWithValue(mockPaymentSetupService!),
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
