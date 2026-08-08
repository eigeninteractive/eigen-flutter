import 'dart:io';

import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled faces are single variable files with no per-weight entries, so
/// every weight is the `wght` axis moving rather than a different file being
/// chosen. That only works because `FontWeight` drives the axis, which landed
/// in Flutter 3.41. Before it, one file meant one weight and every
/// `FontWeight` rendered identically.
///
/// Measuring is the only way to tell the two apart from a test: a variable font
/// whose axis is ignored still lays out, it just lays out the same at every
/// weight. Nine static weights used to be bundled to work around exactly that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)
      ..addFont(
        File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    await loader.load();
  }

  double widthAt(String family, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Rock paper scissors',
        style: TextStyle(fontFamily: family, fontSize: 48, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  setUpAll(() async {
    await load(AppTheme.inter, 'fonts/Inter-Variable.ttf');
    await load(AppTheme.spaceGrotesk, 'fonts/SpaceGrotesk-Variable.ttf');
  });

  test('Inter renders a real weight range from one file', () {
    final light = widthAt(AppTheme.inter, FontWeight.w300);
    final regular = widthAt(AppTheme.inter, FontWeight.w400);
    final bold = widthAt(AppTheme.inter, FontWeight.w700);

    check(light).isLessThan(regular);
    check(regular).isLessThan(bold);
  });

  test('Space Grotesk renders a real weight range from one file', () {
    final light = widthAt(AppTheme.spaceGrotesk, FontWeight.w300);
    final bold = widthAt(AppTheme.spaceGrotesk, FontWeight.w700);

    check(light).isLessThan(bold);
  });

  test('reaches weights no static file would have provided', () {
    // The axis is continuous, so a weight between the shipped statics is now
    // available. Under file matching this would have snapped to a neighbour.
    final w450 = widthAt(AppTheme.inter, const FontWeight(450));
    final w400 = widthAt(AppTheme.inter, FontWeight.w400);
    final w500 = widthAt(AppTheme.inter, FontWeight.w500);

    check(w450).isGreaterThan(w400);
    check(w450).isLessThan(w500);
  });

  test('the two faces are actually different faces', () {
    // Cheap guard against both families resolving to the same fallback, which
    // is how a font wiring mistake usually presents: everything still renders.
    check(
      widthAt(AppTheme.inter, FontWeight.w400),
    ).not((w) => w.equals(widthAt(AppTheme.spaceGrotesk, FontWeight.w400)));
  });
}
