import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// EDIT DEVICE NAME DIALOG
// =============================================================================
// Prompts for a new device name and calls [onSave] with it. The dialog owns the
// saving spinner: it stays open (and re-enables the button) when [onSave]
// returns false, and closes returning the new name when it returns true.
// =============================================================================

/// Shows the rename dialog. Returns the saved name, or null if the user
/// cancelled or the save failed.
Future<String?> showEditDeviceNameDialog(
  BuildContext context, {
  required String? currentName,
  required Future<bool> Function(String newName) onSave,
}) {
  final controller = TextEditingController(text: currentName);
  bool isSaving = false;

  return showGlassDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => GlassDialog(
        title: 'Edit Device Name',
        icon: Icons.drive_file_rename_outline,
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: glassInputDecoration(
            labelText: 'Device Name',
            prefixIcon: const Icon(Icons.label_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          GlassButton(
            label: 'Save',
            fullWidth: false,
            height: 44,
            isLoading: isSaving,
            onPressed: isSaving
                ? null
                : () async {
                    final newName = controller.text.trim();
                    if (newName.isEmpty) return;

                    setDialogState(() => isSaving = true);

                    final success = await onSave(newName);

                    if (!dialogContext.mounted) return;
                    if (success) {
                      Navigator.pop(dialogContext, newName);
                    } else {
                      setDialogState(() => isSaving = false);
                    }
                  },
          ),
        ],
      ),
    ),
  );
}
