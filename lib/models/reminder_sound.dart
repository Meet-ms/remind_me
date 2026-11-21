import '../utils/stable_hash.dart';

enum SoundKind { defaultSound, ringtone, file }

/// The sound played when a reminder fires.
///
/// [uri] is a `content://` URI the system can read (used for notifications).
/// [path] is a local file (used by the alarm player, which cannot read
/// content URIs). Either may be null for [SoundKind.defaultSound].
class ReminderSound {
  const ReminderSound({
    this.kind = SoundKind.defaultSound,
    this.uri,
    this.path,
    this.name = '',
  });

  static const defaultSound = ReminderSound();

  final SoundKind kind;
  final String? uri;
  final String? path;
  final String name;

  bool get isDefault => kind == SoundKind.defaultSound || uri == null;

  String get label => isDefault ? 'Default' : (name.isEmpty ? 'Custom' : name);

  /// Stable id used to derive a notification channel for this sound.
  String get channelSuffix =>
      isDefault ? 'default' : stableHash(uri!).toRadixString(36);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'uri': uri,
    'path': path,
    'name': name,
  };

  factory ReminderSound.fromJson(Map<String, dynamic>? j) {
    if (j == null) return defaultSound;
    return ReminderSound(
      kind: SoundKind.values.asNameMap()[j['kind']] ?? SoundKind.defaultSound,
      uri: j['uri'] as String?,
      path: j['path'] as String?,
      name: (j['name'] as String?) ?? '',
    );
  }
}
