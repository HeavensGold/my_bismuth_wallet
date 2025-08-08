

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class BaseTheme {
  late Color primary;
  late Color primary60;
  late Color primary45;
  late Color primary30;
  late Color primary20;
  late Color primary15;
  late Color primary10;

  late Color icon;
  late Color icon45;
  late Color icon60;

  late Color success;
  late Color success60;
  late Color success30;
  late Color success15;
  late Color successDark;
  late Color successDark30;

  late Color background;
  late Color background40;
  late Color background00;

  late Color backgroundDark;
  late Color backgroundDark00;

  late Color backgroundDarkest;

  late Color text;
  late Color text60;
  late Color text45;
  late Color text30;
  late Color text20;
  late Color text15;
  late Color text10;
  late Color text05;
  late Color text03;

  late Color overlay20;
  late Color overlay30;
  late Color overlay50;
  late Color overlay70;
  late Color overlay80;
  late Color overlay85;
  late Color overlay90;

  late Color animationOverlayMedium;
  late Color animationOverlayStrong;

  late Brightness brightness;
  late SystemUiOverlayStyle statusBar;

  late BoxShadow boxShadow;
  late BoxShadow boxShadowButton;
}

class BismuthTheme extends BaseTheme {
  static const teal = Color(0xFF8C379F);

  static const orange = Color(0xFF873999);

  static const orangeDark = Color(0xFF873998);

  static const purpleDark = Color(0xFF242945);

  static const purpleLight = Color(0xFF202940);

  static const purpleDarkest = Color(0xFF242945);

  static const white = Color(0xFFFFFFFF);

  static const black = Color(0xFF000000);

  static const blue = Color(0xFF2196F3);

  Color primary = teal;
  Color primary60 = white.withValues(alpha: 0.6);
  Color primary45 = teal.withValues(alpha: 0.45);
  Color primary30 = teal.withValues(alpha: 0.3);
  Color primary20 = teal.withValues(alpha: 0.2);
  Color primary15 = teal.withValues(alpha: 0.15);
  Color primary10 = teal.withValues(alpha: 0.1);

  Color icon = blue;
  Color icon45 = blue.withValues(alpha: 0.45);
  Color icon60 = blue.withValues(alpha: 0.60);

  Color success = orange;
  Color success60 = orange.withValues(alpha: 0.6);
  Color success30 = orange.withValues(alpha: 0.3);
  Color success15 = orange.withValues(alpha: 0.15);

  Color successDark = orangeDark;
  Color successDark30 = orangeDark.withValues(alpha: 0.3);

  Color background = purpleDark;
  Color background40 = purpleDark.withValues(alpha: 0.4);
  Color background00 = purpleDark.withValues(alpha: 0.0);

  Color backgroundDark = purpleLight;
  Color backgroundDark00 = purpleLight.withValues(alpha: 0.0);

  Color backgroundDarkest = purpleDarkest;

  Color text = white.withValues(alpha: 0.9);
  Color text60 = white.withValues(alpha: 0.6);
  Color text45 = white.withValues(alpha: 0.45);
  Color text30 = white.withValues(alpha: 0.3);
  Color text20 = white.withValues(alpha: 0.2);
  Color text15 = white.withValues(alpha: 0.15);
  Color text10 = white.withValues(alpha: 0.1);
  Color text05 = white.withValues(alpha: 0.05);
  Color text03 = white.withValues(alpha: 0.03);

  Color overlay90 = black.withValues(alpha: 0.9);
  Color overlay85 = black.withValues(alpha: 0.85);
  Color overlay80 = black.withValues(alpha: 0.8);
  Color overlay70 = black.withValues(alpha: 0.7);
  Color overlay50 = black.withValues(alpha: 0.5);
  Color overlay30 = black.withValues(alpha: 0.3);
  Color overlay20 = black.withValues(alpha: 0.2);

  Color animationOverlayMedium = black.withValues(alpha: 0.7);
  Color animationOverlayStrong = black.withValues(alpha: 0.85);

  Brightness brightness = Brightness.dark;
  SystemUiOverlayStyle statusBar =
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent);

  BoxShadow boxShadow = BoxShadow(color: Colors.transparent);
  BoxShadow boxShadowButton = BoxShadow(color: Colors.transparent);
}
