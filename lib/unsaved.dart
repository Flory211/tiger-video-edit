import 'package:flutter/material.dart';

import 'editor.dart';

/// A cancelled save is a cancelled navigation. Keeping a mounted editing
/// session is explicitly different from discarding it to open a new project.
Future<bool> confirmUnsavedChanges(
  BuildContext context,
  Editor editor, {
  bool preserveSession = false,
}) async {
  if (!editor.dirty) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Несохранённые изменения'),
      content: Text(
        preserveSession
            ? 'Сохранить проект перед переходом на главный экран? '
                  'Можно оставить изменения в текущем сеансе и вернуться к ним позже.'
            : 'Сохранить текущий проект перед тем, как продолжить?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: Text(
            preserveSession ? 'Оставить несохранённым' : 'Не сохранять',
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'save'),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (choice == 'discard') return true;
  if (choice != 'save') return false;
  try {
    await editor.save();
    return !editor.dirty;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить проект: $error')),
      );
    }
    return false;
  }
}
