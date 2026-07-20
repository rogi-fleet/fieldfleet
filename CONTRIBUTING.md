# Contributing to FieldFleet

Thanks for your interest in FieldFleet, the field operations platform built
by [TaskFleet](https://taskfleet.app). Contributions are welcome — bug
reports, fixes, tests, docs, and features.

## Before You Start

- FieldFleet is licensed under the **Elastic License 2.0** —
  source-available, free to use and self-host, but not OSI open source. By
  submitting a contribution you agree it may be used, modified, licensed, and
  distributed by TaskFleet under any terms, including in commercial
  offerings. See [LICENSE](LICENSE).
- For large changes, open an issue first to discuss the direction before
  investing time in a pull request.

## Development Setup

Follow the [Quick Start](README.md#quick-start): install the Flutter SDK and
Supabase CLI, run `flutter pub get`, `supabase start`, and
`supabase migration up --local`, then `flutter run -d chrome`. This public
checkout uses Supabase project id `fieldfleet_public` and local port `55321`;
inspect existing Supabase containers before running reset or repair commands.

## Making Changes

- Keep edits scoped and consistent with the existing Flutter/Supabase
  patterns (Provider for state, go_router for navigation, services under
  `lib/services/`, models under `lib/models/`).
- Add or update tests under `test/` for behavior you change.
- Run the same checks CI runs before pushing:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

## What Not to Submit

- Secrets of any kind: `.env` files, service keys, JWTs, database dumps,
  auth-state files, or screenshots containing real data. If a change needs a
  secret, document the environment variable name instead of a value.
- Real hostnames or environment-specific paths. Use placeholders such as
  `https://api.example.com` and `/path/to/fieldfleet`.
- Changes to the license or the README's licensing/positioning language.

Run a secret scanner (for example
[Gitleaks](https://github.com/gitleaks/gitleaks)) before pushing.

## Reporting Bugs and Requesting Features

Use the issue templates. For security vulnerabilities, do **not** open a
public issue — see [SECURITY.md](SECURITY.md).
