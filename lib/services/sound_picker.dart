import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reminder.dart';
import '../models/reminder_sound.dart';
import '../utils/stable_hash.dart';

/// Lets the user choose a system ringtone or an audio file, and prepares it
/// for both delivery modes: a `content://` URI for notification channels and
/// a local file for the alarm player.
class SoundPicker {
  static const _channel = MethodChannel('remind_me/sound');

  static Future<Directory> _soundsDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'sounds')).create(recursive: true);
  }

  static Future<ReminderSound?> pickRingtone(
    Delivery delivery,
    ReminderSound current,
  ) async {
    final res = await _channel.invokeMapMethod<String, String>('pickRingtone', {
      'type': delivery == Delivery.alarm ? 'alarm' : 'notification',
      'existing': current.kind == SoundKind.ringtone ? current.uri : null,
    });
    if (res == null) return null;
    final uri = res['uri']!;
    final dir = await _soundsDir();
    final dest = p.join(dir.path, 'ringtone_${stableHash(uri)}.snd');
    await _channel.invokeMethod('copyUriToFile', {'uri': uri, 'dest': dest});
    return ReminderSound(
      kind: SoundKind.ringtone,
      uri: uri,
      path: dest,
      name: res['name'] ?? 'Ringtone',
    );
  }

  static Future<ReminderSound?> pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    final source = file?.path;
    if (file == null || source == null) return null;

    final dir = await _soundsDir();
    final dest = p.join(
      dir.path,
      '${stableHash(source)}_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.name)}',
    );
    await File(source).copy(dest);
    final uri = await _channel.invokeMethod<String>(
      'registerNotificationSound',
      {'path': dest, 'name': p.basenameWithoutExtension(file.name)},
    );
    return ReminderSound(
      kind: SoundKind.file,
      uri: uri,
      path: dest,
      name: file.name,
    );
  }
}
