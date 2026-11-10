import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import 'routes.dart';

/// Opens Search from the top of any tab.
class SearchAction extends StatelessWidget {
  const SearchAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('open-search'),
    tooltip: AppLocalizations.of(context).navSearch,
    icon: const Icon(Icons.search_rounded),
    onPressed: () => unawaited(context.push(AppRoutes.search)),
  );
}
