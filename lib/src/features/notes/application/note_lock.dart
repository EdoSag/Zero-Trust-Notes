import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// Confirms it's the phone's owner before a locked note opens.
abstract interface class NoteLockAuthenticator {
  /// True once confirmed; false when cancelled or it failed.
  Future<bool> confirm(BuildContext context, WidgetRef ref, {required String reason});
}

final noteLockAuthenticatorProvider = Provider<NoteLockAuthenticator>(
  (ref) => const DeviceNoteLockAuthenticator(),
);

/// The phone's fingerprint, face or screen lock (PIN, pattern, password).
/// On a phone with no screen lock at all, the account password instead.
class DeviceNoteLockAuthenticator implements NoteLockAuthenticator {
  const DeviceNoteLockAuthenticator();

  static const _noDeviceLock = {
    LocalAuthExceptionCode.noCredentialsSet,
    LocalAuthExceptionCode.noBiometricHardware,
    LocalAuthExceptionCode.noBiometricsEnrolled,
  };

  @override
  Future<bool> confirm(BuildContext context, WidgetRef ref, {required String reason}) async {
    final auth = LocalAuthentication();
    var useDevice = false;
    try {
      useDevice = await auth.isDeviceSupported();
    } on Object {
      useDevice = false;
    }
    if (useDevice) {
      try {
        return await ref
            .read(vaultControllerProvider.notifier)
            .whileShowingSystemUi(
              () => auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true),
            );
      } on LocalAuthException catch (e) {
        if (!_noDeviceLock.contains(e.code)) return false;
      } on Object {
        return false;
      }
    }
    if (!context.mounted) return false;
    return confirmWithAccountPassword(context, ref);
  }
}

/// Asks for the account password and checks it (offline too, against the
/// keys kept on this phone).
Future<bool> confirmWithAccountPassword(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _PasswordDialog(),
  );
  return ok ?? false;
}

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final password = _controller.text;
    if (password.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final result = await ref.read(accountServiceProvider).unlock(password);
      result.dek.fillRange(0, result.dek.length, 0);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = 'That password isn\'t right.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open locked note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This phone has no screen lock, so enter your account password. '
            'Set a screen lock to use your fingerprint or face instead.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !_checking,
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              labelText: 'Account password',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_checking) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _checking ? null : _check, child: const Text('Open')),
      ],
    );
  }
}
