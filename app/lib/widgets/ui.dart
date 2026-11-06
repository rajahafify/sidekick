import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'dots.dart';

/// A person's photo in black and white, or a dotted portrait until they have one.
/// Small avatars show their initial instead, since dots don't read at that size.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url = '', this.size = 44, this.seed});
  final String name;
  final String url;
  final double size;
  final String? seed;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final Widget fallback = size >= 56
        ? SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: ColoredBox(
                color: C.paper,
                child: Dots(portraitField(seed ?? name, headY: 0.4, scale: 1.1), step: math.max(4.0, size / 16)),
              ),
            ),
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: C.soft, shape: BoxShape.circle),
            child: Text(initial, style: displayStyle(size * 0.5)),
          );
    if (url.isEmpty) return Align(widthFactor: 1, heightFactor: 1, child: fallback);
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: ClipOval(
        child: ColorFiltered(
          colorFilter: grayscale,
          child: Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
        ),
      ),
    );
  }
}

const grayscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: highlight ? C.go : C.soft,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: highlight ? C.go : C.line),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: highlight ? C.onInk : C.ink,
        fontWeight: highlight ? FontWeight.w600 : null,
      ),
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: C.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: C.line),
    ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.danger.withValues(alpha: 0.3)),
      ),
      child: Text(text!, style: const TextStyle(color: C.danger, fontSize: 15)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.text, this.action, this.icon});
  final String title;
  final String text;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
    child: Column(
      children: [
        if (icon != null) ...[Icon(icon, color: C.ink, size: 36), const SizedBox(height: 16)],
        Text(title, textAlign: TextAlign.center, style: displayStyle(30)),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 16, height: 1.4),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.go)),
  );
}

class ButtonProgress extends StatelessWidget {
  const ButtonProgress({super.key});
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.onInk));
}

void haptic() => HapticFeedback.lightImpact();

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
      style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w700, fontSize: 14),
    ),
  );
}
