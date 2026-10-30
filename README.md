# signage_surgeon

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android release signing

Copy `android/key.properties.sample` → `android/key.properties` (gitignored — never commit it)
and fill in your real keystore details:

```bash
cp android/key.properties.sample android/key.properties
```

Without `android/key.properties`, `flutter build apk --release` still succeeds (falls back to
the debug key) so local release builds work out of the box — just never ship a Play Store build
signed that way.

```bash
flutter build appbundle --release   # Play Store
flutter build apk --release         # sideload / testing
```
