import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'art.dart';
import 'mark.dart';

/// A person's photo, or their initial on colour until they have one: on their own poster colour
/// when it's large, on the secondary colour when it's small.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url = '', this.size = 44, this.seed, this.ring});
  final String name;
  final String url;
  final double size;
  final String? seed;

  /// A ring around the picture, in this colour: paper where avatars overlap, Signal for a new match.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final Widget fallback = size >= 56
        ? SizedBox(
            width: size,
            height: size,
            child: ClipOval(child: PosterArt(seed ?? name, monogram: initial, monogramAt: Alignment.center)),
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: C.second, shape: BoxShape.circle),
            child: Text(initial, style: displayStyle(size * 0.5, color: C.onSecond)),
          );
    final Widget face = url.isEmpty
        ? fallback
        : ClipOval(
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : Container(width: size, height: size, color: C.soft),
            ),
          );
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: ring == null
          ? face
          : Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: face,
            ),
    );
  }
}

/// A few overlapping faces and a count: who's in the room.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.people, this.size = 28, this.max = 4});

  /// Name and photo of each person.
  final List<({String name, String url})> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size * 0.68;
    return SizedBox(
      width: size + 5 + step * (shown.length - 1),
      height: size + 5,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: i * step,
            child: Avatar(name: shown[i].name, url: shown[i].url, size: size, ring: C.paper),
          ),
      ]),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: highlight ? C.second : C.surface,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: highlight ? C.second : C.line),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.1,
        color: highlight ? C.onSecond : C.ink,
        fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? C.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key});
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: C.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline_rounded, color: C.danger, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text!, style: TextStyle(color: C.danger, fontSize: 14.5, height: 1.35))),
      ]),
    );
  }
}

/// Nothing to show yet: Buddy (or an icon), a serif line, and what to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.text, this.action, this.icon, this.mood});
  final String title;
  final String text;
  final Widget? action;
  final IconData? icon;

  /// Shows Buddy in this mood instead of an icon.
  final BuddyMood? mood;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mood != null) ...[
          SidekickMark(size: 44, mood: mood!),
          const SizedBox(height: 20),
        ] else if (icon != null) ...[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: C.second, shape: BoxShape.circle),
            child: Icon(icon, color: C.onSecond, size: 26),
          ),
          const SizedBox(height: 20),
        ],
        Text(title, textAlign: TextAlign.center, style: displayStyle(30)),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 15.5, height: 1.45),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 22), action!],
      ],
    ),
  );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: C.brand)),
  );
}

class ButtonProgress extends StatelessWidget {
  const ButtonProgress({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color ?? C.onBrand));
}

void haptic() => HapticFeedback.lightImpact();

void toast(BuildContext context, String text) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// Google's "G", for our own sign-in button.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    child: const Text(
      'G',
      style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w600, fontSize: 14),
    ),
  );
}

/// The Buddy mark and "Sidekick." in the serif italic.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SidekickMark(size: size * 0.8),
        SizedBox(width: size * 0.35),
        Text('Sidekick.', style: displayStyle(size, style: FontStyle.italic)),
      ]);
}

/// A letterspaced caps label over a section, like YOUR EVENTS.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: caps)),
          ?trailing,
        ]),
      );
}

/// The big serif title at the top of a screen, with a line under it.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.text, this.size = 40});
  final String title;
  final String? text;
  final double size;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: displayStyle(size)),
        if (text != null) ...[
          const SizedBox(height: 10),
          Text(text!, style: TextStyle(color: C.muted, fontSize: 16, height: 1.45)),
        ],
      ]);
}

/// A round button with one icon: back, share, more. [glass] is for buttons that sit on a poster.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 42,
    this.glass = false,
    this.badge = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;
  final bool glass;
  final bool badge;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Stack(clipBehavior: Clip.none, children: [
          Material(
            color: glass ? Poster.glass : C.surface,
            shape: CircleBorder(side: glass ? const BorderSide(color: Poster.edge) : BorderSide.none),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, size: size * 0.48, color: glass ? Poster.ink : C.ink),
              ),
            ),
          ),
          if (badge)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: signal,
                  shape: BoxShape.circle,
                  border: Border.all(color: C.paper, width: 2),
                ),
              ),
            ),
        ]),
      );
}

/// The bar at the top of a pushed screen: a round back button, an optional title, and actions.
class BackBar extends StatelessWidget implements PreferredSizeWidget {
  const BackBar({super.key, this.title, this.actions = const [], this.onBack});
  final Widget? title;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) => AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 60,
        titleSpacing: 0,
        leadingWidth: 68,
        leading: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        title: title,
        actions: [
          for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: Center(child: a)),
          const SizedBox(width: 16),
        ],
      );
}

/// Two or three choices in a pill, like Scouted | Matches.
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.items, required this.value, required this.onChanged, this.dense = false});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: dense ? MainAxisSize.min : MainAxisSize.max, children: [
          for (final (v, label) in items)
            _wrap(
              Semantics(
                button: true,
                selected: v == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (v == value) return;
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.symmetric(vertical: dense ? 7 : 11, horizontal: dense ? 14 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? C.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 13 : 15,
                        fontWeight: FontWeight.w500,
                        color: v == value ? C.onBrand : C.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _wrap(Widget child) => dense ? child : Expanded(child: child);
}

/// The one Signal button: Connect, and the other moments a match is made of.
class SignalButton extends StatelessWidget {
  const SignalButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(backgroundColor: signal, foregroundColor: onSignal),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const ButtonProgress(color: onSignal)
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
      );
}

/// A Signal dot that breathes: something is happening right now.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8});
  final double size;
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size * 2,
        height: widget.size * 2,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _LivePainter(_c.value, widget.size / 2)),
        ),
      );
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.t, this.r);
  final double t, r;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    canvas.drawCircle(c, r + r * 1.0 * t, Paint()..color = signal.withValues(alpha: 0.35 * (1 - t)));
    canvas.drawCircle(c, r, Paint()..color = signal);
  }

  @override
  bool shouldRepaint(_LivePainter old) => old.t != t;
}

/// A grey block that breathes while the real thing loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 10});
  final double? width;
  final double height;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(color: C.soft, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

/// A few rows of skeleton, the shape of a list of people or events.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 3, this.round = true});
  final int count;
  final bool round;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Skeleton(width: 50, height: 50, radius: round ? 25 : 14),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Skeleton(width: 140.0 + (i.isEven ? 30 : 0), height: 14),
                  const SizedBox(height: 8),
                  Skeleton(width: 200.0 - (i.isEven ? 0 : 40), height: 12),
                ]),
              ),
            ]),
          ),
      ]);
}

/// What the sidekick says: Buddy, a caps label in Signal, and its line.
class SidekickNote extends StatelessWidget {
  const SidekickNote({super.key, required this.text, this.label = 'YOUR SIDEKICK', this.mood = BuddyMood.wink, this.busy = false});
  final String text;
  final String label;
  final BuddyMood mood;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(color: C.second, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SidekickMark(size: 14, mood: mood),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: eyebrow.copyWith(fontSize: 11))),
            if (busy) SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: C.go)),
          ]),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(fontSize: 16, height: 1.45, color: C.onSecond)),
        ]),
      );
}

/// A square with the day and month of an event, or an icon for a place check-in.
class DateTile extends StatelessWidget {
  const DateTile({super.key, this.date, this.icon, this.live = false, this.size = 52});
  final DateTime? date;
  final IconData? icon;
  final bool live;
  final double size;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final d = date;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live ? C.brand : C.second,
        borderRadius: BorderRadius.circular(15),
      ),
      child: d == null || icon != null
          ? Icon(icon ?? Icons.event_outlined, size: 21, color: live ? C.onBrand : C.onSecond)
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                _months[d.month - 1],
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: (live ? C.onBrand : C.onSecond).withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 3),
              Text('${d.day}', style: displayStyle(23, color: live ? C.onBrand : C.onSecond)),
            ]),
    );
  }
}

/// A person as a poster: their photo, or their initials on their own colour, deepening at the
/// bottom so light words can sit on it.
class PortraitPoster extends StatelessWidget {
  const PortraitPoster({
    super.key,
    required this.name,
    required this.seed,
    this.url = '',
    this.child,
    this.scrim = 0.5,
    this.radius,
  });
  final String name;
  final String seed;
  final String url;

  /// Laid over the picture.
  final Widget? child;

  /// How far up the dark fade starts, as a fraction of the height from the top.
  final double scrim;

  /// Rounded corners, for a poster that is a card. Square when it runs edge to edge.
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final art = PosterArt(seed, monogram: initialsOf(name), monogramAt: Alignment(0, scrim - 0.95));
    final (_, deep) = toneOf(seed);
    // A photo needs a darker fade than flat colour does.
    final under = url.isEmpty ? deep : const Color(0xFF07110C);
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.zero,
      child: ColoredBox(
        color: Poster.bg,
        child: Stack(fit: StackFit.expand, children: [
          if (url.isEmpty) art else Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => art),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  under.withValues(alpha: 0.4),
                  under.withValues(alpha: 0),
                  under.withValues(alpha: 0),
                  under.withValues(alpha: 0.85),
                  under.withValues(alpha: 0.96),
                ],
                stops: [0, 0.2, scrim * 0.7, scrim + (1 - scrim) * 0.45, 1],
              ),
            ),
          ),
          ?child,
        ]),
      ),
    );
  }
}

/// Asks before something that can't be taken back, in a sheet with the action named on the button.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
  bool danger = true,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: displayStyle(30)),
            const SizedBox(height: 10),
            Text(text, style: TextStyle(color: C.muted, fontSize: 16, height: 1.45)),
            const SizedBox(height: 22),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: C.paper) : null,
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Cancel', style: TextStyle(color: C.muted)),
            ),
          ]),
        ),
      ),
    ) ==
    true;

/// One row of a sheet of actions.
class SheetAction extends StatelessWidget {
  const SheetAction({super.key, required this.icon, required this.title, this.text, required this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String? text;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: C.surface, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: danger ? C.danger : C.ink),
        ),
        title: Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w500, color: danger ? C.danger : C.ink)),
        subtitle: text == null ? null : Text(text!, style: TextStyle(color: C.muted, fontSize: 14, height: 1.35)),
        onTap: onTap,
      );
}

/// A banner asking for something small: sign in, finish your profile.
class Nudge extends StatelessWidget {
  const Nudge({super.key, required this.text, required this.action, required this.onTap});
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.second,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(children: [
              const SidekickMark(size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, height: 1.35, color: C.onSecond))),
              const SizedBox(width: 10),
              Text(action, style: TextStyle(color: C.go, fontWeight: FontWeight.w600, fontSize: 14.5)),
            ]),
          ),
        ),
      );
}
