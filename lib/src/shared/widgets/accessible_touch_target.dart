import 'package:flutter/material.dart';

/// An [IconButton] wrapped to guarantee the WCAG 2.1 AA 48x48dp minimum
/// touch target and a screen-reader label — the pattern used for every
/// icon-only action button in this app.
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        height: 48,
        width: 48,
        child: IconButton(
          tooltip: label,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
