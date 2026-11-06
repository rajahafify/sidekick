import 'dart:async';

import 'package:aws_common/aws_common.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models.dart';
import 'api.dart';
import 'identity.dart';

/// Who's using the app: nobody yet, a guest, or someone signed in with Google. Plus their profile.
class Session extends ChangeNotifier implements Credentials {
  Session() {
    api = Api(this);
  }

  late final Api api;
  final _identity = Identity();

  /// False until we know who's here.
  bool ready = false;
  Profile? profile;

  /// Name and photo from Google, to fill in the profile form the first time.
  String googleName = '';
  String googlePhoto = '';

  /// Set when we couldn't reach the server at start-up.
  String? startError;

  bool get started => Config.useDevApi ? _devId != null : _identity.exists;
  bool get guest => Config.useDevApi ? _devGuest : !_identity.google;
  bool get needsProfile => started && (profile == null || !profile!.onboarded);
  String get uid => Config.useDevApi ? (_devId ?? '') : (_identity.id ?? '');

  Future<void> start() async {
    if (Config.useDevApi) {
      final p = await SharedPreferences.getInstance();
      _devId = p.getString('devIdentity');
      _devGuest = p.getBool('devGuest') ?? true;
    } else {
      await _identity.load();
    }
    if (started) {
      try {
        // Saved credentials cover a reload; when they've expired, credentials() renews them
        // (for Google users, silently through Google if it can).
        await reloadProfile();
      } on IdentityError catch (e) {
        if (e.code == 'NeedsGoogle' || e.code == 'ResourceNotFoundException' || e.code == 'NotAuthorizedException') {
          await _identity.clear();
        } else {
          startError = e.message;
        }
      } catch (e) {
        startError = '$e';
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> reloadProfile() async {
    final r = await api.me();
    profile = r.profile;
    notifyListeners();
  }

  Future<void> retry() async {
    startError = null;
    ready = false;
    notifyListeners();
    await start();
  }

  // ---------- Guest ----------

  Future<void> continueAsGuest() async {
    if (Config.useDevApi) {
      await _setDev('dev-guest-${DateTime.now().millisecondsSinceEpoch}', true);
    } else {
      await _identity.startGuest();
      await _identity.refresh();
    }
    await reloadProfile();
  }

  // ---------- Google ----------

  static bool _googleReady = false;
  final _webSignIns = StreamController<Object?>.broadcast();

  /// On the web, Google's own button signs people in, and the result arrives here: null when
  /// they're signed in and linked, or the error.
  Stream<Object?> get webSignIns => _webSignIns.stream;

  /// Sets up Google sign-in once. On the web this must run before Google's button is shown.
  Future<void> prepareGoogle() async {
    if (_googleReady) return;
    final google = GoogleSignIn.instance;
    await google.initialize(
      serverClientId: Config.googleWebClientId.isEmpty || kIsWeb ? null : Config.googleWebClientId,
      clientId: kIsWeb
          ? Config.googleWebClientId
          : (Config.googleIosClientId.isEmpty ? null : Config.googleIosClientId),
    );
    if (kIsWeb) google.authenticationEvents.listen(_onWebEvent, onError: (Object e) => _webSignIns.add(e));
    _googleReady = true;
  }

  Future<void> _onWebEvent(GoogleSignInAuthenticationEvent e) async {
    if (e is! GoogleSignInAuthenticationEventSignIn) return;
    try {
      await _identity.refresh(googleIdToken: _tokenOf(e.user));
      await reloadProfile();
      _webSignIns.add(null);
    } catch (err) {
      _webSignIns.add(err);
    }
  }

  String _tokenOf(GoogleSignInAccount account) {
    googleName = account.displayName ?? '';
    googlePhoto = account.photoUrl ?? '';
    final token = account.authentication.idToken;
    if (token == null) throw IdentityError("Google didn't return a sign-in token. Try again.");
    return token;
  }

  Future<String> _googleIdToken({required bool interactive}) async {
    await prepareGoogle();
    final google = GoogleSignIn.instance;
    GoogleSignInAccount? account;
    if (!interactive) {
      if (kIsWeb) {
        // On the web, Google's silent sign-in answers through the events stream, not the future.
        final next = google.authenticationEvents
            .where((e) => e is GoogleSignInAuthenticationEventSignIn)
            .map<GoogleSignInAccount?>((e) => (e as GoogleSignInAuthenticationEventSignIn).user)
            .first
            .timeout(const Duration(seconds: 10), onTimeout: () => null)
            .catchError((Object _) => null);
        account = await google.attemptLightweightAuthentication() ?? await next;
      } else {
        account = await google.attemptLightweightAuthentication();
      }
    } else {
      account = await google.authenticate();
    }
    if (account == null) throw IdentityError('Sign in again to continue.', code: 'NeedsGoogle');
    return _tokenOf(account);
  }

  Future<void> _refreshGoogle({required bool interactive}) async {
    final token = await _googleIdToken(interactive: interactive);
    await _identity.refresh(googleIdToken: token);
  }

  /// Signs in with Google. A guest keeps everything: Google is linked to their identity.
  Future<void> signInWithGoogle() async {
    if (Config.useDevApi) {
      await _setDev(_devId ?? 'dev-user-${DateTime.now().millisecondsSinceEpoch}', false);
    } else {
      await _refreshGoogle(interactive: true);
    }
    await reloadProfile();
  }

  Future<void> signOut() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    if (Config.useDevApi) {
      final p = await SharedPreferences.getInstance();
      await p.remove('devIdentity');
      _devId = null;
    }
    await _identity.clear();
    profile = null;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    await signOut();
  }

  // ---------- Credentials for the API ----------

  @override
  Future<AWSCredentials> credentials() async {
    var c = _identity.credentials;
    if (c != null) return c;
    if (_identity.google) {
      await _refreshGoogle(interactive: false);
    } else {
      await _identity.refresh();
    }
    c = _identity.credentials;
    if (c == null) throw ApiError('Sign in again to continue.');
    return c;
  }

  // ---------- Dev server identities ----------

  String? _devId;
  bool _devGuest = true;

  Future<void> _setDev(String id, bool guest) async {
    _devId = id;
    _devGuest = guest;
    final p = await SharedPreferences.getInstance();
    await p.setString('devIdentity', id);
    await p.setBool('devGuest', guest);
  }

  @override
  String get devIdentity => _devId ?? '';
  @override
  bool get devGuest => _devGuest;
}
