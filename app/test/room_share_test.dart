import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sidekick/theme.dart';
import 'package:sidekick/widgets/room_share.dart';

/// A screen with one button that opens the share sheet, the way the event screen does.
Future<void> openShare(WidgetTester tester, Brightness look) async {
  C.use(look);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(look == Brightness.light ? Palette.light : Palette.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showRoomShare(context, link: 'https://sidekick.artifisi.com/e/demo', eventName: 'Demo night'),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Sets the test screen to a phone's size in logical pixels, and puts it back afterwards.
void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _shareButton = find.widgetWithText(FilledButton, 'Share link');
final _sheetScroll = find.descendant(of: find.byType(BottomSheet), matching: find.byType(SingleChildScrollView));

void main() {
  testWidgets('on a small phone the code and the Share link button are both on screen', (tester) async {
    useScreen(tester, const Size(360, 640));

    await openShare(tester, Brightness.light);

    expect(tester.getRect(find.byType(QrImageView)).bottom, lessThanOrEqualTo(640));
    expect(tester.getRect(_shareButton).bottom, lessThanOrEqualTo(640));
  });

  testWidgets('on a very short screen the sheet scrolls down to the Share link button', (tester) async {
    useScreen(tester, const Size(360, 400));

    await openShare(tester, Brightness.dark);
    await tester.dragUntilVisible(_shareButton, _sheetScroll, const Offset(0, -40));

    expect(tester.getRect(_shareButton).bottom, lessThanOrEqualTo(400));
  });

  for (final look in [Brightness.light, Brightness.dark]) {
    testWidgets('the code is black on white in the ${look.name} look', (tester) async {
      useScreen(tester, const Size(360, 640));

      await openShare(tester, look);

      final code = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(code.eyeStyle.color, Colors.black);
      expect(code.dataModuleStyle.color, Colors.black);
      expect(code.backgroundColor, Colors.white);
    });
  }
}
