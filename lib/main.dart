import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const int _kMinIntervalMinutes = 15;
const int _kMaxScheduledNotifications = 60;
const int _kNotificationIdBase = 1000;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AquaholicApp());
}

class AquaholicApp extends StatelessWidget {
  const AquaholicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aquaholic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF4DABF7),
          secondary: const Color(0xFF74C0FC),
          surface: const Color(0xFF141B2D),
          background: const Color(0xFF0A0E1A),
          surfaceVariant: const Color(0xFF1E2740),
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withOpacity(0.05),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const Color(0xFF4DABF7);
            }
            return const Color(0xFF3A4558);
          }),
          trackColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const Color(0xFF4DABF7).withOpacity(0.3);
            }
            return const Color(0xFF1E2740);
          }),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0E1A),
          elevation: 0,
          centerTitle: true,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

@immutable
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.intervalMinutes,
    required this.quietStart,
    required this.quietEnd,
  });

  final bool enabled;
  final int intervalMinutes;
  final TimeOfDay quietStart;
  final TimeOfDay quietEnd;

  ReminderSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
    );
  }
}

class _SettingsStore {
  static const String _kEnabled = 'enabled';
  static const String _kInterval = 'intervalMinutes';
  static const String _kQuietStartMinutes = 'quietStartMinutes';
  static const String _kQuietEndMinutes = 'quietEndMinutes';

  Future<ReminderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    final intervalMinutes = prefs.getInt(_kInterval) ?? 60;

    final quietStartMinutes = prefs.getInt(_kQuietStartMinutes) ?? 0;
    final quietEndMinutes = prefs.getInt(_kQuietEndMinutes) ?? (5 * 60);

    return ReminderSettings(
      enabled: enabled,
      intervalMinutes: intervalMinutes.clamp(_kMinIntervalMinutes, 24 * 60),
      quietStart: _timeOfDayFromMinutes(quietStartMinutes),
      quietEnd: _timeOfDayFromMinutes(quietEndMinutes),
    );
  }

  Future<void> save(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, settings.enabled);
    await prefs.setInt(_kInterval, settings.intervalMinutes);
    await prefs.setInt(_kQuietStartMinutes, _minutesFromTimeOfDay(settings.quietStart));
    await prefs.setInt(_kQuietEndMinutes, _minutesFromTimeOfDay(settings.quietEnd));
  }
}

class _NotificationService {
  _NotificationService._();
  static final _NotificationService instance = _NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } on MissingPluginException {
      tz.setLocalLocation(tz.UTC);
    } on PlatformException {
      tz.setLocalLocation(tz.UTC);
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const windowsInit = WindowsInitializationSettings(
      appName: 'Aquaholic',
      appUserModelId: 'com.aquaholic.app',
      guid: '5F8E3E7A-8D6C-49AA-9F7D-74A1E1E0D4C0',
    );

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
      windows: Platform.isWindows ? windowsInit : null,
    );

    await _plugin.initialize(initSettings);

    await _requestPermissions();
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> cancelAllScheduled() async {
    for (var i = 0; i < _kMaxScheduledNotifications; i++) {
      await _plugin.cancel(_kNotificationIdBase + i);
    }
  }

  NotificationDetails _details() {
    const androidDetails = AndroidNotificationDetails(
      'water_reminders',
      'Water reminders',
      channelDescription: 'Reminders to drink water',
      importance: Importance.max,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    return const NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  Future<void> scheduleRolling({required ReminderSettings settings}) async {
    await cancelAllScheduled();
    if (!settings.enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    final scheduledTimes = _computeNextTimes(
      now: now,
      intervalMinutes: settings.intervalMinutes,
      quietStart: settings.quietStart,
      quietEnd: settings.quietEnd,
      count: _kMaxScheduledNotifications,
    );

    final details = _details();
    for (var i = 0; i < scheduledTimes.length; i++) {
      final when = scheduledTimes[i];
      await _plugin.zonedSchedule(
        _kNotificationIdBase + i,
        'Drink water',
        'Time to hydrate',
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = _SettingsStore();
  ReminderSettings? _settings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _NotificationService.instance.init();
    final s = await _store.load();
    setState(() => _settings = s);
    if (s.enabled) {
      await _NotificationService.instance.scheduleRolling(settings: s);
    }
  }

  Future<void> _apply(ReminderSettings next) async {
    setState(() {
      _busy = true;
      _settings = next;
    });
    await _store.save(next);
    await _NotificationService.instance.scheduleRolling(settings: next);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickQuietStart() async {
    final s = _settings;
    if (s == null) return;
    final picked = await showTimePicker(context: context, initialTime: s.quietStart);
    if (picked == null) return;
    await _apply(s.copyWith(quietStart: picked));
  }

  Future<void> _pickQuietEnd() async {
    final s = _settings;
    if (s == null) return;
    final picked = await showTimePicker(context: context, initialTime: s.quietEnd);
    if (picked == null) return;
    await _apply(s.copyWith(quietEnd: picked));
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: 80,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              child: Image.asset(
                'assets/Logo_transparent.png',
                height: 80,
                width: 80,
                semanticLabel: 'Aquaholic',
              ),
            ),
            const SizedBox(width: 8),
            const Text('Aquaholic', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildMainCard(context, s),
          const SizedBox(height: 10),
          _buildQuietHoursCard(context, s),
          const SizedBox(height: 16),
          if (_busy)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainCard(BuildContext context, ReminderSettings s) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.notifications_active,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reminders',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.enabled ? 'Active' : 'Inactive',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: s.enabled
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white54,
                                  fontSize: 16,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 1.1,
                      child: Switch(
                        value: s.enabled,
                        onChanged: _busy ? null : (v) => _apply(s.copyWith(enabled: v)),
                      ),
                    ),
                  ],
                ),
                if (s.enabled) ...[
                  const SizedBox(height: 24),
                  Divider(color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 20),
                  Text(
                    'Interval',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.08),
                          Colors.white.withOpacity(0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: s.intervalMinutes,
                        isExpanded: true,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                        dropdownColor: const Color(0xFF1E2740),
                        borderRadius: BorderRadius.circular(12),
                        onChanged: _busy
                            ? null
                            : (v) {
                                if (v == null) return;
                                _apply(s.copyWith(intervalMinutes: v));
                              },
                        items: const [15, 30, 45, 60, 90, 120, 180]
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text('$m Minutes'),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuietHoursCard(BuildContext context, ReminderSettings s) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                            Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.bedtime,
                        color: Theme.of(context).colorScheme.secondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Quiet Hours',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTimeSelector(
                  context,
                  label: 'Start',
                  time: _formatTimeOfDay(context, s.quietStart),
                  onTap: _busy ? null : _pickQuietStart,
                ),
                const SizedBox(height: 12),
                _buildTimeSelector(
                  context,
                  label: 'End',
                  time: _formatTimeOfDay(context, s.quietEnd),
                  onTap: _busy ? null : _pickQuietEnd,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector(
    BuildContext context, {
    required String label,
    required String time,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          fontSize: 16,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}

List<tz.TZDateTime> _computeNextTimes({
  required tz.TZDateTime now,
  required int intervalMinutes,
  required TimeOfDay quietStart,
  required TimeOfDay quietEnd,
  required int count,
}) {
  final interval = Duration(minutes: intervalMinutes.clamp(_kMinIntervalMinutes, 24 * 60));
  final out = <tz.TZDateTime>[];

  var candidate = now.add(interval);
  var guard = 0;

  while (out.length < count && guard < count * 10) {
    guard++;
    if (!_isWithinQuietHours(candidate, quietStart, quietEnd)) {
      out.add(candidate);
    }
    candidate = candidate.add(interval);
  }
  return out;
}

bool _isWithinQuietHours(tz.TZDateTime t, TimeOfDay quietStart, TimeOfDay quietEnd) {
  final m = t.hour * 60 + t.minute;
  final start = _minutesFromTimeOfDay(quietStart);
  final end = _minutesFromTimeOfDay(quietEnd);

  if (start == end) {
    return false;
  }

  if (start < end) {
    return m >= start && m < end;
  }
  return m >= start || m < end;
}

int _minutesFromTimeOfDay(TimeOfDay t) => t.hour * 60 + t.minute;

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  final m = minutes % (24 * 60);
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

String _formatTimeOfDay(BuildContext context, TimeOfDay t) {
  return MaterialLocalizations.of(context).formatTimeOfDay(t);
}