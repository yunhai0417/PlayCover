# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayCover is a Swift/SwiftUI macOS app (Apple Silicon only) that runs iOS apps and games natively on Mac. It wraps iOS IPAs in an iPad-imitating layer, converts Mach-O binaries, injects the PlayTools framework (built locally from a sibling clone of github.com/PlayCover/PlayTools) for graphics/input/keymapping, and re-signs apps with entitlements. GPLv3 licensed.

## Build & Lint

- PlayTools is a **fully local dependency** (never linked at compile time — it is a runtime payload embedded into the app bundle and injected into IPAs):
  - `scripts/build-playtools.sh` builds `PlayTools.xcframework` from the sibling repo `../PlayTools` into `Vendor/` (gitignored; clone PlayCover/PlayTools next to this repo or set `PLAYTOOLS_DIR`).
  - `Vendor/PlayTools.podspec` is a script-only CocoaPods pod that injects the build phase embedding the framework (copy → vtool maccatalyst conversion → deep-framework rebundle). Paths use `PODS_TARGET_SRCROOT` / `PODS_CONFIGURATION_BUILD_DIR` because the phase runs on the pod's aggregate target inside the Pods project.
- After pulling or changing PlayTools: `scripts/build-playtools.sh`, then `pod install` if the Podfile/podspec changed. Build via **`PlayCover.xcworkspace`**. There are **no Debug configurations** — only `Release` and `Nightly`.
- Command-line build: `xcodebuild -workspace PlayCover.xcworkspace -scheme PlayCover -configuration Release build` (requires `Vendor/PlayTools.xcframework` built first).
- SwiftLint runs with `--strict` (zero warnings) on every push/PR via `.github/workflows/SwiftLint.yml`. Run locally with `swiftlint --strict`. Config: `.swiftlint.yml` (note: `force_unwrapping` is opted in).
- **No test targets exist** in this project.
- Releases are built with fastlane (`bundle exec fastlane release` / `nightly`); these require signing certs via `match` and are CI-only.

## Architecture

Standard MVVM: `Model/` (data), `ViewModel/` (ObservableObjects, mostly singletons like `AppsVM.shared`, `InstallVM.shared`, `StoreVM.shared`, `DownloadVM.shared` injected via `.environmentObject` in `Views/PlayCoverApp.swift`), `Views/` (SwiftUI, with AppKit interop — many flows use `NSAlert` and `NSWorkspace`).

### App install/launch pipeline

1. `AppInstaller/Installer.swift` — orchestration: unzip IPA (`Utils/IPA.swift`) → detect native Mac availability → compose entitlements (`Utils/Entitlements.swift`) → resolve/convert Mach-O binaries (`Utils/Macho.swift`: iOS→macOS arch conversion, encryption detection) → inject PlayTools dylib load command (`Utils/PlayTools.swift: installInIPA`) → ad-hoc sign via `codesign` (`Utils/Shell.swift`).
2. `Model/PlayApp.swift` — runtime model of an installed app (subclass of `Model/BaseApp.swift`); `launch()` applies rules checks, version checks, KeyCover unlock, then launches via `NSWorkspace` from the alias dir. Also handles Discord IPC, no-sleep IOKit assertions, and hard-coded PROHIBITED_APPS/MALICIOUS_APPS blocklists.

### Filesystem-based state

Almost all app state lives under `~/Library/Containers/io.playcover.PlayCover/`:
- `Applications/` — installed `.app` bundles (scanned by `AppsVM`); aliases in `~/Applications/PlayCover/`
- `App Settings/<bundleID>.plist` — per-app settings (`Model/AppSettings.swift`, encodes on every `didSet`)
- `Keymapping/<bundleID>/` — per-app keymap `.plist`s (`Utils/Keymapping.swift`, models in `Model/KeymapData.swift`; the in-game overlay itself is rendered by PlayTools, not this app)
- `PlayChain/<bundleID>` — KeyCover-encrypted keychain data (`Utils/KeyCover.swift`, CryptoKit; unlocked before launch, re-locked on quit)
- `Sources.plist` — app store source registry (`ViewModel/StoreVM.swift`)
- `~/.config/PlayCover/` — user rules YAML overrides + PlayTools install (`~/Library/Frameworks/PlayTools.framework`)

### Rules system

`Model/PlayRules.swift` + `Rules/default.yaml`: per-app YAML rules (`blocklist`/`greenlist`/`allow`/`bypass` SBPL snippets, with `${BundleID}` substitution) feed into `Utils/Entitlements.swift: composeEntitlements`. The "bypass jailbreak" per-app toggle gates blocklist/greenlist. TCC bypass entitlements are only added when "PlaySign" is active (`Utils/SystemConfig.swift`: SIP disabled && AMFI boot-arg set — first-run setup UI in `Views/SigningSetupView.swift`).

### Store/sources

`StoreVM` fetches remote JSON sources; `Model/ITunesResponse.swift` uses the iTunes lookup API for metadata; `Utils/GoogleDrive.swift` scrapes Google Drive redirect pages to resolve direct IPA URLs. Downloads go through `AppInstaller/Downloader.swift` into the install pipeline.

### Preferences

Settings panes in `Views/Settings/` use Preferences-style `*Preferences` classes backed by `UserDefaults` (e.g. `InstallPreferences`, `KeyCoverPreferences`).

## Conventions & Gotchas

- Heavy use of `Shell.run` (Foundation `Process`) wrapping system binaries — `codesign`, `unzip`, `xattr`, `csrutil`, `nvram`. Behavior depends on these being present.
- Localization: plain `.lproj/Localizable.strings` files (22 languages, managed via Weblate) with dotted keys like `playapp.add`, used both via `NSLocalizedString` and bare SwiftUI `Text("keymap.title")` literals. Never hardcode user-facing English strings — always use localization keys.
- SwiftLint `--strict` means new code must be warning-free, including no force unwrapping.
- The PlayTools framework is a separate repository; this app only injects and installs it. Changes to runtime in-app behavior (overlay, controls rendering) belong there.
