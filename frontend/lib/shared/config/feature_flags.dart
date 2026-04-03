class FeatureFlags {

  /// Use --dart-define=ENABLE_DUBBING=false to disable at build time.
  static const bool isDubbingEnabled = bool.fromEnvironment(
    'ENABLE_DUBBING',
    defaultValue: true,
  );
}
