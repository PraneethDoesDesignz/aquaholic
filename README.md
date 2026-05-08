# Aquaholic

Aquaholic is a Flutter hydration reminder app that helps users stay hydrated with recurring local notifications.

## What it does

- Sends water reminders on a schedule you choose.
- Lets users enable or disable reminders.
- Supports configurable reminder intervals from 15 minutes up to 3 hours.
- Includes quiet hours so notifications are automatically paused during sleep or do-not-disturb windows.
- Persists settings locally using shared preferences.

## Key features

- Local notifications via `flutter_local_notifications`
- Timezone-aware scheduling with `timezone` and `flutter_timezone`
- Settings storage using `shared_preferences`
- Dark-themed Material UI with interval selector and quiet hours picker
- Multi-platform support (Android, iOS, macOS, Windows)

## How it works

- The app initializes notification services and reads saved reminder settings.
- If reminders are enabled, it schedules a rolling set of notifications at the selected interval.
- Quiet hours are respected by skipping notifications between the configured start and end times.

## Quick start

1. Install Flutter dependencies:

```bash
flutter pub get
```

2. Run the app on a connected device or emulator:

```bash
flutter run
```

## App configuration

The main app logic is implemented in `lib/main.dart`.

- `ReminderSettings` stores whether reminders are enabled, the reminder interval, and quiet hours.
- `_NotificationService` initializes notification permissions and schedules local reminders.
- `_SettingsStore` saves and loads settings with `SharedPreferences`.

## Dependencies

- `flutter_local_notifications`
- `flutter_local_notifications_windows`
- `timezone`
- `flutter_timezone`
- `shared_preferences`

## Notes

- Minimum reminder interval is 15 minutes.
- The app schedules up to 60 future notifications to keep reminders active.
- Quiet hours wrap across midnight when needed.
