import 'dart:io';

import 'package:aws_common/aws_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sidekick/data/identity.dart';
import 'package:sidekick/data/session.dart';
import 'package:sidekick/models.dart';

/// A person signed in with Google, whose saved sign-in can't be renewed the way [failure] says.
class RenewalSession extends Session {
  RenewalSession(this.failure);
  final Object failure;

  @override
  Future<AWSCredentials> credentials() async => throw failure;
}

void main() {
  test('a Google sign-in that Google can no longer renew asks the person to sign in again', () async {
    SharedPreferences.setMockInitialValues({'identityId': 'eu-west-1:1111', 'signedInWithGoogle': true});
    final s = RenewalSession(IdentityError('Sign in again to continue.', code: 'NeedsGoogle'));

    await s.start();

    // Not the offline page: the saved sign-in is dropped, so the welcome screen offers Google again.
    expect(s.started, isFalse);
    expect(s.startError, isNull);
  });

  test('a dropped connection still shows the offline page, and keeps the sign-in', () async {
    SharedPreferences.setMockInitialValues({'identityId': 'eu-west-1:1111', 'signedInWithGoogle': true});
    final s = RenewalSession(const SocketException('no network'));

    await s.start();

    expect(s.started, isTrue);
    expect(s.startError, "Couldn't reach Sidekick. Check your connection and try again.");
  });

  test('before the server says otherwise, the look is light', () {
    final s = Session();

    expect(s.defaultTheme, ThemeChoice.light);
    expect(s.theme, ThemeChoice.light);
  });
}
