# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ASC is a Swift command-line tool for managing App Store Connect. It provides functionality to create versions, update release notes in multiple languages (German/English), manage credentials securely in the macOS Keychain, and interact with Xcode Cloud workflows.

## Build & Run

```bash
# Build the project (codesign required for Keychain access on macOS)
swift build && codesign --force --sign "Apple Development" .build/debug/asc

# Run the executable
.build/debug/asc <command>
```

## Testing

Run tests with `swift test`. Tests use mock API responses (no live App Store Connect credentials required).

## Architecture

The application uses Swift ArgumentParser to provide a command-line interface.

### Command Structure

Commands use a resource-based noun-verb pattern, grouped by resource:

```
asc init / clear                          # Credential management
asc apps list                             # App listing
asc versions create / show / select-build / submit  # Version lifecycle
asc workflows list / trigger / status     # Xcode Cloud workflow definitions
asc runs list / view / download           # Xcode Cloud build runs & artifacts
```

Mirrors the `gh` CLI split: `workflows` manages the workflow *definitions* (like
`gh workflow`), `runs` works with their individual *executions* and artifacts
(like `gh run`). Resources are flat top-level nouns; ownership is expressed via
the `<app>` argument and filters (e.g. `--workflow`), not command nesting.

- **ASCMain** (`ASC.swift`): the root command that registers the command groups. It lives in the importable **`ASC` library target**; the actual `@main` executable is a thin wrapper in `Sources/ASCExecutable/Entry.swift` that calls `ASCMain.main()`. This split lets the test target import the library and exercise commands directly.
- **Commands/**: Flat directory with prefixed filenames (e.g., `VersionCreateCommand.swift`, `RunsDownloadCommand.swift`). Command groups (e.g., `VersionsCommand.swift`, `RunsCommand.swift`) register their subcommands.
- **KeychainHelper.swift**: Centralized keychain operations with static service identifier `"de.JulianKahnert.asc"`; also hosts shared `resolveAppID()` and `getCiProductID()` helpers.
- **VersionLogic.swift / RunsLogic.swift**: Fetch/parse logic extracted from the command types so it can be unit-tested in isolation against mock API responses.
- **JSONOutput.swift**: Shared `--json` output helper (see below).
- **Platform+Extensions.swift**: `Platform` display-name helper for CLI output.

### JSON Output (`--json`)

Every data-returning command accepts a global `--json` flag. When set, the
command prints a single JSON document (via `JSONOutput.emit`) and suppresses the
human-readable output, so other clients can parse results programmatically.
Currently wired into `apps list`, `versions show`, `workflows list`,
`workflows status`, and all `runs` subcommands. Command logic builds a `Codable`
model and either emits it as JSON or renders it as text.

### Key Dependencies

- **AppStoreConnect-Swift-SDK**: Provides `APIProvider`, `APIConfiguration`, and all App Store Connect API endpoints
- **ArgumentParser**: Command-line interface structure

### Credential Flow

1. User runs `init` command with `--issuerID`, `--keyID`, and `--privateKeyFile` parameters
2. Private key file (.p8) is read and PEM headers/footers are stripped (SDK expects only base64 content)
3. All three credentials are stored in macOS Keychain under service `"de.JulianKahnert.asc"`
4. Other commands retrieve credentials from keychain and create `APIConfiguration` + `APIProvider`

### Version Create Workflow

The `version create` command handles complex scenarios:

1. **App ID Resolution**: Accepts either numeric App ID or Bundle ID (e.g., "com.example.app"). If Bundle ID is provided, it's resolved to App ID via API.

2. **Dual Platform Version Creation**: Creates/finds versions for both iOS and macOS simultaneously.

3. **Version Creation with Conflict Handling**:
   - Attempts to create new version via `createVersion()`
   - If 409 DUPLICATE error: finds and returns existing version via `findExistingVersion()`
   - If 409 "cannot create in current state" error: finds active version via `findActiveVersion()`, then updates its version number via `updateVersionNumber()`
   - Active states considered: `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`

4. **Localization Updates**: For each platform version, creates or updates localizations for both `de-DE` and `en-US` locales via `updateOrCreateLocalization()`.

### Workflows Commands

The `workflows` group uses App Store Connect CI endpoints:

- **list**: Gets CI product for app, then lists workflows with name/enabled/ID
- **trigger**: Resolves workflow by name, finds branch git reference, posts `CiBuildRunCreateRequest`
- **status**: Lists recent build runs per workflow with progress/completion status

### Runs Commands (build runs & artifacts)

The `runs` group inspects Xcode Cloud build runs and their downloadable
artifacts. Logic lives in `RunsLogic.swift`. The relevant API hierarchy is:

```
CiProduct → CiWorkflow → CiBuildRun → CiBuildAction → { CiArtifact, CiIssue, CiTestResult }
```

Key detail: **artifacts hang off `CiBuildAction`, not `CiBuildRun`** — there is
no `/ciBuildRuns/{id}/artifacts`. To get all artifacts of a build, iterate the
run's actions and collect each action's artifacts.

- **list**: Lists recent build runs for the app (`ciProducts/{id}/buildRuns`), or a single workflow's runs (`ciWorkflows/{id}/buildRuns`) with `--workflow`. Resolves branch and workflow names from the `included` payload.
- **view**: Resolves a build *number* to its run, fetches its actions with issue counts, and (for failed / all actions) their issues and downloadable artifacts. `--failed` restricts to failed actions.
- **download**: Fetches fresh pre-signed artifact URLs and downloads matching files to `--output` (default cwd). `--type` filters by file type (LOG_BUNDLE, RESULT_BUNDLE, ARCHIVE, …); `--action` filters by action name.

**Artifact download URLs**: `CiArtifact.downloadUrl` is a short-lived,
pre-signed URL that needs no App Store Connect credentials to fetch, but expires
(typically within minutes). Always re-fetch it from the API immediately before
downloading — never treat it as a durable link. `runs download` does this and
uses a plain `URLSession` to save the file.

## Platform Requirements

- macOS 15.0+ (specified in Package.swift)
- Swift 6.2+ (swift-tools-version)
- Uses macOS Keychain for credential storage (not portable to Linux)
