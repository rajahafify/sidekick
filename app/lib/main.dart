import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'data/session.dart';
import 'models.dart';
import 'screens/admin.dart';
import 'screens/chat.dart';
import 'screens/check_in.dart';
import 'screens/event.dart';
import 'screens/home.dart';
import 'screens/match.dart';
import 'screens/new_event.dart';
import 'screens/profile.dart';
import 'screens/welcome.dart';
import 'theme.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths on the web (sidekick.artifisi.com/e/<id>), not #/ links.
  usePathUrlStrategy();
  if (!Config.configured) {
    SystemChrome.setSystemUIOverlayStyle(_chrome(Brightness.dark));
    runApp(const _NotConfigured());
    return;
  }
  final session = Session();
  // Read the person's own theme before the first frame, so the app doesn't flash the wrong look.
  await session.loadTheme();
  runApp(SidekickApp(session: session));
  await session.start();
}

/// Status bar and navigation bar, matching the look in use.
SystemUiOverlayStyle _chrome(Brightness b) {
  final light = b == Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: C.paper,
    systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
  );
}

class SidekickApp extends StatefulWidget {
  const SidekickApp({super.key, required this.session});
  final Session session;

  @override
  State<SidekickApp> createState() => _SidekickAppState();
}

class _SidekickAppState extends State<SidekickApp> with WidgetsBindingObserver {
  late final GoRouter router = _router(widget.session);
  ThemeChoice? _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onChange);
    _syncTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onChange);
    super.dispose();
  }

  // The phone or browser switched between light and dark: "system" follows it.
  @override
  void didChangePlatformBrightness() => _onChange();

  void _onChange() {
    if (!_syncTheme()) return;
    // Screens read the colours while they build, and some are not rebuilt by their parent (a const
    // route, or the tab bar under it). So mark every element dirty: the whole app rebuilds once,
    // in the new colours, and screens keep their state.
    _rebuildEverything(WidgetsBinding.instance.rootElement);
    if (mounted) setState(() {});
  }

  static void _rebuildEverything(Element? e) {
    if (e == null) return;
    e.markNeedsBuild();
    e.visitChildren(_rebuildEverything);
  }

  /// Points the colours in use (C) at the look to show. Returns true if the look changed, so the
  /// app rebuilds with it.
  bool _syncTheme() {
    final choice = widget.session.theme;
    final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final b = brightnessOf(choice, platform);
    if (choice == _shown && b == C.brightness) return false;
    _shown = choice;
    C.use(b);
    SystemChrome.setSystemUIOverlayStyle(_chrome(b));
    return true;
  }

  @override
  Widget build(BuildContext context) => SessionScope(
        session: widget.session,
        child: MaterialApp.router(
          title: 'Sidekick',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Palette.light),
          darkTheme: buildTheme(Palette.dark),
          themeMode: themeModeOf(widget.session.theme),
          routerConfig: router,
          builder: (context, child) => _PhoneFrame(child: child ?? const SizedBox.shrink()),
        ),
      );
}

/// On a wide browser window the app is a phone-width column in the middle, not a page stretched
/// edge to edge. Phones, and the admin site (which has its own layout), get the full width.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  static const width = 560.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!kIsWeb || Config.adminHost || media.size.width < width + 120) return child;
    return ColoredBox(
      color: C.surface,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: C.paper,
            border: Border.symmetric(vertical: BorderSide(color: C.line)),
          ),
          child: SizedBox(
            width: width,
            height: media.size.height,
            child: MediaQuery(
              data: media.copyWith(size: Size(width, media.size.height)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
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
        GoRoute(path: '/messages', builder: (_, _) => const HomeShell(tab: 1)),
        GoRoute(path: '/places', builder: (_, _) => const HomeShell(tab: 2)),
        GoRoute(path: '/alerts', builder: (_, _) => const HomeShell(tab: 3)),
        GoRoute(path: '/me', builder: (_, _) => const HomeShell(tab: 4)),
        GoRoute(path: '/connected', builder: (_, _) => const HomeShell(tab: 5)),
        GoRoute(path: '/checkin', builder: (_, _) => const CheckInScreen()),
        GoRoute(path: '/new', builder: (_, _) => const NewEventScreen()),
        GoRoute(
          path: '/chat/:id/:uid',
          builder: (_, s) => ChatScreen(eventId: s.pathParameters['id']!, other: s.pathParameters['uid']!),
        ),
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
        theme: buildTheme(Palette.dark),
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
