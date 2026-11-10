import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// "Bring the room in": the event's link and a code to scan, with a Share button. The sheet can be
/// dragged to full height, and it scrolls on a small phone, so the code and the button are never cut off.
Future<void> showRoomShare(BuildContext context, {required String link, String? eventName}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bring the room in', style: displayStyle(32)),
              const SizedBox(height: 8),
              Text(
                'Sidekick only works when people are checked in. Share the link or put the code on screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted),
              ),
              const SizedBox(height: 18),
              // Dark code on a white card in both looks. A camera needs the contrast, and a code drawn
              // in the look's ink would vanish on the light look.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(
                  data: link,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    SharePlus.instance.share(ShareParams(text: '${eventName ?? 'Join me'} on Sidekick: $link')),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share link'),
              ),
            ],
          ),
        ),
      ),
    );
