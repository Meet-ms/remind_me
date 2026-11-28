# remind_me

A new Flutter project.

## Maps and place search

Map tiles and place search use [Ola Maps](https://maps.olakrutrim.com). Put
your API key in a `dart_defines.json` file in the project root (it is
git-ignored):

```json
{ "OLA_MAPS_API_KEY": "your-key" }
```

and pass it when running or building:

```
flutter run --dart-define-from-file=dart_defines.json
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
