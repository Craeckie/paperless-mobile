# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Paperless Mobile is a Flutter (Dart) client for [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx), targeting Android and iOS. It lets users view, edit, scan, upload, search and organize documents on a self-hosted paperless server, with support for multiple accounts, biometric auth, mTLS client certificates and 2FA.

## Toolchain (FVM)

The Flutter SDK version is pinned via [FVM](https://fvm.app) in `.fvmrc` (Flutter `3.35.4`, Dart SDK `>=3.8.0 <4.0.0`). **Prefix Flutter/Dart commands with `fvm`** (e.g. `fvm flutter ...`, `fvm dart ...`) to use the pinned version. A Flutter git submodule is also pinned under `flutter/` as an alternative (`git submodule update --init`). Commands below assume `fvm`.

## Common Commands

```sh
# One-shot setup: pub get + gen-l10n + build_runner (the canonical bootstrap)
scripts/install_dependencies_fvm.sh    # fvm variant; install_dependencies.sh is the non-fvm version

# Manual equivalents
fvm dart pub get
fvm flutter gen-l10n                                       # generates lib/generated/l10n from lib/l10n/*.arb
fvm dart run build_runner build --delete-conflicting-outputs   # json_serializable, freezed, mockito, copy_with

# Analyze / format (must pass; enforced by the pre-commit hook)
fvm dart analyze
fvm dart format .

# Tests
fvm flutter test                                          # all unit/widget tests under test/
fvm flutter test test/src/bloc/<file>_test.dart           # a single test file
fvm flutter test --plain-name "<test name>"               # a single test by name

# Integration tests (need a device/emulator)
fvm flutter test integration_test/

# Run / build
fvm flutter run
fvm flutter build apk [--split-per-abi]                   # see CONTRIBUTING.md for release signing notes
```

Install the git hooks once with `scripts/install_git_hooks.sh`. The `pre-commit` hook checks staged Dart files for merge markers, formatting (`dart format`) and analyzer errors; bypass with `git commit --no-verify`.

## Code Generation

Generated files (`*.g.dart`, `*.freezed.dart`) are **not** committed-safe to hand-edit — regenerate with `build_runner`. `build.yaml` configures `json_serializable` with `field_rename: snake` and `explicit_to_json: true`, and scopes `mockito` mock generation to `lib/`, `test/` and `integration_test/src/mocks/`. The analyzer excludes `**/*.g.dart` and `**/*.freezed.dart`.

The low-level API model/client classes under `lib/generated/` are produced from the OpenAPI spec `specs/paperless-ngx-api-v9.yaml` via `scripts/generate_models.sh` (`openapi-generator`, `dart-dio`). Do not hand-edit `lib/generated/`; change the spec or the script and regenerate.

## Architecture

The app uses a layered architecture wired together with `provider` (DI), `flutter_bloc`/`hydrated_bloc` (state), and `cached_query_flutter` (server-state caching). Entry point is `lib/main.dart`.

**Layers (top → bottom):**

- **`lib/features/<feature>/`** — feature-first organization (documents, inbox, login, document_scan, document_edit, labels, saved_view, settings, etc.). Each feature typically holds `cubit/` or `bloc/` state classes and `view/pages` + `view/widgets`. UI talks to repositories/blocs, never to the raw API.
- **`lib/core/repository/`** — repositories (e.g. `DocumentRepository`, label/tag/correspondent repos) wrap the API modules, own caching/invalidation via `cached_query`, and expose `ChangeNotifier`-style streams (`ChangeNotifierMixin`). This is the boundary the UI and blocs depend on.
- **`lib/api/`** — the typed Paperless API surface. `modules/` holds the client interfaces/impls (`PaperlessDocumentsApi`, `paperless_search_api`, label/user/tasks/stats/custom-fields, `authentication_api`), `models/` the hand-written domain models, and `interceptor/`/`converters/` Dio plumbing. `paperless_api.dart` is the barrel export. Supported server API versions are `minSupportedApiVersion`..`latestSupportedApiVersion` in `lib/constants.dart`.
- **`lib/core/`** — cross-cutting infrastructure: `security/` (SessionManager — per-account Dio sessions, mTLS), `store/` (encrypted local store + Hive-backed `slices/` for global settings, accounts, credentials, per-user app state), `service/`, `interceptor/`, `bloc/` (e.g. `ConnectivityCubit`), `notifier/`, `extensions/`.
- **`lib/routing/`** — `go_router` configuration. `routes/` defines per-feature routes; `routes/shells/` defines shell routes (e.g. `authenticated_route.dart`) that gate authenticated navigation; `navigation_keys.dart` holds global navigator keys.

**Multi-account & sessions:** the app supports multiple paperless accounts. `SessionManager` (`lib/core/security/`) manages authenticated Dio clients per local user; account/credential/global-settings state lives in the encrypted store slices under `lib/core/store/slices/`. `AuthenticationCubit` (`lib/features/login/cubit/`) drives login/logout and account switching. Settings (theme, locale, biometric lock) are persisted via `hydrated_bloc` and the encrypted store.

## Localization

Strings live in `lib/l10n/intl_*.arb` (template `intl_en.arb`); `fvm flutter gen-l10n` generates the `S` localization class into `lib/generated/l10n/` (config in `l10n.yaml`). Translations are managed via Crowdin (`crowdin.yml`); helper scripts: `scripts/upload_translation_source.sh`, `scripts/update_translations.sh`. Untranslated keys are reported to `untranslated_messages.txt`.

## Releasing

Use the `/version <major|minor|patch>` skill (defined in `.agents/skills/version/SKILL.md`). It bumps `version` in `pubspec.yaml` (format `<major>.<minor>.<patch>+<buildNumber>`), increments the build number by 10, generates fastlane changelog stubs from `feat`/`fix` commits since the last tag (translated per locale under `android/fastlane/metadata/android/`), and registers the new Android version code in `changelog_dialog.dart`. The Android version code is the build number with `3` appended (build `570` → `5703`).

## Conventions

- Commit messages follow Conventional Commits (`feat:`, `fix:`, `chore:`); PRs target the `development` branch.
- Lints come from `package:flutter_lints` (`analysis_options.yaml`).
