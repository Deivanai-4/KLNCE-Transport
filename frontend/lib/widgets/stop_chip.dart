import 'package:flutter/material.dart';
import '../main.dart';

class StopChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const StopChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      selected: isSelected,
      onDeleted: onDelete,
      onPressed: onTap,
      deleteIconColor: Theme.of(context).colorScheme.error,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.engBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }
}

