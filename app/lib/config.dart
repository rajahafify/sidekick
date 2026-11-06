/// Build-time settings, passed with `--dart-define-from-file=env.json` (see app/env.example.json).
/// None of these are secrets: the identity pool id and API URL are public, and every request is
/// signed with short-lived credentials that can only call the Sidekick API.
class Config {
  /// From the CDK deploy outputs (Sidekick.Region, Sidekick.IdentityPoolId, Sidekick.ApiUrl).
  static const awsRegion = String.fromEnvironment('AWS_REGION', defaultValue: 'ap-southeast-1');
  static const identityPoolId = String.fromEnvironment('IDENTITY_POOL_ID');
  static const apiUrl = String.fromEnvironment('API_URL');

  /// The Google OAuth "Web application" client id. Android asks Google for an ID token issued to
  /// it, and the identity pool trusts it.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// The iOS OAuth client id, only for iOS builds.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Shareable event links.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://sidekick.artifisi.com');

  /// Talk to the local dev server (backend: `npm run dev`) instead of AWS, with fake identities.
  static const devApi = String.fromEnvironment('DEV_API');

  static bool get useDevApi => devApi.isNotEmpty;
  static bool get configured => useDevApi || (identityPoolId.isNotEmpty && apiUrl.isNotEmpty);

  static String eventLink(String id) => '$siteUrl/e/$id';
}
