# My Bismuth Wallet

Bismuth iOS and Android app based on Flutter framework.

All infos here : https://hypernodes.bismuth.live/?p=2574

## Thanks
Thanks to Natrium team with his perfect flutter app :)


<How to compile>

The code base is years old. Up to date Flutter/Dart versions might not compatible with the code base.
I used the following version of Flutter SDK to compile My Bismuth Wallet.

│ Version │ Channel │ Flutter Version │ Dart Version │ Release Date │ Global │
├─────────┼─────────┼─────────────────┼──────────────┼──────────────┼────────┤
│ 2.2.1   │ stable  │ 2.2.1           │ 2.13.1       │ May 27, 2021 │        │
├─────────┼─────────┼─────────────────┼──────────────┼──────────────┼────────┤

1. Install flutter:
https://docs.flutter.dev/get-started/install

2. Set up development & compile environments for your system(WINDOW/MACOS/LINUX)
You have to study yourself.  

3. Install fvm:
- fvm is flutter version manager. To install older versions of flutter SDK, quite useful. 
https://fvm.app/documentation/getting-started/installation

4. git clone the repository: git clone https://github.com/HeavensGold/my_bismuth_wallet.git
- original v1.0.55 version's commit hash is b5d29b327624b616615216784e52ef7a3c1226d6
- I rebased from that commit, fixed some errors and updated api url addresses.
5. cd my_bismuth_wallet
6. fvm install 2.2.1
7. fvm use 2.2.1
8. .fvm/flutter_sdk/bin/flutter clean
9. .fvm/flutter_sdk/bin/flutter pub get
10. .fvm/flutter_sdk/bin/flutter devices
11. make sure your device is attached.
12. .fvm/flutter_sdk/bin/flutter run --no-sound-null-safety
13. .fvm/flutter_sdk/bin/flutter build apk --release --no-sound-null-safety





