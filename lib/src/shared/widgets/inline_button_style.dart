import 'package:flutter/material.dart';

/// Style for a FilledButton or OutlinedButton that sits in a Row or in
/// AppBar actions.
///
/// ZtTheme gives these buttons a full-width minimum size, which suits a
/// button on its own line. In a Row the width it asks for is infinite, the
/// layout fails and release builds draw nothing there, so the button is
/// simply missing on the phone. This keeps the theme's height and shape but
/// lets the button be as wide as its label.
const ButtonStyle inlineButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll<Size>(Size(64, 48)),
);
