/// Surfaced when a Pull finds a remote snapshot newer than this device's
/// last successful sync — the automated pipeline pauses here and asks the
/// user to explicitly pick a side rather than silently picking one for them.
class SyncConflict {
  const SyncConflict({
    required this.remoteUpdatedAt,
    required this.remoteDeviceId,
    required this.localLastSyncTimestamp,
  });

  final DateTime remoteUpdatedAt;
  final String remoteDeviceId;
  final DateTime? localLastSyncTimestamp;
}
