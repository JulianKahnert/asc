# AppStoreConnect Helper

![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2015.0+-lightgrey.svg)

This tool helps you creating a new version in App Store Connect and updating version information.
The `issuerID`, `keyID` and `privateKey` will be saved in the keychain.

## Requirements

- macOS 15.0 or later
- Swift 6.2 or later (for building from source)
- [Mint](https://github.com/yonaskolb/Mint) (for installation via Mint)

## Features

- 🚀 Create new versions for iOS and macOS simultaneously
- 🔄 Automatically update version numbers if an active version exists
- 📝 Update "What's New" texts in German and English (supports JSON input)
- 🔍 Support for both App ID (numeric) and Bundle ID (e.g., com.example.app)
- 🔐 Secure credential storage in macOS Keychain
- 📊 Display current version states and release notes
- 📤 Submit versions for Apple review
- 🔗 Select and assign builds to versions

## Installation

### Via Mint (Recommended)

```bash
mint install juliankahnert/asc
```

### Building from Source

```bash
# Clone the repository
git clone https://github.com/juliankahnert/asc.git
cd asc

# Build the project
swift build -c release

# The executable will be at .build/release/asc
# Optionally, copy it to a location in your PATH
cp .build/release/asc /usr/local/bin/
```

### Development

```bash
# Build and run during development
swift run asc <command>

# Or build separately
swift build
.build/debug/asc <command>
```

## Getting App Store Connect API Credentials

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Navigate to **Users and Access** → **Integrations** → **App Store Connect API**
3. Click the **+** button to generate a new key
4. Give it a name and select **App Manager** access (or higher)
5. Click **Generate**
6. **Download the API Key (.p8 file)** - you can only download this once!
7. Note the following values:
   - **Issuer ID**: Found at the top of the Keys page
   - **Key ID**: Listed in the table for your newly created key

⚠️ **Important**: Store the downloaded `.p8` file securely - you cannot download it again!

## Initialization

Initialize the tool with your App Store Connect API credentials:

```
asc init --issuerID <ISSUER_ID> --keyID <KEY_ID> --privateKeyFile <PATH/TO/FILE.p8>
```

## Usage

### List all apps

First, list all apps in your account to find the App ID or Bundle ID you want to work with:

```bash
asc list-apps
```

This will output:
```
Found 2 app(s):

📦 My App
   App ID: 1234567890
   Bundle ID: com.example.myapp

📦 Another App
   App ID: 9876543210
   Bundle ID: com.example.anotherapp
```

### Create/update a version

Create a version (if needed) and update the "What's New" texts. You can use either the App ID (numeric) or Bundle ID:

```bash
# Using App ID with separate language flags
asc version 1234567890 2.1.0 --hintGerman "Fehlerbehebungen und Verbesserungen" --hintEnglish "Bug fixes and improvements"

# Using Bundle ID (will be automatically resolved to App ID)
asc version com.example.myapp 2.1.0 --hintGerman "Neue Funktionen" --hintEnglish "New features"

# Using JSON format for hints (supports multiline content)
asc version com.example.myapp 2.1.0 --hint '{"german": "Neue Funktionen:\n- Feature 1\n- Feature 2", "english": "New features:\n- Feature 1\n- Feature 2"}'
```

### Show version information

Display current versions with their states and release notes:

```bash
# Show all versions for an app
asc show com.example.myapp

# Or using App ID
asc show 1234567890
```

This will display:
```
📱 iOS Versions:
  Version: 2.1.0
  State: PREPARE_FOR_SUBMISSION

💻 macOS Versions:
  Version: 2.1.0
  State: READY_FOR_SALE
```

### Submit version for review

Submit the current version in PREPARE_FOR_SUBMISSION state for Apple review:

```bash
# Submit iOS version
asc submit com.example.myapp

# Submit macOS version
asc submit com.example.myapp --platform macos
```

### Select build for version

Assign the newest build to a specific version:

```bash
# Select newest iOS build for version 2.1.0
asc select-build com.example.myapp 2.1.0

# Select newest macOS build
asc select-build com.example.myapp 2.1.0 --platform macos
```

### Clear stored credentials

Remove all stored credentials from keychain:

```bash
asc clear
```

## Complete Workflow Example

```bash
# 1. Initialize with your credentials
asc init --issuerID abc123-def4-5678-90ab-cdef12345678 \
         --keyID AB1CD2EF34 \
         --privateKeyFile ~/Downloads/AuthKey_AB1CD2EF34.p8

# 2. List your apps to find the ID
asc list-apps

# 3. Create version 2.1.0 for your app
asc version com.example.myapp 2.1.0 \
    --hintGerman "Fehlerbehebungen und Verbesserungen" \
    --hintEnglish "Bug fixes and improvements"

# Or using JSON format
asc version com.example.myapp 2.1.0 \
    --hint '{"german": "Neue Funktionen", "english": "New features"}'

# 4. Show the current version status
asc show com.example.myapp

# 5. Select the newest build for the version
asc select-build com.example.myapp 2.1.0

# 6. Submit the version for review
asc submit com.example.myapp

# 7. If needed later, clear credentials
asc clear
```

## Available Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize and store App Store Connect API credentials |
| `list-apps` | List all apps in your App Store Connect account |
| `version` | Create or update a version with release notes |
| `show` | Display current versions and their states |
| `submit` | Submit a version for Apple review |
| `select-build` | Assign the newest build to a version |
| `clear` | Remove stored credentials from keychain |

Use `asc <command> --help` to see detailed options for each command.

## Limitations

- **Localizations**: Currently supports only German (`de-DE`) and English (`en-US`) release notes
- **Platform**: macOS only (uses macOS Keychain for credential storage)
- **Platforms managed**: Creates/updates versions for both iOS and macOS simultaneously
