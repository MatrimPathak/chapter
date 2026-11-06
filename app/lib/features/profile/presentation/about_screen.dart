import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.aboutPrivacy),
            onTap: () => context.push(AppRoutes.privacy),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutLicences),
            onTap: () => showLicensePage(context: context, applicationName: 'Chapter'),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.aboutBookData),
            subtitle: Text(l10n.aboutBookDataBody),
          ),
        ],
      ),
    );
  }
}

/// The policy travels with the app, so it can be read offline.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const asset = 'assets/legal/privacy_policy.md';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutPrivacy)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snapshot) => snapshot.hasData
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(ChapterSpacing.gutter),
                child: SelectableText(snapshot.data!, style: context.textTheme.bodyMedium),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
