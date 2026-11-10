// The Sidekick API on AWS (API Gateway + Lambda). Every request is signed (SigV4) with the
// caller's identity-pool credentials; API Gateway checks the signature and tells the backend who
// is calling and whether they're a guest.
import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';
import 'identity.dart';

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

class ApiError implements Exception {
  ApiError(this.message, {this.status = 0, this.data = const {}});
  final String message;
  final int status;
  final Map<String, dynamic> data;

  bool get needsLogin => data['needsLogin'] == true;
  bool get needsProfile => data['needsProfile'] == true;

  @override
  String toString() => message;
}

/// Gives the API valid credentials (refreshing them if needed), and in dev mode a fake identity.
abstract class Credentials {
  Future<AWSCredentials> credentials();
  String get devIdentity;
  bool get devGuest;
}

class Api {
  Api(this.auth);
  final Credentials auth;
  final _client = http.Client();

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    final payload = body == null ? '' : jsonEncode(body);
    late http.Response res;
    try {
      if (Config.useDevApi) {
        final uri = Uri.parse('${Config.devApi}$path');
        res = await _plain(method, uri, {
          'content-type': 'application/json',
          'x-dev-identity': auth.devIdentity,
          'x-dev-guest': auth.devGuest ? '1' : '0',
        }, payload);
      } else {
        final uri = Uri.parse('${Config.apiUrl}$path');
        final creds = await auth.credentials();
        final signer = AWSSigV4Signer(credentialsProvider: AWSCredentialsProvider(creds));
        final request = AWSHttpRequest(
          method: AWSHttpMethod.fromString(method),
          uri: uri,
          headers: {AWSHeaders.host: uri.host, AWSHeaders.contentType: 'application/json'},
          body: utf8.encode(payload),
        );
        final signed = await signer.sign(
          request,
          credentialScope: AWSCredentialScope(region: Config.awsRegion, service: AWSService.apiGatewayManagementApi),
        );
        final headers = Map<String, String>.from(signed.headers)..remove(AWSHeaders.host);
        res = await _plain(method, uri, headers, payload);
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      // A sign-in that Google can't renew is not a connection problem: the person signs in again.
      if (e is IdentityError && e.code == 'NeedsGoogle') throw ApiError(e.message);
      throw ApiError("Couldn't reach Sidekick. Check your connection and try again.");
    }
    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw ApiError('${data['error'] ?? data['message'] ?? 'Something went wrong. Try again.'}',
        status: res.statusCode, data: data);
  }

  Future<http.Response> _plain(String method, Uri uri, Map<String, String> headers, String body) {
    final r = http.Request(method, uri)..headers.addAll(headers);
    if (body.isNotEmpty) r.body = body;
    return _client.send(r).then(http.Response.fromStream).timeout(const Duration(seconds: 45));
  }

  // ---------- Profile ----------

  /// Who I am, my profile, and the theme the admin set for people who haven't picked one.
  Future<({bool guest, Profile? profile, ThemeChoice defaultTheme})> me() async {
    final j = await _send('GET', '/me');
    final p = j['profile'];
    return (
      guest: j['guest'] == true,
      profile: p is Map ? Profile.fromMap(p.cast<String, dynamic>()) : null,
      defaultTheme: ThemeChoice.parse(j['defaultTheme'], fallback: ThemeChoice.light),
    );
  }

  Future<Profile> saveProfile(Profile p) async {
    final j = await _send('PUT', '/me', p.toMap());
    return Profile.fromMap((j['profile'] as Map).cast<String, dynamic>());
  }

  Future<void> deleteAccount() => _send('DELETE', '/me');

  // ---------- Admin (only works for accounts listed in ADMIN_IDENTITY_IDS) ----------

  /// Everyone, every event (newest first) and open reports.
  Future<Map<String, dynamic>> adminOverview() => _send('GET', '/admin/overview');

  Future<Map<String, dynamic>> adminEvent(String id) => _send('GET', '/admin/events/${Uri.encodeComponent(id)}');

  /// kind is events, users or reports.
  Future<void> adminDelete(String kind, String id) => _send('DELETE', '/admin/$kind/${Uri.encodeComponent(id)}');

  /// The theme for everyone who hasn't picked their own, on the web and the phone.
  Future<void> adminSetDefaultTheme(ThemeChoice theme) =>
      _send('PUT', '/admin/settings', {'defaultTheme': theme.name});

  // ---------- Sidekick status ----------

  /// Which model the sidekick runs on, and how its last real call went.
  Future<Map<String, dynamic>> status() => _send('GET', '/status');

  /// Asks the model a tiny question right now: {ok, model, ms, reply, error}.
  Future<Map<String, dynamic>> checkSidekick() => _send('POST', '/status/check');

  // ---------- Events ----------

  Future<({List<MyEvent> mine, List<EventDoc> open})> events() async {
    final j = await _send('GET', '/events');
    return (
      mine: ((j['mine'] as List?) ?? []).map((e) => MyEvent.fromMap((e as Map).cast<String, dynamic>())).toList(),
      open: ((j['open'] as List?) ?? []).map((e) => EventDoc.fromMap((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  Future<String> createEvent(Map<String, dynamic> event) async => '${(await _send('POST', '/events', event))['id']}';

  Future<String> checkIn(Map<String, dynamic> body) async => '${(await _send('POST', '/checkin', body))['id']}';

  Future<Room> room(String id) async => Room.fromMap(await _send('GET', '/events/${Uri.encodeComponent(id)}'));

  Future<void> join(String id) => _send('POST', '/events/${Uri.encodeComponent(id)}/join', {});

  Future<void> leave(String id) => _send('POST', '/events/${Uri.encodeComponent(id)}/leave', {});

  Future<void> setVisible(String id, bool visible) =>
      _send('POST', '/events/${Uri.encodeComponent(id)}/visible', {'visible': visible});

  Future<Scout> scout(String id) async => Scout.fromJson(await _send('POST', '/events/${Uri.encodeComponent(id)}/scout', {}));

  /// Returns true if it's a match.
  Future<bool> swipe(String id, String to, bool like) async =>
      (await _send('POST', '/events/${Uri.encodeComponent(id)}/swipe', {'to': to, 'like': like}))['match'] == true;

  Future<MatchDetails> match(String id, String other) async => MatchDetails.fromMap(
      await _send('GET', '/events/${Uri.encodeComponent(id)}/matches/${Uri.encodeComponent(other)}'));

  Future<void> block(String uid) => _send('POST', '/block', {'uid': uid});

  Future<void> report(String uid, String eventId, String reason) =>
      _send('POST', '/report', {'uid': uid, 'eventId': eventId, 'reason': reason});

  // ---------- Alerts and messages ----------

  /// What's new with my matches, newest first, and how many of it I haven't seen yet.
  Future<NoteList> alerts() async => NoteList.fromMap(await _send('GET', '/alerts'));

  /// Marks every alert as seen.
  Future<void> readAlerts() => _send('POST', '/alerts/read', {});

  /// My conversations, newest first, and how many have messages I haven't read.
  Future<NoteList> chats() async => NoteList.fromMap(await _send('GET', '/chats'));

  /// Everyone I've connected with, across events, with their contact details.
  Future<ConnectionList> connections() async => ConnectionList.fromMap(await _send('GET', '/connections'));

  /// One conversation with a match. Opening it marks it read.
  Future<ChatThread> chat(String eventId, String uid) async => ChatThread.fromMap(
      await _send('GET', '/chats/${Uri.encodeComponent(eventId)}/${Uri.encodeComponent(uid)}'));

  /// Sends a message and returns it as it was saved.
  Future<ChatMessage> send(String eventId, String uid, String text) async {
    final j = await _send(
        'POST', '/chats/${Uri.encodeComponent(eventId)}/${Uri.encodeComponent(uid)}/messages', {'text': text});
    return ChatMessage.fromMap(_map(j['message']));
  }

  // ---------- Photos ----------

  /// Uploads a JPEG, PNG or WebP photo and returns its address.
  Future<String> uploadPhoto(List<int> bytes, String type) async =>
      '${(await _send('POST', '/me/photo', {'image': base64Encode(bytes), 'type': type}))['photoURL']}';

  // ---------- Places and imports ----------

  Future<ImportedEvent> importEvent(String url) async =>
      ImportedEvent.fromJson(await _send('POST', '/import-event', {'url': url}));

  Future<List<PlaceDetails>> placeSuggestions(String input) async {
    try {
      return _placeList((await _send('POST', '/places', {'input': input}))['suggestions']);
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceDetails>> nearby(double lat, double lng) async {
    try {
      return _placeList((await _send('POST', '/places', {'lat': lat, 'lng': lng}))['places']);
    } catch (_) {
      return const [];
    }
  }

  static List<PlaceDetails> _placeList(Object? v) =>
      ((v as List?) ?? const []).whereType<Map>().map((p) => PlaceDetails.fromJson(p.cast<String, dynamic>())).toList();
}
