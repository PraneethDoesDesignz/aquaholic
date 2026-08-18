// Desktop screenshot capture for Aquaholic.
//
//   flutter test tool/capture_screenshots.dart
//
// Renders the real UI on a 1280x800 desktop surface with the SDK's
// Roboto/MaterialIcons (otherwise flutter_test draws text as boxes) and writes
// one PNG per state and per section into screenshots/.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:Aquaholic/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _desktop = Size(1280, 800);
final Directory _outDir = Directory('screenshots');

Future<void> _loadSdkFonts() async {
  final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(File('$fonts/$name').readAsBytesSync());

  await (FontLoader('Roboto')
        ..addFont(read('roboto-regular.ttf'))
        ..addFont(read('roboto-medium.ttf'))
        ..addFont(read('roboto-bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(read('materialicons-regular.otf'))).load();
}

/// No plugin registrant runs in a test binding, so point the notification
/// platform interface at its method-channel implementation and stub the calls.
void _stubPlugins() {
  FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
  for (final channel in const [
    MethodChannel('dexterous.com/flutter/local_notifications'),
    MethodChannel('flutter_timezone'),
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => call.method == 'getLocalTimezone' ? 'UTC' : true);
  }
}

/// Boots the app with [prefs] already saved and settles the first real frame.
Future<void> _pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues({
    for (final e in prefs.entries) 'flutter.${e.key}': e.value,
  });
  await tester.pumpWidget(const AquaholicApp());
  // Asset decoding is real async work, so it needs runAsync or the logo in the
  // header renders as an empty box.
  await tester.runAsync(() => precacheImage(
        const AssetImage('assets/Logo_transparent.png'),
        tester.element(find.byType(MaterialApp)),
      ));
}

/// Writes the whole surface as `screenshots/[name].png`, or just the bounds of
/// [section] (plus a little margin) when given.
Future<void> _shoot(WidgetTester tester, String name, {Finder? section}) async {
  var root = tester.renderObject(find.byType(AquaholicApp));
  while (!root.isRepaintBoundary) {
    root = root.parent!;
  }
  final full = (root.debugLayer! as OffsetLayer).toImageSync(root.paintBounds);
  final surface = Offset.zero & _desktop;

  ui.Image shot = full;
  if (section != null) {
    final crop = tester.getRect(section).inflate(16).intersect(surface);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(full, crop, Offset.zero & crop.size, Paint());
    shot = recorder.endRecording().toImageSync(crop.width.round(), crop.height.round());
  }

  final png = await tester.runAsync(() => shot.toByteData(format: ui.ImageByteFormat.png));
  File('${_outDir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

Finder get _card => find.byType(BackdropFilter);

void main() {
  const off = <String, Object>{'enabled': false, 'intervalMinutes': 60};
  const on = <String, Object>{
    'enabled': true,
    'intervalMinutes': 60,
    'quietStartMinutes': 0,
    'quietEndMinutes': 300,
  };

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadSdkFonts();
    _outDir.createSync(recursive: true);
  });

  setUp(() {
    _stubPlugins();
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = _desktop;
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('reminders off', (tester) async {
    await _pumpApp(tester, off);
    await tester.pumpAndSettle();
    await _shoot(tester, '01-home-reminders-off');
    await _shoot(tester, '02-section-header', section: find.byType(AppBar));
    await _shoot(tester, '03-section-reminders-off', section: _card.at(0));
  });

  testWidgets('reminders on', (tester) async {
    await _pumpApp(tester, on);
    await tester.pumpAndSettle();
    await _shoot(tester, '04-home-reminders-on');
    await _shoot(tester, '05-section-reminders-on', section: _card.at(0));
    await _shoot(tester, '06-section-quiet-hours', section: _card.at(1));
  });

  testWidgets('interval dropdown', (tester) async {
    await _pumpApp(tester, on);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await _shoot(tester, '07-interval-dropdown');
  });

  testWidgets('quiet hours time picker', (tester) async {
    await _pumpApp(tester, on);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await _shoot(tester, '08-quiet-hours-time-picker');
  });
}
