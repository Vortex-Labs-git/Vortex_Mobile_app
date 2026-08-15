import 'package:flutter/material.dart';

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

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}
