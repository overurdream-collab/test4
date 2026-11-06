class AppConfig {
  const AppConfig._();

  static const String appName = 'QAT LINK';
  static const String apiBaseUrl = String.fromEnvironment(
    'QATLINK_API_URL',
    defaultValue: '',
  );
  static const bool allowDemoMode = bool.fromEnvironment(
    'QATLINK_ALLOW_DEMO',
    defaultValue: false,
  );

  static bool get hasRemoteApi => apiBaseUrl.trim().isNotEmpty;
  static bool get useDemoData => !hasRemoteApi;

  static Uri? get apiBaseUri {
    final raw = apiBaseUrl.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }
}
