# Sidekick app (Flutter)

See the [main README](../README.md) for setup. Quick reference:

```sh
flutter pub get
flutter test
flutter run --dart-define=DEV_API=http://10.0.2.2:8787          # against the local dev API (Android emulator)
flutter build apk --release --dart-define-from-file=env.json     # against AWS (copy env.example.json)
```

- `lib/data/identity.dart`: Cognito identity pool (guest identities, linking Google).
- `lib/data/api.dart`: signed calls to the API.
- `lib/data/session.dart`: who's signed in, and their profile.
- `lib/screens/`: welcome, profile, home tabs, check-in, add event, event room (swipe deck), match.
