# AGENTS.md

Canonical guide for humans and AI agents working on Fetchr (display name `Fetchr`, app id `com.defo.fetchr`, Dart package `grabby`, org `com.defo`). The Dart package keeps its old name, so every import is `package:grabby/...`. Read it before changing code. `CLAUDE.md` only points here.

Generated options: Riverpod, go_router, Sentry, screen scaling, git hooks. On top of that Fetchr has a native Kotlin layer (yt-dlp, ffmpeg and aria2c through youtubedl-android) behind a pigeon contract. This guide covers only what this app has.

## Commands

Run `fvm flutter` and `fvm dart`. The SDK is pinned in `.fvmrc` and installed by fvm into `.fvm/` (gitignored); run `fvm install` once per clone. `tool/check.sh` puts `.fvm/flutter_sdk/bin` on `PATH` itself.

```bash
fvm flutter pub get
fvm flutter run
fvm flutter analyze
fvm flutter test                               # all
fvm flutter test test/modules/downloader/data/downloader_repository_impl_test.dart
fvm flutter test --name "substring of a test name"
fvm dart format lib test
fvm dart run build_runner build   # flutter_gen

fvm dart run pigeon --input pigeons/fetchr_api.dart   # regenerate the native contract, then format the Dart output
fvm dart format lib/core/platform/fetchr_api.g.dart
(cd android && ./gradlew :app:testDebugUnitTest)      # Kotlin unit tests (Windows: gradlew.bat)

bash tool/check.sh fast                        # import URIs, format and gates on staged files
bash tool/check.sh full                        # everything below
python tool/ci/arch_gates.py                   # architecture gates vs tool/ci/arch_baseline.json
python tool/ci/arch_gates.py --list            # status only, always exit 0
python tool/ci/arch_gates.py --update-baseline # lock in fixed violations (refuses while a total grew)
git config core.hooksPath tool/hooks           # once per clone: enable the tracked git hooks

fvm flutter build apk --debug --split-per-abi --target-platform android-arm64
fvm flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

Builds always pass `--split-per-abi --target-platform`: Gradle has no ABI config, and a fat APK carries libpython, ffmpeg and aria2c for every ABI. media_kit downloads libmpv at build time, so builds need network.

`tool/check.sh full` runs: gates self-test, gates, `dart format --set-exit-if-changed`, `build_runner`, a check that generated files are committed (skipped before the first commit), `flutter analyze`, `flutter test`. The tracked hooks in `tool/hooks/` run `fast` on pre-commit; pre-push runs `full` only with `FULL_CHECK=1 git push` (PowerShell: `$env:FULL_CHECK=1; git push`), otherwise run `bash tool/check.sh full` by hand before a release. The toolchain is pinned in `.fvmrc` (Flutter 3.47.7, Dart 3.13.5) and run through fvm; needs Python 3.9+ for the gates.

If the hooks do not fire on macOS or Linux, `chmod +x tool/check.sh tool/hooks/*`.

**Release signing.** `android/key.properties` (gitignored) with `storeFile`, `storePassword`, `keyAlias` and `keyPassword` signs release builds. Without it release builds fall back to the debug key so `fvm flutter run --release` works, but that APK is debug-signed and cannot update a release-signed install.

## Architecture

Riverpod (state and dependency injection) and go_router (routing) over Clean Architecture. Providers are the dependency graph: there is no `get_it` and no `injectable`.

```text
lib/
  main.dart                    only calls bootstrap()
  app/                         wiring: knows every layer, no module imports it (except the allowed folders below)
    bootstrap/                 bootstrap.dart, app_initializer.dart, provider_error_observer.dart
    di/                        core_providers.dart (one provider per core object)
    routes/                    app_routes.dart (AppRoutes), app_router.dart (routerProvider, AppRouter, go_router; unknown paths open NotFoundView)
    shell/                     app_shell.dart: persistent_bottom_nav_bar_v2's Style 8 bar around the four tabs, a NavigationRail from 600 dp
    launch/                    launch_intro.dart, the splash hand-off into the Home header
    theme/                     themeModeProvider, accentProvider (Notifiers) and system_bars.dart
    shared/                    session-wide state every module reads: shared/domain/entities/quality.dart, download_prefs_provider.dart
  core/                        cross-cutting, state-management-neutral, imports no app/ or modules/
    config/                    environment.dart
    crash/ errors/ logging/ networking/ usecase/ utils/ widgets/
    platform/                  fetchr_api.g.dart, the generated pigeon client (see Native layer)
    gen/                       flutter_gen output (assets.gen.dart), committed
    services/                  storage/
    theme/                     app_colors.dart (the seed), app_tokens.dart, app_theme.dart, ...
  modules/<module>/            one folder per feature
    data/{datasources,models,repositories}
    domain/{entities,extensions,repositories,usecases}
    di/                        the module's providers: datasource, repository, use cases
    presentation/{formatters,providers,views/widgets}
```

No file sits at the root of a module's `domain/` or `presentation/`. A rule about the data that is not an entity is a getter on the entity (`DownloadTask.cardState`) or an extension in `domain/extensions/<type>_extensions.dart` (`List<DownloadTask>.groupedAt`, `String?.firstUrl`). UI copy built from a type is an extension in `presentation/formatters/<type>_formatter.dart` (`DownloadTaskFormat`, `QualityFormat`, `LibraryItemFormat`); it is presentation, not domain, because localising it will need `AppLocalizations` from Flutter, which G2 keeps out of domain. Copy shared by several modules (sizes, durations, dates, `plural`) is in `core/utils/formatters.dart`.

A module with no data or domain layer stays flat (`providers/`, `views/`). Code only one module uses lives in that module; it goes to `core/` only when it is shared and imports nothing from `app/` or `modules/`. Never create `lib/features/` or `lib/app/modules/`.

### Layer rules

| Layer | May import | Must not import |
| --- | --- | --- |
| `core` | itself, Flutter, plain packages (dio, equatable, ...) | `app/`, `modules/`, `get`, `get_it`, `injectable`, `flutter_bloc`, `bloc`, `flutter_riverpod`, `riverpod` |
| `domain` | itself, `equatable`, `core` | `data/`, `di/`, `flutter`, `get`, `get_it`, `dio`, `flutter_bloc`, `riverpod` |
| `data` | `domain`, `core`, `dio` | presentation, `di/`; never calls `ref.read` or `ref.watch` |
| `presentation` | `domain`, `core`, `flutter_riverpod`, `go_router`, its own module's `di/`, Flutter | `data/` (talk to use cases only) |
| module (any layer) | from `app/` only `routes/`, `shared/`, `theme/`; a `providers/` folder and the module's `di/` folder may also import `app/di/` | the rest of `app/` |
| module `di/` | `data`, `domain`, `core`, `app/di/`, `flutter_riverpod` | nothing in `data` or `domain` imports it |

Conventions that go with them:

- **`Result<T>`** (`core/errors/result.dart`) is `Ok(value)` or `Err(failure)`. `result.fold(onErr, onOk)` takes the failure first. Repositories, datasources, use cases and `DioClient.makeRequest` all return `Future<Result<T>>`. `guard(() async => ...)` wraps a throwing body into a `Result`.
- **`Failure`** subclasses carry `message` and `code`, and both take part in equality. Notifiers and views branch on the type or the code, never on message text.
- **Vocabulary:** folders `datasources`, `repositories`, `usecases`, `entities`, `models`; files `*_usecase.dart`; classes `I*` for abstract repositories and datasources, `*Impl` for implementations, `*UseCase` for use cases. Entities are pure Equatable; JSON lives in models that extend them.
- **Constructor injection everywhere.** Classes take their dependencies as `final` fields. Only the providers (`lib/app/di/`, `modules/<m>/di/`), notifiers and widgets use `ref`; there is no `sl`.
- **Core is plain.** Core classes (`DioClient`, `TokenStore`, ...) know nothing about Riverpod. The app layer injects behaviour into them, for example `AppInterceptors.onUnauthorized` is set in `AppInitializer`, so a 401 never reaches into a notifier from core.
- **Endpoints belong to the datasource** that calls them, not to `ApiConstants`.
- **Repositories check connectivity first** with `INetworkInfo` and return `Err(NetworkFailure())` when offline, for calls that need the network. Fetchr has no backend of its own, so the probe hits `https://connectivitycheck.gstatic.com/generate_204` and any HTTP answer counts as online. Which calls check is listed under "Deviations from the module recipe".
- **Logging:** only `AppLogger` (`debug`, `info`, `warning`, `error`). It redacts tokens, bearer headers, JWTs and coordinates. Never log tokens or PII. Exception messages reach Sentry unredacted: never put a token or a response body in an exception message. `print`, `debugPrint` and `dart:developer` are banned outside `lib/core/logging`.
- **Imports:** relative inside `lib/` (`prefer_relative_imports`, `directives_ordering`); `package:grabby/...` from `test/` and `tool/`. A relative `../lib/` path from a test loads a second copy of the library.
- **Comments:** only a non-obvious why. No banners, no doc comments that restate the code.
- **Size:** no file over 800 lines (aim for under 250).

### Architecture gates

`tool/ci/arch_gates.py` enforces the table above. It reads the package name from `pubspec.yaml` and the state management from its dependencies (`get` is getx, `flutter_bloc` is bloc, `flutter_riverpod` is riverpod), and drops or adapts the gates that only make sense for one of them.

| Gate | Rule |
| --- | --- |
| G-core | `core` imports nothing from `app/` or `modules/` |
| G-core-neutral | `core` imports no get, get_it, injectable, flutter_bloc, bloc, flutter_riverpod, riverpod |
| G1 | `domain` imports nothing from `data/` or `di/` |
| G2 | `domain` imports no Flutter, GetX, GetIt, Dio, Bloc or Riverpod |
| G3 | module `presentation` imports nothing from `data/` |
| G4 | `data` imports nothing from `presentation/` or `di/` |
| G9 | *getx only.* `bindings/` do not register repositories or datasources |
| G10 | `data` and `domain` never resolve from a service locator: `sl`, `getIt`, `locator`, `GetIt.I`/`GetIt.instance`, `Get.find` (riverpod also `ref.read`, `ref.watch`, `ref.listen`) |
| G-app | modules import only `app/routes`, `app/shared`, `app/theme`; DI-entry folders also `app/di` |
| G-log | no `print`, `debugPrint`, `dart:developer` outside `lib/core/logging` |
| G-size | no lib file over 800 lines |

The DI-entry folders are `providers/` (under `presentation/`) and the module's `di/`. `di/` is the module's wiring layer: it may import `data/` (G3 does not apply to it), and `data/` and `domain/` may not import it (G1, G4).

Existing violations sit in `tool/ci/arch_baseline.json`, counted per gate and file; it starts as `{}`. A new or grown violation fails, and so does a fixed one until `--update-baseline` locks it in, so counts only go down. A gate whose scope matches no file reports `VACUOUS` and passes (for example a gate for a layer the app does not have yet); `--self-test` guards the scopes. Never hand-edit the baseline to let new code through; fix the code. `python tool/ci/arch_gates.py --self-test` checks the gates themselves, including the per-state-management switch.

## Dependency injection

Two different jobs get called "DI", and each state management solves them its own way:

1. **Building the object graph** (Dio, storage, datasources, repositories, use cases).
2. **Providing it to the UI** (controllers, cubits, notifiers) with a lifecycle tied to a screen.

| | getx | bloc | riverpod (this app) |
| --- | --- | --- | --- |
| Object graph | `get_it` (`sl`) + `injectable` | `get_it` + `injectable` | providers |
| UI objects | GetX `Bindings` (`Get.lazyPut`) | `BlocProvider(create: ...)` in `lib/app/routes/` | `Notifier` / `Provider` |
| Package needed | get, get_it, injectable | flutter_bloc, get_it, injectable | flutter_riverpod only |
| Test override | register a fake on `sl`, `Get.put` a fake controller | `sl.registerFactory` a fake | `ProviderScope(overrides: [...])` |

### Riverpod variant (this app): providers are the container, no `get_it`

Riverpod already is a dependency injection container. A provider declares how to build a value and which other providers it needs:

```dart
final fetchMediaInfoUseCaseProvider = Provider<FetchMediaInfoUseCase>(
  (ref) => FetchMediaInfoUseCase(ref.watch(downloaderRepositoryProvider)),
);
```

Providers are lazy, built on first read, cached, and referenced by variable name, so a missing provider is a compile error, not a runtime "not registered". Tests replace any node with `overrideWithValue`, on a `ProviderContainer(overrides: [...])` or on `ProviderScope(overrides: [...])`.

So **adding `get_it` and `injectable` to a Riverpod app is a mistake**: it creates a second container that can disagree with the first, `ref` is not available inside a `get_it` factory so the two graphs cannot depend on each other cleanly, and every test has to override both. This app has no `injection_service.dart`, no `@injectable` annotations, no generated DI file and no `_Probe` smoke test; `build_runner` only runs for `flutter_gen`.

How the layers map:

- **`core` stays plain.** `DioClient`, `TokenStore` and the other core classes take their dependencies in constructors, so the same classes work with any container. `lib/app/di/core_providers.dart` holds one provider per core object (`secureStorageProvider`, `sharedPreferencesProvider`, `internetConnectionProvider`, `appStorageProvider`, `tokenStoreProvider`, `networkInfoProvider`, `dioProvider`, `dioClientProvider`, `fetchrHostApiProvider`).
- **A module's graph lives in the module.** `modules/<m>/di/<m>_providers.dart` declares the repository and use-case providers (plus a datasource provider in a module that has one), for example `Provider<IDownloaderRepository>((ref) => DownloaderRepositoryImpl(ref.watch(fetchrHostApiProvider), ref.watch(networkInfoProvider), api.downloads))`. It imports the core providers from `lib/app/di/core_providers.dart`, which is why `di/` may import `app/di` (G-app) and `data/` (it is the wiring layer, so G3 does not apply). Nothing in `data/` or `domain/` imports it (G1, G4), and they never call `ref` (G10).
- **`presentation/providers/` holds the screen's notifier.** `LibraryNotifier extends AsyncNotifier<List<LibraryItem>>` is exposed as `libraryNotifierProvider = AsyncNotifierProvider.autoDispose<LibraryNotifier, List<LibraryItem>>(...)`. `build()` reads the use case through `ref.watch(getLibraryUseCaseProvider)` and returns the items, or throws the `Failure`. The view `ref.watch`es the `AsyncValue` and switches on it: `AsyncData` is the list (or `EmptyView`), `AsyncError` is `ErrorView` (a `Failure` shows its `message`, anything else `ErrorMessages.unexpected`), anything else is loading. Retry is `ref.invalidate(libraryNotifierProvider)`; pull-to-refresh calls `refresh()`, which keeps the previous list on screen while it reloads.
- **Failures are retried by hand.** Riverpod 3 retries a failed provider up to ten times with backoff, which would hold the screen on loading before the error shows. `libraryNotifierProvider` passes `retry: (_, _) => null`; do the same for a notifier whose error is a `Failure` the user can retry.
- **Code outside the widget tree** (an interceptor hook; never code running in another isolate, which has no container) uses the one `ProviderContainer` that `bootstrap()` creates before `runApp`. `AppInitializer.init(container)` takes it and the app gets it through `UncontrolledProviderScope`, which is the Riverpod counterpart of `sl`.
- **Unexpected errors are reported.** Riverpod catches what a provider throws, so the zone hooks never see it. A `Failure` thrown from `build()` is state the view shows; anything else is a bug, and `ProviderErrorObserver` (`lib/app/bootstrap/`, installed on the container in `bootstrap()`) forwards it to `CrashReporting.recordError`.
- **The router is a provider.** `routerProvider` (`lib/app/routes/app_router.dart`) builds the one `GoRouter`: a `StatefulShellRoute.indexedStack` with the Home, Downloads, Library and Settings tabs inside `AppShell` (`lib/app/shell/`), plus the top-level `AppRoutes.player`. `App` watches it. A test builds its own with `AppRouter.create()`.
- **App-wide state** such as the theme mode and the download preferences is a `NotifierProvider` (`themeModeProvider`, `downloadPrefsProvider`); `AppInitializer` awaits their `load()` before `runApp`. They are not in the smoke test `_graph`, which lists only the `final xProvider =` declarations under `di/`.
- **The smoke test is a guard.** `test/app/di/providers_smoke_test.dart` builds a `ProviderContainer` with only the platform edges faked, reads every provider listed in its `_graph`, and fails when that list differs from the `final xProvider =` declarations in `lib/app/di/` and `lib/modules/*/di/`. Declare providers at top level in that shape so it can see them.

The Bloc variant keeps `get_it` + `injectable` for the graph because Bloc has no container of its own: `RepositoryProvider` / `BlocProvider` are widget-tree scoped and cannot reach non-widget code.

## Add a module

For a feature `orders`:

1. **Folders:** `lib/modules/orders/{data/{datasources,models,repositories},domain/{entities,repositories,usecases},di,presentation/{providers,views/widgets}}`.
2. **Domain:**
   - `entities/order.dart`: `class Order extends Equatable`, no JSON.
   - `repositories/i_orders_repository.dart`: `abstract interface class IOrdersRepository { Future<Result<List<Order>>> getOrders(); }`.
   - `usecases/get_orders_usecase.dart`: `class GetOrdersUseCase implements BaseUseCase<List<Order>, NoParams>`; constructor takes the repository.
3. **Data:**
   - `models/order_model.dart`: `OrderModel extends Order` with `fromJson` / `toJson`.
   - `datasources/orders_remote_datasource.dart`: `IOrdersRemoteDataSource` plus `class OrdersRemoteDataSourceImpl`, calling `DioClient.makeRequest(path: 'orders', converter: ...)`. The path lives here.
   - `repositories/orders_repository_impl.dart`: `OrdersRepositoryImpl` takes the datasource and `INetworkInfo`, returns `Err(NetworkFailure())` offline.
4. **Providers:** `di/orders_providers.dart` declares `ordersRemoteDataSourceProvider`, `ordersRepositoryProvider` and `getOrdersUseCaseProvider`, each a top-level `final xProvider = Provider<Interface>((ref) => Impl(ref.watch(...)))` that reads core objects from `lib/app/di/core_providers.dart`.
5. **Presentation:**
   - `providers/orders_notifier.dart`: `class OrdersNotifier extends AsyncNotifier<List<Order>>`; `build()` calls the use case through `ref.watch(getOrdersUseCaseProvider)` and returns the value or throws the `Failure`; `refresh()` does `ref.invalidateSelf()` then awaits `future`, catching so a failed reload stays in state. Expose it as `final ordersNotifierProvider = AsyncNotifierProvider.autoDispose<OrdersNotifier, List<Order>>(OrdersNotifier.new, retry: (_, _) => null)`. Check `ref.mounted` after an `await` before writing `state`. Never build widgets or dialogs in a notifier.
   - `views/orders_view.dart`: a `ConsumerWidget` that `ref.watch`es the provider and switches on the `AsyncValue` using `LoadingView`, `ErrorView(onRetry: () => ref.invalidate(ordersNotifierProvider))`, `EmptyView`. An `AsyncData` that is also loading is a refresh: keep the list. Leaves go in `views/widgets/`.
6. **Route:** add `static const orders = '/orders';` to `AppRoutes` and a `GoRoute(path: AppRoutes.orders, builder: (_, _) => const OrdersView())` to `AppRouter.create`; navigate with `context.go(AppRoutes.orders)` (replaces the stack) or `context.push(AppRoutes.orders)` (adds to it).
7. **Tests** at the mirrored path under `test/modules/orders/{data,domain,presentation}/`: model JSON round trip, repository (offline gives `NetworkFailure`, online delegates), use case, notifier (loading to loaded, loading to failed, refresh, on a `ProviderContainer` with the use-case provider overridden), view (each state renders, retry reloads), and one `_graph` entry per new provider in `providers_smoke_test.dart`. Use `mocktail` and `test/support/`: mocks go in `mocks.dart` (one per repository and use case) and entity builders in `fixtures.dart`; add to them instead of declaring a private copy in a test file.
8. **Verify:** `bash tool/check.sh full`.

A module backed by the native layer (downloader, library, settings) has no datasource or model files in step 3 and no datasource provider in step 4; see "Deviations from the module recipe" under Native layer.

## Native layer

Every download runs in Kotlin: `youtubedl-android` 0.18.1 bundles yt-dlp, ffmpeg and aria2c, and the app calls it from `android/app/src/main/kotlin/com/defo/fetchr/` (package `com.defo.fetchr`). Native owns the task list and persists it; Flutter is a view onto it and never merges state. Dart reaches native only through the generated pigeon client in `lib/core/platform/`.

### Pigeon contract

- **Schema:** `pigeons/fetchr_api.dart`. It writes `lib/core/platform/fetchr_api.g.dart` and `android/app/src/main/kotlin/com/defo/fetchr/pigeon/FetchrApi.g.kt` (Kotlin package `com.defo.fetchr.pigeon`, error class `FetchrError`).
- **Generate:** `fvm dart run pigeon --input pigeons/fetchr_api.dart`, then `fvm dart format lib/core/platform/fetchr_api.g.dart`. Both generated files are committed and never hand-edited; rerun this command instead. `tool/check.sh full` does not regenerate pigeon output, so after any schema change rerun the command and commit both files.
- **Channel names carry the Dart package name** (`dev.flutter.pigeon.grabby.*`, from `dartPackageName: 'grabby'`). Renaming the package means regenerating, and `DOWNLOADS_CHANNEL` in `MainActivity.kt` must match.
- **Host API `FetchrHostApi`:** `fetchInfo`, `enqueue`, `cancel`, `retry`, `remove`, `listLibrary`, `deleteFromLibrary`, `share`, `openFile`, `openFolder`, `pickVideo`, `convertToMp3`, `updateYtDlp`, `ytDlpVersion`. `pickVideo` is `@async` and returns the picked video's uri, or null when the user backs out: the photo picker (`android.provider.action.PICK_IMAGES`, no permission) on API 33, and on API 30 to 32 with the system update that brings it, else `ACTION_OPEN_DOCUMENT`; it persists read access when it can, so a retry after a restart still reads the video. `convertToMp3(uri, folder)` is `@async` and queues an MP3 task whose `url` is that `content:` or `file:` uri (see `LocalVideo.kt`). `remove` and `deleteFromLibrary(uri)` are `@async` and return a `bool`; `deleteFromLibrary` deletes one MediaStore item through `MediaLibrary.deleteFile` and returns false when the user declines the dialog; once the file is gone it also drops the completed task that saved it (`DownloadRepository.forgetSaved`), so Downloads and Home's Recent forget it too. For a completed task with a `savedUri`, `remove` deletes the MediaStore file first (without a consent dialog, a file already gone counts as deleted), then the task, and returns false with the task kept when the user declines the system delete dialog. `openFolder(uri)` is `@async` and returns nothing: it opens the folder holding that MediaStore item (`Movies/<folder>`, `Music/<folder>` or `Pictures/<folder>`) in the Files app, and throws `no_folder_app` when the item has no row or no app can open it; Android cannot highlight the file itself. `awaitLaunchSplash()` is `@async` and completes once the Android 12+ launch splash has played its icon animation and gone (at once below Android 12, and when the activity is destroyed); `LaunchIntro` bounds the wait at 1.2 s, because no exit listener fires when the system shows no splash. `@async` methods are generated as Kotlin `suspend fun`s that `setUp` launches on `Dispatchers.Main`, so blocking work goes in `withContext(Dispatchers.IO)`.
- **Event channel `FetchrEvents.downloads()`** is the top-level Dart function `downloads()`. It emits the full `DownloadsSnapshot` on listen and on every change, at most one per 250 ms. The generated factory opens a new `EventChannel` on each call, so the repository calls it once.
- **Types:** a Dart `int` arrives in Kotlin as `Long` and a `double` as `Double`. `progress` is 0..1, with -1 meaning unknown (starting, merging, and an MP3 conversion until ffmpeg's first report); `etaSeconds` is -1 when unknown. The pigeon classes share names with the domain entities (`DownloadRequest`, `DownloadTask`, `LibraryItem`, `PlaylistEntry`, `Quality`, `TaskStatus`), so data files import the generated file with a prefix: `import '../../../../core/platform/fetchr_api.g.dart' as api;`.

Native throws `FetchrError(code, message, null)`, which Dart receives as `PlatformException(code: ...)`. `failureFrom` in `core/errors/failure_mapper.dart` has a `PlatformException` arm that calls `failureFromCode`, so `guard()` maps every pigeon call. A failed task carries the same string in `DownloadTask.errorCode`, a `String?` and not an enum, and the repository passes it straight to `failureFromCode`. The raw yt-dlp line in `errorMessage` reaches the domain task only for an `unknown` failure.

| Code | Failure | When |
| --- | --- | --- |
| `unsupported_site`, `invalid_url` | `UnsupportedSiteFailure` | yt-dlp has no extractor, or the URL is not `http(s)` |
| `private_video` | `PrivateVideoFailure` | private, age-gated, members-only, needs sign-in |
| `unavailable` | `MediaUnavailableFailure` | removed, geo-blocked, 404 |
| `network` | `NetworkFailure` | DNS, timeout, connection reset |
| `no_storage` | `StorageFailure` | disk full or write denied |
| `busy` | `YtDlpBusyFailure` | `updateYtDlp` while a download or info fetch runs |
| `no_folder_app` | `UnexpectedFailure(ErrorMessages.noFolderApp)` | `openFolder` when the item has no row or no app can open the folder |
| `unknown`, anything else | `UnexpectedFailure(ErrorMessages.downloadUnknown)` | the native `message` is the last yt-dlp `ERROR:` line |

### Kotlin classes

| File | Role |
| --- | --- |
| `FetchrApp.kt` | `Application`: starts `YtDlp`, owns the one `DownloadRepository` (`FetchrApp.downloads`) |
| `YtDlp.kt` | Init gate (`ready`) for YoutubeDL, FFmpeg and Aria2c; `run` counts active runs; `update` and `version`; the daily update check |
| `MainActivity.kt` | Registers `FetchrHostApi` and the downloads stream, unregisters both in `cleanUpFlutterEngine`; `launchIntentSender` for MediaStore consent dialogs; `launchForResult` for the video picker; on Android 12+ holds the splash until its icon animation ends, removes it, restores the system bars and completes `awaitLaunchSplash` |
| `PlatformApi.kt` | `HostApi` (the `FetchrHostApi` implementation) and `DownloadsStream`; every exception is mapped through `ErrorClassifier` into a `FetchrError`; the stream sends from the main thread |
| `DownloadRepository.kt` | `StateFlow` of tasks (newest first), at most two downloads at once, a temp dir per task (stale ones are cleared on its IO scope at startup), cancel, retry, remove, `savedUri` (a completed task's saved file, null otherwise), JSON persistence on every status change except queued to running; `isLive` is the one queued-or-running test; a progress tick under 0.5% with the same ETA is dropped; while an MP3 with a known duration converts it reads ffmpeg's report every 500 ms (`withConversion`); an MP3 task saves only its `.mp3` |
| `DownloadService.kt` | The foreground service |
| `DownloadNotifications.kt` | "Downloaded" and "Download failed" notifications |
| `MediaLibrary.kt` | Save, list, delete, share and open through MediaStore; `save` takes a `MediaKind`, `viewIntent` is shared with the notifications; `list` returns videos and audio only; `deleteFile` deletes one uri and tells gone from declined, and is the one delete behind `remove` and `deleteFromLibrary`; `openFolder` opens the item's folder in the Files app or throws `no_folder_app` |
| `FolderPath.kt` | Pure: a MediaStore `RELATIVE_PATH` (API 29+) or legacy `DATA` path (API 26 to 28) to the `primary:<folder>` document id that `openFolder` opens; null outside the external root |
| `MediaKind.kt` | Pure: `MediaKind` (video, audio, image) with its mime prefix and default mime, and `Quality.mediaKind` (mp3 is audio, cover is image, the rest video); the one place a quality becomes a kind |
| `SplashHold.kt` | Pure: how long the splash icon animation still runs; 0 without an animated icon, capped at 1000 ms |
| `RequestBuilder.kt` | Pure: yt-dlp arguments, URL check, folder and file name sanitising; `convert` for a local video; `Quality.shortSideCap` is the one cap table |
| `LocalVideo.kt` | A video on the device as an MP3 task: the picker intent, the request (name and duration from the uri), and `stage`, which copies the video into the task dir under the name yt-dlp would save it as, so yt-dlp finds it "already downloaded", only converts it and deletes the copy |
| `InfoParser.kt` | Pure: `-J --flat-playlist` JSON to `VideoInfo`; `options` is one `FormatOption` per quality with the dimensions, frame rate and size of what yt-dlp would download |
| `ErrorClassifier.kt` | Pure: exception or yt-dlp stderr to an error code and a message |
| `TaskCodec.kt` | Pure: task list to and from JSON |
| `Json.kt` | Pure: the `JSONObject.str` and `num` extensions |

- **URLs are checked natively.** `RequestBuilder.requireHttpUrl` is the trust boundary: a URL starting with `-` would be read by yt-dlp as an option. The Dart `extractUrl` only helps the paste box.
- **Request shape.** Every download passes `--no-playlist --no-mtime --cache-dir`, `-N 4` and an output template under the task's temp dir. `-N 4` (`--concurrent-fragments`) only parallelises HLS and DASH fragments, because aria2c takes only http(s) and ftp(s) files since yt-dlp 2026.06.09; it does nothing for single files and covers and applies with or without aria2c. 4 keeps two tasks to at most 8 requests at a server (a benchmark showed no gain past about 10). Video uses `-f bv*+ba/b` with `-S res:<cap>,vcodec:h264,acodec:aac` (`-S res,...` for best) and `--merge-output-format mp4`; the cap comes from `Quality.shortSideCap` (1080, 720, 480) and yt-dlp's `res` is the smaller of width and height, so a portrait 1080x1920 clip counts as 1080p. MP3 uses `-x --audio-format mp3 --audio-quality 0` and `--postprocessor-args "ExtractAudio+ffmpeg:-progress <task dir>/ffmpeg.progress"`: yt-dlp keeps ffmpeg's output to itself, so ffmpeg's report file is the only progress while it converts (out_time over the request's duration; unknown without one); a local video (`LocalVideo`) runs the same MP3 options through `RequestBuilder.convert`, which adds `--enable-file-urls` for that request only; cover uses `--skip-download --write-thumbnail --convert-thumbnails jpg`, which leaves one `.jpg` in the task dir for the largest-file pick in `DownloadRepository`; aria2c adds `--downloader libaria2c.so` and one `--downloader-args "aria2c:--summary-interval=1 --ca-certificate=<cert>"` (the library sends those two separately and yt-dlp keeps only the last, which would drop the interval and the progress lines). aria2c is skipped for YouTube hosts (youtube.com and subdomains, youtu.be, youtube-nocookie.com, matched on the parsed host), even with "Faster downloads" on: yt-dlp's maintainers strongly discourage it there, and YouTube throttles requests over 10 MB, which the native downloader avoids with 10 MiB chunks.
- **Options and sizes.** `fetchInfo` returns `VideoInfo.options`, the one list the quality picker shows. For a single video `InfoParser` picks the stream yt-dlp would pick for best, 1080p, 720p and 480p: video formats with a width and a height, the largest short side within the cap (or the smallest one above it when none fits), then yt-dlp's own order for `-S vcodec:h264,acodec:aac`: the video codec closest to h264 (h264, then the older codecs, then h265, vp9, av1), the audio codec closest to aac (so a progressive stream beats a video-only one of the same codec), then higher frame rate, larger size and higher bitrate. A tier whose pick has the short side of an earlier option is dropped. A video-only pick adds the best audio stream (`mp4a` first, then bitrate), and the size is the sum of the parts: `filesize`, else `filesize_approx`, else `tbr` times the duration, with `sizeIsEstimate` set when any part was not exact and the size left null when any part has none. MP3 is offered when an audio or progressive stream exists (its size is the best audio stream's, always an estimate), and cover when the info has a thumbnail (its size comes from the matching `thumbnails` entry, if any). A playlist, or a video with no `formats`, gets best, 1080p, 720p, 480p and MP3 without metadata (and no cover for a playlist); video formats without dimensions give best and MP3.
- **Android's `org.json` returns `"null"` for JSON null** from `optString`; read optional strings through the `str` extension in `Json.kt`, which checks `isNull` first, as `InfoParser.kt` and `TaskCodec.kt` do.
- **Kotlin changes need a rebuild and reinstall.** Hot reload and hot restart do not reach them.
- **Packaging.** `useLegacyPackaging = true` in `android/app/build.gradle.kts` extracts libpython, ffmpeg and aria2c so they can run from `nativeLibraryDir`. `android/app/proguard-rules.pro` keeps `com.yausername.**` and `org.apache.commons.compress.archivers.zip.**` under R8; Flutter's Gradle plugin picks the file up.

### Foreground service and notifications

- **`DownloadService`** is a started service, not a bound one. `DownloadRepository.enqueue` starts it. It calls `startForeground` with `FOREGROUND_SERVICE_TYPE_SPECIAL_USE` on API 34+ (the manifest declares `foregroundServiceType="specialUse"` plus the subtype property, and `specialUse` has no Android 15 timeout), holds a partial WakeLock while it runs, and stops itself when no download is active.
- **Progress notification:** channel `downloads` (`IMPORTANCE_LOW`), ongoing, `setOnlyAlertOnce`, indeterminate while progress is below 0, one "Cancel all" action through `PendingIntent.getService`. `onTimeout` cancels everything. The service is `START_NOT_STICKY`: a killed process does not resume downloads, and the interrupted tasks load as failed with the message "Interrupted", so the user retries them.
- **Result notifications:** `DownloadNotifications.finished` runs on every transition to completed or failed, on channel `download_results` (`IMPORTANCE_DEFAULT`, auto-cancel). A completed tap opens the saved file with `ACTION_VIEW`; a failed tap opens the app; a cancelled task posts nothing. It skips silently when `POST_NOTIFICATIONS` is not granted. All of this is native and works with the app closed; there is no Flutter notification plugin.
- **Permissions** are declared in `AndroidManifest.xml` and requested from Dart by `AppInitializer` after the first frame (notification, storage, videos, audio). Denial is fine: downloads still run and Android 10+ saves without storage access.

### MediaStore locations

- **Android 10+ (API 29+):** `MediaLibrary.save` inserts, by `MediaKind`, into `MediaStore.Video.Media` (`Movies/<folder>`), `MediaStore.Audio.Media` (`Music/<folder>`) or `MediaStore.Images.Media` (`Pictures/<folder>`, for a cover), on `VOLUME_EXTERNAL_PRIMARY`, with `IS_PENDING=1` while it copies and `0` after; a failed copy deletes the row. No storage permission is needed.
- **Android 8 to 9 (API 26 to 28):** copies into the public `Movies`, `Music` or `Pictures` directory (a " (n)" suffix on a name clash) and runs `MediaScannerConnection`. This needs `WRITE_EXTERNAL_STORAGE`, declared with `maxSdkVersion` 28.
- **Listing** reads the same relative paths for videos and audio; covers are saved but never listed. Files from an earlier install need `READ_EXTERNAL_STORAGE` (max 32) or `READ_MEDIA_VIDEO` and `READ_MEDIA_AUDIO`.
- **Delete** tries `ContentResolver.delete`. For files the app does not own it asks for consent: `MediaStore.createDeleteRequest` on API 30+, or the `RecoverableSecurityException` intent sender on API 29, both through `MainActivity.launchIntentSender`. `HostApi.remove` and `HostApi.deleteFromLibrary` both go through `MediaLibrary.deleteFile`. Removing a completed download deletes its file first, and the task stays when the user declines the dialog (the dialog's answer is final: an unowned row is invisible to the app's own query, so `deleteFile` never re-checks existence after a consent request). Without a dialog a file that is already gone, or a uri that is neither MediaStore nor `file:`, counts as deleted. A `file:` uri (API 26 to 28, when the media scan fails) is deleted with `File.delete()`, and the task stays when that fails.
- **Open folder** reads the item's `RELATIVE_PATH` (API 29+) or the parent of `DATA` (API 26 to 28; a `file:` uri uses its own path) and starts `ACTION_VIEW` on `DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:<folder>")` with the directory mime type, which the Files app resolves. Primary volume only. A missing row or `ActivityNotFoundException` throws `FetchrError("no_folder_app", ...)`.
- **The default folder is `Fetchr`.** `RequestBuilder.safeFolder` strips `\ / : * ? " < > |` and leading dots and falls back to `Fetchr`; the Settings dialog rejects the same characters.

### yt-dlp updates

- **Init:** `FetchrApp.onCreate` calls `YtDlp.start`, which initialises YoutubeDL, FFmpeg and Aria2c on an IO scope. Every run awaits `YtDlp.ready`, so an init failure shows up as an `unknown` error on the first call.
- **Daily update:** after init, `YtDlp` updates yt-dlp from the stable channel when 24 hours have passed. The timestamp lives in the `fetchr_native` SharedPreferences and is written only after a successful update; a failure is logged, never fatal, and retried at the next start.
- **Manual update:** Settings calls `updateYtDlp` (Dart checks connectivity first). The update swaps the zipapp in place, so it throws `busy` while any run is active and new runs wait until it finishes. When downloads start failing as `unknown`, update yt-dlp first.

### JVM unit tests

```bash
cd android && ./gradlew :app:testDebugUnitTest   # Windows: gradlew.bat
```

Tests live in `android/app/src/test/kotlin/com/defo/fetchr/`: `RequestBuilderTest`, `InfoParserTest`, `ErrorClassifierTest`, `TaskCodecTest`, `MediaKindTest`, `FolderPathTest`, `ProgressChangedTest`, `RunGateTest` and `SplashHoldTest`. The `InfoParser` fixtures are in `android/app/src/test/resources/info/`; capture new ones with `uvx --from "yt-dlp==<version>" yt-dlp -J --no-playlist <url>` (`--flat-playlist` for a playlist) and trim them to the keys the parser reads, with the title and uploader replaced by neutral text. `tiktok_vertical.json` is the portrait case. `org.json:json` is a test dependency because the `org.json` in `android.jar` is a stub on the JVM. Only the pure classes have JVM tests; the classes that need Android (`DownloadRepository`, `DownloadService`, `MediaLibrary`, `MainActivity`) are checked on a device. `tool/check.sh` does not run Gradle, so run this command by hand after touching Kotlin, and never alongside a Flutter build.

### Deviations from the module recipe

The downloader, library and settings modules differ from "Add a module" because their data source is the native layer, not an HTTP API.

- **Repositories take the generated `FetchrHostApi`** (`api.FetchrHostApi`, from `fetchrHostApiProvider`) as a constructor argument. There is no `datasources/` folder and no `models/` folder: the pigeon classes are the DTOs, and each repository holds private mapper functions from them to the domain entities. Entities stay pure Equatable. Use cases stay one per operation.
- **The generated client sits in `core/platform/`.** It is plain Dart with no Riverpod, so core stays neutral; the app layer provides it in `lib/app/di/core_providers.dart`.
- **`app/shared/` holds what several modules read:** the `Quality` entity and `downloadPrefsProvider` (`DownloadPrefs`: quality, folder, aria2c). Downloader reads them for new downloads, library for the folder and settings edits them. They are persisted through `appStorageProvider` under `StorageKeys.defaultQuality`, `saveFolder` and `useAria2c`, and loaded in `AppInitializer`. The provider is not in the smoke test `_graph`, like `themeModeProvider`.
- **Connectivity is checked only for network-bound calls:** `fetchInfo` and `updateYtDlp`. Enqueue, cancel, retry, remove, `openFolder`, `pickVideo`, `convertToMp3`, library calls and `ytDlpVersion` are local and never return `NetworkFailure` from the probe. The probe is `https://connectivitycheck.gstatic.com/generate_204`, and any HTTP answer counts as online.
- **Native error codes live in `core/errors`:** the five failures, `failureFromCode` and the `PlatformException` arm of `failureFrom`. A repository only wraps its call in `guard()`.
- **The task list is a stream, not a request.** `DownloadsNotifier` is a `StreamNotifier` over `watchTasks()`, with `retry: (_, _) => null`. The notifier does no merging.
- **Repository tests fake the host API:** `class _MockApi extends Mock implements api.FetchrHostApi`, with `INetworkInfo` mocked next to it. View tests pump the real router through `test/support/fake_app.dart`, which overrides the three repository providers.
- **The demo `home` module is gone.** `AppRoutes` has `home`, `downloads`, `library`, `settings` and `player`.

## Theming and rebrand

`lib/core/theme/app_colors.dart` is the rebrand file. Change `AppColors.seed` and light, dark, tokens and every widget follow. `error` stays red for any brand.

- `AppColors.lightScheme` / `darkScheme` are `ColorScheme.fromSeed`. `AppTokens` (a `ThemeExtension`) derives every role (`background`, `surface`, `card`, `panel`, `sheet`, `divider`, `border`, `hint`, `textPrimary`, `textSecondary`, `success`, `warning`, `errorTint`) from the scheme.
- Read colours through `context.tokens`, `context.colors`, `context.text`, `context.isDark` (`theme_extensions.dart`). **Never branch on brightness by hand** (`isDark ? a : b`) at a call site.
- A new colour role is a field on `AppTokens` (constructor, `fromScheme`, `copyWith`, `lerp`), not a one-off colour in a widget. One accent per status; do not re-derive shades per widget.
- **`const` freezes colours.** A `const` node whose colour comes from the theme will not flip between light and dark; drop `const` there.
- `Card` paints `colorScheme.surface` plus an elevation tint in Material 3; `AppTheme` pins cards with `CardThemeData(color: tokens.card, surfaceTintColor: Colors.transparent)`. Do not repaint a card's surface inside a `Card`.
- Dark mode is `themeModeProvider` (a `Notifier<ThemeMode>`, persisted under `StorageKeys.themeMode` and loaded in `AppInitializer` before the first frame); `ThemeModeButton` cycles system, light, dark.
- Rebranding does not touch the launcher icon, the native splash or the app name. The icon and the splash are Android resources in `android/app/src/main/res`, vectors only (minSdk 26 needs no PNGs and no `flutter_launcher_icons` / `flutter_native_splash`):
  - **Icon:** the adaptive `mipmap-anydpi-v26/ic_launcher.xml`, a `ic_launcher_background` colour under `drawable/ic_launcher_foreground.xml`, which is also the monochrome layer for Android 13 themed icons. Keep the glyph inside the 66 dp safe zone of the 108 dp canvas.
  - **Splash:** `drawable/splash_icon.xml`, the Home header logo tile at 4x on a 288 dp canvas, kept inside the 192 dp circle Android 12+ masks it to. `LaunchTheme` shows it through `windowBackground` (`drawable/launch_background.xml`, Android 8 to 11; transparent system bars so it centres like the edge-to-edge Flutter window). Android 12+ plays `drawable/splash_icon_animated.xml` instead: the arrow drops into the tile and the tray draws out, 800 ms, which `windowSplashScreenAnimationDuration` must equal; its first frame is the declared vector and its last frame must equal `splash_icon.xml`. Never set `windowSplashScreenIconBackgroundColor`: it shrinks the tile. The colours are in `values/colors.xml` and `values-night/colors.xml`; `test/app/launch/launch_splash_colors_test.dart` keeps them equal to `launchSplashColors`.
  - **Launch intro:** `LaunchIntro` (`lib/app/launch/`, wired by `App.splashGone` from `bootstrap`) draws the splash's last frame, a 120 logical px tile in the centre in the system brightness's colours, waits for `awaitLaunchSplash`, fades in the tagline "Any link. Any format." word by word under it, then flies the tile onto the Home header tile (`LaunchLogoTarget` in `app/shared` hands it the key) while the colours become the in-app theme, then fades. Reduce motion skips the flight; with no header on screen the tile fades. Tests pump `App` or `MaterialApp` without `splashGone`, so they never see it.
  - **Glyph copies:** `assets/icons/logo.svg`, `drawable/ic_stat_fetchr.xml`, `ic_launcher_foreground.xml`, `splash_icon.xml` and `splash_icon_animated.xml` draw the same path; a new logo changes all five.
  - **Name:** `android:label` in `AndroidManifest.xml`, `CFBundleDisplayName` in `ios/Runner/Info.plist` and `Environment.appName`.

A loading skeleton is the real layout over placeholder data inside skeletonizer's `Skeletonizer` (the format sheet does this), with `ShimmerEffect(baseColor: tokens.surfaceSunken, highlightColor: tokens.shimmer)`, and `SolidColorEffect` under reduce motion, which the package does not read. Shared widgets live in `core/widgets` (`AppText`, `AppButton`, `AppBackButton`, `AppIconButton`, `AppTextField`, `LoadingView`, `ErrorView`, `EmptyView`, `NotFoundView`, `AppSnackbar`, `SheetDragHandle`, `AudioTile` in `media_thumb.dart`, `confirmDeleteFile` in `confirm_dialog.dart`, `runUndoableDelete` in `undoable_delete.dart`); use them before hand-rolling. `AppSnackbar.showUndo(context, message)` shows a five-second Undo snackbar and resolves true only when Undo is tapped. `runUndoableDelete` hides the item, shows that snackbar, and when it closes any other way runs `commit`; a `false` or an `Err` restores the item, and an `Err` shows its message. It reads the root navigator's context before `hide()` because hiding usually unmounts the caller's tile. Bottom sheets go through `showAppBottomSheet` (`core/utils/widget_utils.dart`), never `showModalBottomSheet` directly.

## Environment

This app has no flavors: one app id and one display name. There is no `flavorizr.yaml` and no flavor Gradle or Xcode config, so commands run without `--flavor`. `Environment.current` (`lib/core/config/environment.dart`) always returns `prod`; set the app name there. Every environment-dependent value reads `Environment.current` or `ApiConstants.baseUrl`, so adding flavors later changes no call site. Fetchr has no backend: `DioClient` and `ApiConstants.baseUrl` are scaffold leftovers that no module calls, and every download goes through the native layer.

## Crash reporting and Sentry

`CrashReporting` (`core/crash/`) logs every error through `AppLogger` and then fans it out to every registered `CrashReporter` (today only `SentryReporter`). `bootstrap()` hooks `FlutterError.onError` and `PlatformDispatcher.instance.onError` to `CrashReporting.recordUncaught`, which skips reporters whose `capturesUncaught` is true so Sentry does not report twice. Errors thrown inside providers never reach those hooks; `ProviderErrorObserver` forwards the non-`Failure` ones to `CrashReporting.recordError`.

Sentry is on for every build, debug included: the DSN is set in `SentryFlutter.init` in `lib/app/bootstrap/bootstrap.dart`. A DSN ships inside the app binary anyway, so committing it is fine; it only lets someone send events to the project. The environment tag is `prod`.

## Responsive sizing

`flutter_screenutil` with design size 375x812. Widgets get `.w`, `.h`, `.sp`, `.r` from `lib/core/utils/scale.dart` and never import screenutil directly. `ScaleScope` (the `ScreenUtilInit` wrapper `App` and the test harnesses use) and the extensions both live there.

## Toolchain pins

Flutter 3.47.7 / Dart 3.13.5 through fvm (`.fvmrc`); `go_router` 18 and `flutter_riverpod` 3.4 are in use; `persistent_bottom_nav_bar_v2` 6.5 caps `go_router` below 19. Do not bump these without checking: `compileSdk` is 37 and `minSdk` is 26 in `android/app/build.gradle.kts` (AGP 9.1, Gradle 9.3.1); `sentry_flutter` is ^10.1 (it needs Flutter 3.44, Dart 3.12 and `minSdk` 26, so Android 7.0 and 7.1 are not supported, and it no longer applies the Kotlin plugin; it pulls `jni` 1.0); `android.builtInKotlin=true` in `android/gradle.properties` is AGP 9's built-in Kotlin, so the app applies no Kotlin plugin and sets the JVM target in the top-level `kotlin { compilerOptions }` block, and `android.newDsl=false` stays as the Flutter template sets it. A plugin that applies `org.jetbrains.kotlin.android` fails the build with "The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support since AGP 9.0" (Flutter wraps it in its "Starting AGP 9+, the default has become built-in Kotlin" box); set the flag back to `false` until that plugin migrates, and the "Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP)" warning then names it; core library desugaring stays enabled in `android/app/build.gradle.kts`; `youtubedl-android` is pinned at 0.18.1 (yt-dlp itself updates daily at run time); `pigeon` ^29 must match the generated files that are committed; keep `environment.sdk` at `^3.11.0` (not the pinned Dart) and run `fvm dart format` so the tall style is stable.

## Pitfalls

- **`ref.watch` in `build`, `ref.read` in callbacks.** A `Notifier` reads its dependencies through `ref` inside `build()` and its methods, and never keeps them in a field assigned in `build()`, which runs again when a watched provider changes.
- **Check `ref.mounted` after an `await`** before writing `state`; the provider may have been disposed or rebuilt meanwhile.
- **An `AsyncValue` can hold a value and be loading or failed at once.** A refresh keeps the previous value, so switch on `AsyncData`, `AsyncError` and test `isLoading` instead of assuming one state excludes the others.
- **Riverpod retries failed providers by default** (ten times with backoff, for anything that is not an `Error`, a `Failure` included). Pass `retry: (_, _) => null` where a Retry button is the intended path, or the screen and the tests sit on loading.
- **An `autoDispose` provider needs a listener.** In a plain `ProviderContainer` test, `container.listen(provider, (_, _) {})` keeps it alive between reads.
- **Declare providers at top level as `final xProvider = Provider...`** in `lib/app/di/` or `lib/modules/*/di/`; the smoke test finds them by that line.
- **Never navigate before the router exists.** `routerProvider` builds the one router and `AppRouter.create()` builds a fresh one for a test. `context.go` replaces the stack, `context.push` adds to it.
- **`.w/.h/.sp/.r` only work below `ScreenUtilInit`.** Not in `main()`, not in eagerly evaluated theme constants. Themes are built lazily (`AppTheme.light()`) for exactly this reason.
- **Route parameters and `extra` can be missing.** Null-guard `state.extra` and parse path parameters defensively before casting.
- **Reset loading flags in `finally`**, not in both the success and the catch path; early returns and rethrows skip the latter.
- **The global `builder` unfocuses on tap and clamps text scaling at 1.3.** A screen that must keep focus on tap (a chat composer) handles it locally; do not remove the global builder.
- **`compute()` converters** (`isIsolate: true` on `makeRequest`) must be top-level or static functions, or capture only sendable values.
- **One `Dio`.** It is a lazy singleton built by `buildDio`; do not construct a `Dio` per request.
- **Equality must see `code`.** `Failure.props` includes it; keep it that way in new subclasses.
- **A doubled slash in an import URI** (`package:grabby//x.dart`) loads a second copy of the library; `tool/check.sh` rejects it.
- **Spell names right.** A typo in a folder or route is baked into every import forever.
- **Generated files are committed** (`*.gen.dart`, `*.g.dart`, `*.g.kt`); `check.sh full` fails when the `build_runner` ones drift from what the generator produces. It does not check the pigeon pair: rerun the pigeon command after a schema change.
