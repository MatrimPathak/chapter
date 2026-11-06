import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/account_actions.dart';

/// Deleting an account can't be undone, so it says exactly what goes and asks
/// for `DELETE` to be typed (docs/05 §1.5).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  static const _word = 'DELETE';
  final _text = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    // The app-wide messenger: signing out replaces this screen.
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await ref.read(accountActionsProvider).deleteAccount();
    if (result == DeleteAccountResult.deleted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.deleteDone)));
      return;
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _error = result == DeleteAccountResult.failed ? l10n.deleteFailed : l10n.deleteCancelled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = context.textTheme.bodyMedium;
    final ready = _text.text.trim() == _word;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deleteTitle)),
      body: ListView(
        padding: const EdgeInsets.all(ChapterSpacing.gutter),
        children: [
          Text(l10n.deleteBody, style: style),
          const SizedBox(height: ChapterSpacing.md),
          Text(l10n.deleteOtherDevices, style: context.textTheme.bodySmall),
          const SizedBox(height: ChapterSpacing.md),
          Text(l10n.deleteExportFirst, style: style),
          const SizedBox(height: ChapterSpacing.lg),
          TextField(
            key: const Key('delete-word'),
            controller: _text,
            enabled: !_deleting,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: l10n.deleteTypeWord(_word), errorText: _error),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ChapterSpacing.lg),
          ChapterButton(
            key: const Key('delete-confirm'),
            label: l10n.deleteConfirm,
            expand: true,
            isLoading: _deleting,
            onPressed: ready ? _delete : null,
          ),
        ],
      ),
    );
  }
}
