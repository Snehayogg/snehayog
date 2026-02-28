class FeatureFlags {
  // Toggle to enable/disable the Agent feature globally
  static const bool isAgentEnabled = false;

  /// Whether the video dubbing feature is enabled.
  /// Use --dart-define=ENABLE_DUBBING=false to disable at build time.
  static const bool isDubbingEnabled = bool.fromEnvironment(
    'ENABLE_DUBBING',
    defaultValue: true,
  );
}
