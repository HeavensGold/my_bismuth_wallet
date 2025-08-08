# My Bismuth Wallet

<div align="center">

![Bismuth Wallet](https://raw.githubusercontent.com/bismuthfoundation/MEDIA-KIT/master/Screenshots/MyBismuthWallet/my_bis_wallet.png)

**A modern mobile cryptocurrency wallet for Bismuth (BIS)**

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://android.com)

</div>

## 📱 About

My Bismuth Wallet is a cross-platform mobile wallet application built with Flutter for the Bismuth cryptocurrency. It provides secure wallet management, transaction handling, and seamless integration with the Bismuth network.

### ✨ Features

- 🔐 **Secure Wallet Management** - BIP32/BIP39 mnemonic seed support
- 💸 **Send & Receive BIS** - Intuitive transaction interface
- 📱 **Modern UI** - Clean, responsive Material Design
- 🔍 **Transaction History** - Complete transaction tracking
- 🏦 **Multi-Account Support** - Manage multiple wallet accounts
- 📱 **Biometric Security** - TouchID/FaceID authentication
- 🗃️ **Local Storage** - Secure local data management with Hive
- 🔗 **QR Code Support** - Easy address sharing and scanning

## 🛠️ Build Environment Setup

### Prerequisites

Before you begin, ensure you have the following installed on your system:

#### 1. Flutter SDK
- **Required Version**: Flutter 3.16.0 or higher
- **Dart SDK**: 2.19.0 or higher (included with Flutter)

**Installation:**
```bash
# Download Flutter from https://flutter.dev/docs/get-started/install
# Or using package managers:

# macOS (using brew)
brew install flutter

# Linux/macOS (using snap)
sudo snap install flutter --classic

# Verify installation
flutter --version
flutter doctor
```

#### 2. Android Development Environment

**Android Studio** (Recommended) or **Android SDK Command Line Tools**

**Required Components:**
- **Android SDK**: API Level 35 (Android 15)
- **Android Build Tools**: 35.0.0 or higher
- **Android Gradle Plugin**: 8.3.0
- **Gradle**: 8.4
- **Java**: OpenJDK 17 or higher

**Installation via Android Studio:**
1. Download [Android Studio](https://developer.android.com/studio)
2. Install Android Studio and open it
3. Go to SDK Manager and install:
   - Android SDK Platform 35
   - Android SDK Build-Tools 35.0.0
   - Android SDK Command-line Tools
   - Android SDK Platform-Tools

#### 3. Platform-Specific Setup

**For macOS:**
```bash
# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Install CocoaPods (for iOS dependencies)
sudo gem install cocoapods
```

**For Linux:**
```bash
# Install required dependencies
sudo apt-get update
sudo apt-get install curl git unzip xz-utils zip libglu1-mesa
```

**For Windows:**
```bash
# Install Git for Windows
# Download from https://git-scm.com/download/win

# Install Visual Studio or Visual Studio Build Tools
# Download from https://visualstudio.microsoft.com/downloads/
```

### Environment Variables

Set up your development environment:

```bash
# Add Flutter to PATH (add to ~/.bashrc, ~/.zshrc, etc.)
export PATH="$PATH:/path/to/flutter/bin"

# Android SDK path (usually auto-detected by Flutter)
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools"
```

## 🚀 Building and Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/my_bismuth_wallet.git
cd my_bismuth_wallet
```

### 2. Install Dependencies

```bash
# Get Flutter packages
flutter pub get

# Generate required code (for Hive models)
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### 3. Configure Android Signing (Optional for Release Builds)

Create `android/key.properties` for release signing:

```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=../path/to/your/keystore.jks
```

### 4. Build Options

#### Debug Build (Development)
```bash
# Build APK for testing
flutter build apk --debug

# Or build and install directly to connected device
flutter run --debug
```

#### Release Build (Production)
```bash
# Build optimized APK
flutter build apk --release

# Build Android App Bundle (for Play Store)
flutter build appbundle --release

# Build with specific target CPU
flutter build apk --release --target-platform android-arm64
```

### 5. Install on Android Device

#### Method 1: ADB Install
```bash
# Enable Developer Options and USB Debugging on your device
# Connect device via USB

# Install debug build
adb install build/app/outputs/flutter-apk/app-debug.apk

# Install release build
adb install build/app/outputs/flutter-apk/app-release.apk
```

#### Method 2: Direct Installation
1. Copy the APK file to your Android device
2. Enable "Install from Unknown Sources" in device settings
3. Open the APK file and follow installation prompts

#### Method 3: Flutter Run
```bash
# Connect device and run directly
flutter devices  # List available devices
flutter run --release  # Run on connected device
```

## 🔧 Development Tools & Versions

### Compatible Versions

| Tool | Minimum Version | Recommended | Notes |
|------|----------------|-------------|-------|
| **Flutter SDK** | 3.16.0 | Latest Stable | Core framework |
| **Dart SDK** | 2.19.0 | Latest with Flutter | Language runtime |
| **Android SDK** | API 21 (Android 5.0) | API 35 (Android 15) | Target SDK |
| **Android Build Tools** | 30.0.0 | 35.0.0 | Build system |
| **Gradle** | 8.0 | 8.4 | Build automation |
| **Android Gradle Plugin** | 8.0.0 | 8.3.0 | Android build plugin |
| **Java/OpenJDK** | 11 | 17 | Build environment |
| **Kotlin** | 1.7.10 | 1.8.10 | Android development |

### Key Dependencies

- **flutter_secure_storage**: ^9.2.4 - Secure credential storage
- **hive**: ^2.0.4 - Fast local database
- **bip32/bip39**: Cryptocurrency wallet standards
- **qr_flutter**: ^4.0.0 - QR code generation
- **local_auth**: ^2.1.2 - Biometric authentication
- **web_socket_channel**: ^2.1.0 - Network communication

## 📱 Device Requirements

### Android
- **Minimum**: Android 5.0 (API 21)
- **Target**: Android 15 (API 35)
- **Architecture**: ARM64, ARM32, x86_64
- **RAM**: 2GB minimum, 4GB recommended
- **Storage**: 100MB free space

### iOS (Future Support)
- **Minimum**: iOS 12.0
- **Target**: iOS 17.0
- **Architecture**: ARM64
- **RAM**: 2GB minimum
- **Storage**: 100MB free space

## 🐛 Troubleshooting

### Common Build Issues

**1. Flutter Doctor Issues**
```bash
flutter doctor -v
# Fix any reported issues before building
```

**2. Android License Issues**
```bash
flutter doctor --android-licenses
# Accept all licenses
```

**3. Gradle Build Failures**
```bash
# Clean and rebuild
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter build apk --debug
```

**4. Dependency Conflicts**
```bash
# Reset dependencies
flutter clean
rm -rf ~/.pub-cache
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs
```

**5. Android SDK Issues**
- Ensure Android SDK path is correctly set
- Install missing SDK components via Android Studio
- Check that ANDROID_HOME environment variable is set

### Performance Optimization

**For Release Builds:**
```bash
# Enable code shrinking and obfuscation
flutter build apk --release --obfuscate --split-debug-info=build/debug-info/
```

**For Development:**
```bash
# Use debug build for faster compilation
flutter run --debug --hot
```

## 📝 Development Workflow

### Code Generation
```bash
# Run when modifying Hive models or JSON serialization
flutter packages pub run build_runner build
```

### Testing
```bash
# Run unit tests
flutter test

# Run integration tests (if available)
flutter drive --target=test_driver/app.dart
```

### Code Formatting
```bash
# Format code
dart format .

# Analyze code
flutter analyze
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Bismuth Official Website](https://bismuth.im/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Android Development](https://developer.android.com)

## 📞 Support

For issues and support:
- Open an issue on GitHub
- Contact the development team
- Check the [troubleshooting section](#-troubleshooting) above

---

<div align="center">

**Built with ❤️ using Flutter**

</div>