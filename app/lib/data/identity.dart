// Who you are, to AWS: a Cognito identity-pool identity. A guest gets an unauthenticated
// identity. Signing in with Google links Google to that same identity, so everything the guest
// did carries over. Either way we get short-lived AWS credentials that can only call our API.
import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class IdentityError implements Exception {
  IdentityError(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class Identity {
  static const _kId = 'identityId';
  static const _kGoogle = 'signedInWithGoogle';
  static const _kCreds = 'awsCredentials';

  String? id;
  bool google = false;
  AWSCredentials? _creds;

  bool get exists => id != null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    id = p.getString(_kId);
    google = p.getBool(_kGoogle) ?? false;
    // Keep the short-lived credentials across reloads, so a page refresh doesn't need Google again.
    final saved = p.getString(_kCreds);
    if (id != null && saved != null) {
      try {
        final c = jsonDecode(saved) as Map<String, dynamic>;
        _creds = AWSCredentials(
          c['k'] as String,
          c['s'] as String,
          c['t'] as String,
          DateTime.fromMillisecondsSinceEpoch(c['e'] as int, isUtc: true),
        );
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove(_kId);
      await p.remove(_kGoogle);
      await p.remove(_kCreds);
    } else {
      await p.setString(_kId, id!);
      await p.setBool(_kGoogle, google);
      final c = _creds;
      if (c != null && c.expiration != null) {
        await p.setString(
          _kCreds,
          jsonEncode({
            'k': c.accessKeyId,
            's': c.secretAccessKey,
            't': c.sessionToken,
            'e': c.expiration!.millisecondsSinceEpoch,
          }),
        );
      }
    }
  }

  Future<void> clear() async {
    id = null;
    google = false;
    _creds = null;
    await _save();
  }

  static Map<String, String> _logins(String? googleIdToken) =>
      googleIdToken == null ? const {} : {'accounts.google.com': googleIdToken};

  static Future<Map<String, dynamic>> _call(String target, Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.https('cognito-identity.${Config.awsRegion}.amazonaws.com', '/'),
          headers: {'Content-Type': 'application/x-amz-json-1.1', 'X-Amz-Target': 'AWSCognitoIdentityService.$target'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final type = '${data['__type'] ?? ''}'.split('#').last;
      throw IdentityError('${data['message'] ?? 'Sign-in failed.'}', code: type);
    }
    return data;
  }

  /// A new guest identity.
  Future<void> startGuest() async {
    final r = await _call('GetId', {'IdentityPoolId': Config.identityPoolId});
    id = r['IdentityId'] as String;
    google = false;
    _creds = null;
    await _save();
  }

  /// Fetches credentials for the current identity. With a Google ID token, also links Google to
  /// it (a guest becoming a signed-in user keeps the same id). If Google is already linked to
  /// another identity (signed in before on another phone), we switch to that one.
  Future<void> refresh({String? googleIdToken}) async {
    if (googleIdToken == null && google) {
      throw IdentityError('Sign in again to continue.', code: 'NeedsGoogle');
    }
    final logins = _logins(googleIdToken);
    Map<String, dynamic> r;
    try {
      id ??=
          (await _call('GetId', {
                'IdentityPoolId': Config.identityPoolId,
                if (logins.isNotEmpty) 'Logins': logins,
              }))['IdentityId']
              as String;
      r = await _call('GetCredentialsForIdentity', {'IdentityId': id, if (logins.isNotEmpty) 'Logins': logins});
    } on IdentityError catch (e) {
      if (logins.isEmpty) {
        if (e.code == 'ResourceNotFoundException') await clear();
        rethrow;
      }
      // Google already belongs to another identity: use that one.
      id = (await _call('GetId', {'IdentityPoolId': Config.identityPoolId, 'Logins': logins}))['IdentityId'] as String;
      r = await _call('GetCredentialsForIdentity', {'IdentityId': id, 'Logins': logins});
    }
    id = r['IdentityId'] as String? ?? id;
    if (logins.isNotEmpty) google = true;
    final c = r['Credentials'] as Map<String, dynamic>;
    _creds = AWSCredentials(
      c['AccessKeyId'] as String,
      c['SecretKey'] as String,
      c['SessionToken'] as String,
      DateTime.fromMillisecondsSinceEpoch(((c['Expiration'] as num) * 1000).round(), isUtc: true),
    );
    await _save();
  }

  /// Valid credentials, or null if they've expired (refresh first).
  AWSCredentials? get credentials {
    final c = _creds;
    if (c == null) return null;
    final exp = c.expiration;
    if (exp != null && exp.isBefore(DateTime.now().toUtc().add(const Duration(minutes: 2)))) return null;
    return c;
  }
}
