# Open-Source and Release Readiness Notes

Current as of 2026-05-30. This is a contributor/maintainer inventory for RepoPrompt CE's public-readiness work. It documents the current state and follow-ups; it is not legal advice, a substitute for legal review, or a complete third-party dependency audit.

## Release metadata and signing

Release/debug packaging currently derives app identity from [`version.env`](../version.env):

- `APP_NAME=RepoPrompt`
- `DISPLAY_NAME="RepoPrompt CE"`
- `MARKETING_VERSION=2.1.24`
- `BUILD_NUMBER=1`
- `BUNDLE_ID=com.pvncher.repoprompt.ce`
- `SIGNING_TEAM_ID=648A27MST5`

Treat these values as maintainer-owned release metadata. Contributors should not change bundle IDs, signing team IDs, Sparkle keys, or release channels unless a maintainer has explicitly provided the replacement values. Forks that need a branded app should override locally or carry their own release metadata patch.

`./Scripts/package_app.sh release` produces a signed release `.app` bundle only. It requires `SIGN_IDENTITY`, uses timestamped hardened-runtime signing, verifies the signed bundle identifier/team, uses Keychain-backed secure storage, copies the root `LICENSE` and `THIRD_PARTY_NOTICES.md` files into `Contents/Resources/Legal`, and recursively copies root [`ThirdPartyLicenses/`](../ThirdPartyLicenses/) into `Contents/Resources/Legal/ThirdPartyLicenses/` in the packaged app. It does **not** currently create a DMG, notarize/staple, publish GitHub Releases, or generate/update a Sparkle appcast. A fuller production distribution pipeline remains outstanding before public release.

Before a public release, maintainers should reconcile `version.env` with app release/changelog metadata and decide whether `BUILD_NUMBER=1` is intentional for CE or should be advanced to the production build number expected by Sparkle/appcast consumers.

## Sparkle metadata

[`AppBundle/Info.plist.template`](../AppBundle/Info.plist.template) currently contains Sparkle fields:

- `SUFeedURL=https://repoprompt.s3.us-east-2.amazonaws.com/appcast.xml`
- `SUPublicEDKey=KO2Pvcr7ORifYvT7yu2/db48PgzSNN/RG9dk9331iuQ=`
- `SUBundleName=RepoPrompt CE.app`

These are documented as maintainer-owned release/update-channel values. Do not replace them with guessed fork values. Before a CE public release, maintainers should confirm the intended update feed, generate or import the CE Sparkle EdDSA key pair, commit only the public key, store the private key outside the repo/CI secrets, and ensure app-side Sparkle integrity checks agree with the plist values.

## Dependency pins

The root [`Package.swift`](../Package.swift) mostly uses exact versions or fixed revisions. The current branch/fork dependencies that need an explicit maintainer decision before public release are:

| Dependency | Current manifest form | Current `Package.resolved` state | Readiness note |
| --- | --- | --- | --- |
| `https://github.com/provencher/swift-sdk.git` | `branch: "main"` | `cb6a62f7c266ed535792b3e9e6e05dc3f0dac8e4` | Consider a tag/exact revision or document that CE intentionally tracks this fork/branch. |
| `https://github.com/jamesrochabrun/SwiftAnthropic` | `branch: "main"` | `b7d030cd7453f314c780f5492385f73d704cbd5d` | Consider pinning before public release or documenting branch tracking. |
| `https://github.com/provencher/SwiftOpenAI` | `branch: "Fork2"` | `1211782eb337e7968124448a20d9260df1952012` | Fork branch should be tagged/pinned or explicitly documented as required. |

Fixed-revision tree-sitter grammar packages are immutable from SwiftPM's perspective, but they still require license attribution like other dependencies. The seven migrated C, Dart, Go, Java, JavaScript, Python, and Rust grammars use source-preserving exact revision pins, and the curated [`ThirdPartyLicenses/tree-sitter/`](../ThirdPartyLicenses/tree-sitter/) bundle maps those pins plus the other directly linked Tree-sitter grammar products, `SwiftTreeSitter`, its embedded runtime, and the runtime's ICU subset notice. `Package.resolved` should stay committed so local and CI resolutions match unless maintainers intentionally update dependency versions.

Clean coordinated SwiftPM root graphs compile the exact-pinned upstream JavaScript and Python parser objects but omit their external-scanner objects. CE therefore carries the narrow internal [`Sources/TreeSitterScannerSupport`](../Sources/TreeSitterScannerSupport/) compatibility target: byte-for-byte exact-snapshot copies of only those two upstream scanner implementations and their required helper headers. The package URLs, revisions, and upstream products remain unchanged. [`ThirdPartyLicenses/tree-sitter/scanner-support.sha256`](../ThirdPartyLicenses/tree-sitter/scanner-support.sha256) records the copied-file checksums. Remove the support target, guardrails, checksums, and documentation exception together only after validated upstream revisions or SwiftPM behavior compile the scanners directly from the dependency products in a clean graph.

The in-repo provider package at [`Packages/RepoPromptAgentProviders`](../Packages/RepoPromptAgentProviders) is intentional: it is a path dependency used by the root app while provider code is staged for a future external package split.

## Third-party license/notice inventory

Contributor-visible license expectations before public distribution:

| Component | Location | Current notice source | Follow-up |
| --- | --- | --- | --- |
| Sparkle | `Vendor/Sparkle/Sparkle.xcframework` | Binary framework is vendored; no top-level Sparkle license copy was found in this checkout. | Add/verify Sparkle license and provenance in a root `NOTICE`, `THIRD_PARTY_NOTICES.md`, or equivalent before distribution. |
| UniversalCharsetDetection / uchardet | `Vendor/UniversalCharsetDetection` | `LICENSE.md`, `LICENSE-UCHARDET`, `AUTHORS.md`, plus `uchardet/COPYING` and `uchardet/AUTHORS`. | Include the applicable notices in release artifacts / third-party acknowledgements. |
| PCRE2 | `Sources/CSwiftPCRE2/src` | License headers are present in bundled PCRE2 sources such as `pcre2.h`. | Preserve source headers and include PCRE2 notices in release acknowledgements. |
| SLJIT | `Sources/CSwiftPCRE2/deps/sljit` | `LICENSE` and `README.md` identify the bundled SLJIT license. | Preserve source headers and include SLJIT notices in release acknowledgements. |
| wildmatch / OpenBSD-derived fnmatch material | `Sources/RepoPromptC/src/wildmatch/wildmatch.c`, `Sources/RepoPromptC/include/wildmatch.h` | Both checked-in files contain BSD-style notice blocks; `wildmatch.h` includes its existing advertising acknowledgement condition. | Source headers remain preserved. Their full checked-in notice text is reproduced in root `THIRD_PARTY_NOTICES.md` and bundled under `Contents/Resources/Legal` during app packaging. |
| Tree-sitter grammar packages, `SwiftTreeSitter`, embedded runtime, and runtime ICU subset | `Package.swift`, `Package.resolved`, [`ThirdPartyLicenses/tree-sitter/`](../ThirdPartyLicenses/tree-sitter/) | The curated Tree-sitter README maps exact package/runtime pins to full copied license files, including the embedded ICU subset notice. | Included under `Contents/Resources/Legal/ThirdPartyLicenses/tree-sitter/` during app packaging. |
| Other SwiftPM dependencies | `Package.swift`, `Package.resolved` | Upstream packages provide their own license files in their repositories. | Generate or curate a comprehensive third-party notice inventory for remaining release dependencies. |

The root [`LICENSE`](../LICENSE) now provides the Apache License, Version 2.0 for original RepoPrompt CE code. The root [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) is intentionally labeled as a partial inventory: it records the checked-in wildmatch notice material and points to the curated Tree-sitter attribution bundle, while notice curation for other third-party dependencies listed above remains outstanding before a public distribution.

## Contributor validation touchpoints

Docs-only or metadata-documentation changes should at minimum run:

```bash
make guardrails
```

When changes touch dependencies or provider-package code, add:

```bash
swift package resolve
cd Packages/RepoPromptAgentProviders && swift test
```

When changes touch packaging, MCP runtime, debug CLI behavior, Agent Mode runtime behavior, or a running-app feature, run the live CE MCP smoke flow documented in the root [`README.md`](../README.md) after the smallest relevant build/test command.
