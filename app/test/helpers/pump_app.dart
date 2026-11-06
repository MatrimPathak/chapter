import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a themed, localized MaterialApp.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? ChapterTheme.light() : ChapterTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

/// Every combination the design system must support (docs AC3).
const themeVariants = [
  (Brightness.light, 1.0),
  (Brightness.dark, 1.0),
  (Brightness.light, 2.0),
  (Brightness.dark, 2.0),
];
