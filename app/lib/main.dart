import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'data/session.dart';
import 'screens/admin.dart';
import 'screens/check_in.dart';
import 'screens/event.dart';
import 'screens/home.dart';
import 'screens/match.dart';
import 'screens/new_event.dart';
import 'screens/place.dart';
import 'screens/profile.dart';
import 'screens/welcome.dart';
import 'theme.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths on the web (sidekick.artifisi.com/e/<id>), not #/ links.
  usePathUrlStrategy();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.paper,
  ));
  if (!Config.configured) {
    runApp(const _NotConfigured());
    return;
  }
  final session = Session();
  runApp(SidekickApp(session: session));
  await session.start();
}

class SidekickApp extends StatefulWidget {
  const SidekickApp({super.key, required this.session});
  final Session session;

  @override
  State<SidekickApp> createState() => _SidekickAppState();
}

class _SidekickAppState extends State<SidekickApp> {
  late final GoRouter router = _router(widget.session);

  @override
  Widget build(BuildContext context) => SessionScope(
        session: widget.session,
        child: MaterialApp.router(
          title: 'Sidekick',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          darkTheme: buildTheme(),
          themeMode: ThemeMode.dark,
          routerConfig: router,
        ),
      );
}

/// Gives every screen the session (who's signed in, their profile, and the data layer).
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}

GoRouter _router(Session session) => GoRouter(
      refreshListenable: session,
      initialLocation: '/',
      redirect: (context, state) {
        final loc = state.matchedLocation;
        if (!session.ready) return loc == '/loading' ? null : '/loading?next=${Uri.encodeComponent(state.uri.toString())}';
        // The admin site shows only the admin screen, which handles signing in itself.
        if (Config.adminHost) return loc == '/admin' ? null : '/admin';
        final going = loc == '/loading' ? state.uri.queryParameters['next'] : loc;
        if (going == '/admin') {
          if (!session.started) return loc == '/welcome' ? null : '/welcome?next=/admin';
          return loc == '/admin' ? null : '/admin';
        }
        final next = state.uri.queryParameters['next'];
        if (session.startError != null) return loc == '/offline' ? null : '/offline';
        if (loc == '/offline') return next ?? '/';
        if (!session.started) {
          if (loc == '/welcome') return null;
          final target = loc == '/loading' ? next : state.uri.toString();
          return target == null || target == '/' ? '/welcome' : '/welcome?next=${Uri.encodeComponent(target)}';
        }
        if (session.needsProfile && loc != '/profile') {
          final target = (loc == '/loading' || loc == '/welcome') ? next : state.uri.toString();
          return target == null || target == '/' ? '/profile' : '/profile?next=${Uri.encodeComponent(target)}';
        }
        if (loc == '/loading' || loc == '/welcome') return next ?? '/';
        return null;
      },
      routes: [
        GoRoute(path: '/loading', builder: (_, _) => const Scaffold(body: Loading())),
        GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/offline', builder: (_, _) => const OfflineScreen()),
        GoRoute(path: '/profile', builder: (_, s) => ProfileScreen(next: s.uri.queryParameters['next'])),
        GoRoute(path: '/', builder: (_, _) => const HomeShell(tab: 0)),
        GoRoute(path: '/places', builder: (_, _) => const HomeShell(tab: 1)),
        GoRoute(path: '/me', builder: (_, _) => const HomeShell(tab: 2)),
        GoRoute(path: '/checkin', builder: (_, _) => const CheckInScreen()),
        GoRoute(path: '/p/:id', builder: (_, s) => PlaceScreen(placeId: s.pathParameters['id']!)),
        GoRoute(path: '/new', builder: (_, _) => const NewEventScreen()),
        GoRoute(
          path: '/e/:id',
          builder: (_, s) => EventScreen(
            id: s.pathParameters['id']!,
            autoJoin: s.uri.queryParameters['join'] == '1',
            share: s.uri.queryParameters['share'] == '1',
          ),
          routes: [
            GoRoute(
              path: 'm/:uid',
              builder: (_, s) => MatchScreen(eventId: s.pathParameters['id']!, other: s.pathParameters['uid']!),
            ),
          ],
        ),
      ],
      errorBuilder: (_, _) => const Scaffold(
        body: EmptyState(title: 'Nothing here', text: 'That link doesn’t go anywhere in Sidekick.'),
      ),
    );

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
          body: SafeArea(
            child: EmptyState(
              title: 'Almost there',
              text: 'This build has no backend settings. Build with --dart-define-from-file=env.json (see app/README.md).',
            ),
          ),
        ),
      );
}
