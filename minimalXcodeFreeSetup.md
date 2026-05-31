## The viable path

Build it as a **Swift Package Manager macOS app**, then have a tiny shell script turn the SwiftPM executable into a real `.app` bundle. No `.xcodeproj`, no opening Xcode, no Xcode UI. This is basically the steipete pattern.

The catch: you can avoid an **Xcode project**, but you cannot avoid an **Apple SDK/toolchain**. SwiftUI and Liquid Glass are Apple SDK APIs. Apple’s current developer release page lists **Xcode 26.5 RC** as of May 4, 2026, and the Xcode 26.5 notes say it includes **Swift 6.3** and SDKs for iOS/iPadOS/tvOS/watchOS/macOS/visionOS 26.5. ([Apple Developer][1]) Apple’s macOS 26 SDK notes also say the macOS SDK comes bundled with Xcode. ([Apple Developer][2])

So the honest target should be:

> **No Xcode project. No Xcode UI. Clone → `./Scripts/run.sh`. Requires either Xcode 26.x or matching Command Line Tools with the macOS 26 SDK installed.**

That is the sweet spot. Trying to make Liquid Glass compile on a machine with only an older macOS 14/15 SDK is not realistic, because `.glassEffect`, `GlassEffectContainer`, and related SwiftUI symbols are SDK symbols. Apple’s docs describe `glassEffect(_:in:)`, `GlassEffectContainer`, and Liquid Glass custom-view adoption in SwiftUI. ([Apple Developer][3])

## What steipete’s repos point to

The best reference is **RepoBar**. Its own repo guidelines say it is a macOS menubar app using **SwiftUI + AppKit**, built with **SwiftPM**, with app bundling/signing handled by `Scripts/*.sh`; the dev commands are wrapped by `pnpm`, but the core build is `swift build`. ([GitHub][4]) RepoBar’s spec explicitly says **Swift 6.2, Xcode 26**, and its `Package.swift` uses `swift-tools-version: 6.2`, platform declarations, SPM dependencies, and an executable target rather than an Xcode project. ([GitHub][5])

**Trimmy** is an even cleaner reference for the packaging shape: `Package.swift` declares a SwiftPM executable app target and dependencies like Sparkle, KeyboardShortcuts, and MenuBarExtraAccess. ([GitHub][6]) Its `package_app.sh` does the important stuff: resolve/build via SwiftPM, create `MyApp.app/Contents/...`, write `Info.plist`, copy the executable, set `LSMinimumSystemVersion`, set `LSUIElement`, and sign/package. ([GitHub][7])

**CodexBar** is useful as a warning: once you add Widgets/AppIntents-style things, packaging can drift back into `xcodebuild` territory; its script invokes `xcrun`, `appintentsmetadataprocessor`, and `xcodebuild` for widget metadata. ([GitHub][8]) For your “clone to build, no Xcode dependency” goal, avoid widgets, app extensions, asset catalog weirdness, and anything requiring Xcode’s build system until the base app is solid.

## Recommended repo shape

```text
YourApp/
  Package.swift
  Package.resolved
  Sources/
    YourApp/
      YourApp.swift
      ContentView.swift
      GlassCompat.swift
      Resources/
  Scripts/
    doctor.sh
    package_app.sh
    run.sh
  Makefile
  version.env
```

Use **SwiftPM as the only project file**:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "YourApp", targets: ["YourApp"]),
    ],
    dependencies: [
        // Keep this lean. Add Sparkle/MenuBarExtraAccess/etc. later.
    ],
    targets: [
        .executableTarget(
            name: "YourApp",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "YourAppTests",
            dependencies: ["YourApp"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]
        ),
    ]
)
```

Use a normal SwiftUI entry point:

```swift
import SwiftUI

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }

        Settings {
            SettingsView()
        }
    }
}
```

## Liquid Glass while still targeting macOS 14+

This is the important compatibility pattern. Compile with the macOS 26 SDK, but keep your deployment target at macOS 14 and gate Liquid Glass at runtime.

```swift
import SwiftUI

struct GlassPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            content
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.separator.opacity(0.35))
                }
        }
    }
}
```

Then use standard SwiftUI/AppKit-native controls wherever possible. Apple’s guidance says standard SwiftUI/UIKit/AppKit components pick up Liquid Glass with minimal code, while custom components can adopt it using the SwiftUI glass APIs. ([Apple Developer][9])

This gives you:

```swift
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("Repos")
                Text("Settings")
            }
        } detail: {
            VStack(spacing: 16) {
                Text("Native SwiftUI app")
                    .font(.title)

                GlassPanel {
                    VStack(alignment: .leading) {
                        Text("Liquid Glass on macOS 26+")
                            .font(.headline)
                        Text("Material fallback on macOS 14–25.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .toolbar {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    // refresh
                }
            }
        }
    }
}
```

## The build scripts

### `Scripts/doctor.sh`

This is the script that makes the dependency boundary explicit. It does not require an Xcode project, but it checks that the active Apple developer tools expose a macOS 26 SDK. Apple’s command-line tools package is a self-contained package with the macOS SDK and command-line tools in `/Library/Developer/CommandLineTools`; Apple also says Xcode bundles command-line tools and that `xcode-select --install` installs CLT. ([Apple Developer][10])

```bash
#!/usr/bin/env bash
set -euo pipefail

quiet="${1:-}"

log() {
  if [[ "$quiet" != "--quiet" ]]; then
    printf '%s\n' "$*"
  fi
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Missing required tool: $1" >&2
    exit 1
  }
}

require swift
require xcrun
require codesign
require plutil

log "==> Swift"
swift --version

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK_PATH" ]]; then
  echo "ERROR: No macOS SDK found via xcrun." >&2
  echo "Install Xcode 26.x or matching Command Line Tools, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

log "==> macOS SDK"
log "$SDK_PATH"

if [[ "$SDK_PATH" != *"MacOSX26"* && "$SDK_PATH" != *"MacOSX27"* ]]; then
  echo "ERROR: Liquid Glass SwiftUI APIs require the macOS 26 SDK or newer." >&2
  echo "Current SDK: $SDK_PATH" >&2
  echo "Install/select Xcode 26.x or Command Line Tools that include MacOSX26.sdk." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/GlassProbe.swift" <<'SWIFT'
import SwiftUI

@available(macOS 26.0, *)
private struct GlassProbe: View {
    var body: some View {
        Text("OK").glassEffect()
    }
}
SWIFT

ARCH="$(uname -m)"
xcrun swiftc \
  -typecheck \
  -parse-as-library \
  -target "${ARCH}-apple-macos14.0" \
  "$TMP/GlassProbe.swift"

log "OK: toolchain can compile SwiftUI Liquid Glass symbols."
```

### `Scripts/package_app.sh`

This follows the Trimmy/RepoBar pattern: `swift build`, create bundle, copy executable/resources/frameworks, write `Info.plist`, ad-hoc sign for dev. RepoBar’s packaging script builds with `swift build`, creates the `.app` bundle, copies the executable and resources, installs frameworks like Sparkle if present, and writes a packaged `Info.plist`. ([GitHub][11])

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YourApp"
BUNDLE_ID="${BUNDLE_ID:-com.yourcompany.yourapp}"
CONF="${1:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/version.env"

./Scripts/doctor.sh --quiet

echo "==> Building $APP_NAME ($CONF)"
swift build -c "$CONF"

BUILD_DIR="$ROOT_DIR/.build/$CONF"
APP_BUNDLE="$ROOT_DIR/.build/$CONF/$APP_NAME.app"

if [[ ! -f "$BUILD_DIR/$APP_NAME" ]]; then
  echo "ERROR: Missing built executable: $BUILD_DIR/$APP_NAME" >&2
  exit 1
fi

echo "==> Creating app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources" \
  "$APP_BUNDLE/Contents/Frameworks"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy SwiftPM resource bundles, if any.
shopt -s nullglob
for bundle in "$BUILD_DIR"/*.bundle; do
  echo "==> Copying resource bundle: $(basename "$bundle")"
  cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done
shopt -u nullglob

# Optional icon.
if [[ -f "$ROOT_DIR/Icon.icns" ]]; then
  cp "$ROOT_DIR/Icon.icns" "$APP_BUNDLE/Contents/Resources/Icon.icns"
  ICON_PLIST='<key>CFBundleIconFile</key><string>Icon</string>'
else
  ICON_PLIST=''
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  ${ICON_PLIST}
</dict>
</plist>
PLIST

plutil -lint "$APP_BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP_BUNDLE"

echo "Created: $APP_BUNDLE"
```

### `Scripts/run.sh`

RepoBar launches via LaunchServices so the process has the right bundle identity; that is exactly what you want for permissions, menus, URL handlers, and “why is this old binary running?” sanity. ([GitHub][12])

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YourApp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/Scripts/package_app.sh" debug

pkill -x "$APP_NAME" 2>/dev/null || true
open -n "$ROOT_DIR/.build/debug/$APP_NAME.app"
```

### `version.env`

```bash
MARKETING_VERSION=0.1.0
BUILD_NUMBER=1
```

### `Makefile`

```make
.PHONY: doctor build run test clean

doctor:
	./Scripts/doctor.sh

build:
	./Scripts/package_app.sh debug

run:
	./Scripts/run.sh

test:
	swift test

clean:
	rm -rf .build
```

Then clone-to-build is:

```bash
git clone <repo>
cd YourApp
make run
```

## What I would avoid

Avoid generating an `.xcodeproj` with XcodeGen/Tuist unless you actually want Xcode in the loop. Avoid Widgets/AppIntents/App Extensions at first, because they can require Xcode-specific metadata steps; CodexBar is a good example of that trap. ([GitHub][8]) Avoid making `pnpm` mandatory unless you already want JS tooling; steipete uses it in RepoBar as a script wrapper, but the underlying build is still SwiftPM. ([GitHub][4])

I would also avoid “SwiftPM app product” experiments for now. The steipete repos are doing the boring, reliable thing: executable target + manual `.app` bundling. Boring wins here, very annoyingly.

## Bottom line

The cleanest setup is:

1. **SwiftPM-only project**, no `.xcodeproj`.
2. **macOS 14 deployment target** in `Package.swift` and `Info.plist`.
3. **macOS 26 SDK required to build** because Liquid Glass symbols live there.
4. **Runtime availability gates** for all Liquid Glass calls.
5. **Manual `.app` packaging script** copied from the RepoBar/Trimmy style.
6. **`make run` or `./Scripts/run.sh` as the only local dev command**.

That gives you the practical version of “no Xcode dependency”: no Xcode project, no Xcode UI, no Xcode build system for the base app. But for Xcode 26 / Liquid Glass APIs, the builder still needs Apple’s matching SDK/toolchain installed.

[1]: https://developer.apple.com/news/releases/?utm_source=chatgpt.com "Releases"
[2]: https://developer.apple.com/documentation/macos-release-notes/macos-26_5-release-notes?utm_source=chatgpt.com "macOS Tahoe 26.5 RC Release Notes"
[3]: https://developer.apple.com/documentation/swiftui/glasseffectcontainer?utm_source=chatgpt.com "GlassEffectContainer | Apple Developer Documentation"
[4]: https://github.com/steipete/RepoBar/blob/main/AGENTS.md "RepoBar/AGENTS.md at main · steipete/RepoBar · GitHub"
[5]: https://github.com/steipete/RepoBar/blob/main/docs/spec.md "RepoBar/docs/spec.md at main · steipete/RepoBar · GitHub"
[6]: https://github.com/steipete/Trimmy/blob/main/Package.swift "Trimmy/Package.swift at main · steipete/Trimmy · GitHub"
[7]: https://github.com/steipete/Trimmy/blob/main/Scripts/package_app.sh "Trimmy/Scripts/package_app.sh at main · steipete/Trimmy · GitHub"
[8]: https://raw.githubusercontent.com/steipete/CodexBar/main/Scripts/package_app.sh "raw.githubusercontent.com"
[9]: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass?utm_source=chatgpt.com "Adopting Liquid Glass | Apple Developer Documentation"
[10]: https://developer.apple.com/library/archive/technotes/tn2339/_index.html "Technical Note TN2339: Building from the Command Line with Xcode FAQ"
[11]: https://github.com/steipete/RepoBar/blob/main/Scripts/package_app.sh "RepoBar/Scripts/package_app.sh at main · steipete/RepoBar · GitHub"
[12]: https://github.com/steipete/RepoBar/blob/main/Scripts/compile_and_run.sh "RepoBar/Scripts/compile_and_run.sh at main · steipete/RepoBar · GitHub"
