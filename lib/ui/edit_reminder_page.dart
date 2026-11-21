import 'package:material_ui/material_ui.dart';

import '../models/condition.dart';
import '../models/reminder.dart';
import '../models/reminder_sound.dart';
import '../services/sound_picker.dart';
import 'condition_editors.dart';

/// Create or edit a reminder. Pops with the resulting [Reminder].
class EditReminderPage extends StatefulWidget {
  const EditReminderPage({super.key, this.initial});
  final Reminder? initial;

  @override
  State<EditReminderPage> createState() => _EditReminderPageState();
}

class _EditReminderPageState extends State<EditReminderPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late List<Condition> _conditions;
  late Combinator _combinator;
  late bool _repeat;
  late Delivery _delivery;
  late ReminderSound _sound;
  bool _pickingSound = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _title = TextEditingController(text: i?.title ?? '');
    _note = TextEditingController(text: i?.note ?? '');
    _conditions = [...?i?.conditions];
    _combinator = i?.combinator ?? Combinator.all;
    _repeat = i?.repeat ?? true;
    _delivery = i?.delivery ?? Delivery.notification;
    _sound = i?.sound ?? ReminderSound.defaultSound;
  }

  Future<void> _chooseSound() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.music_off_outlined),
              title: const Text('Default sound'),
              onTap: () => Navigator.pop(ctx, 'default'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('System ringtone…'),
              onTap: () => Navigator.pop(ctx, 'ringtone'),
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('Audio file from device…'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'default') {
      setState(() => _sound = ReminderSound.defaultSound);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pickingSound = true);
    try {
      final picked = choice == 'ringtone'
          ? await SoundPicker.pickRingtone(_delivery, _sound)
          : await SoundPicker.pickFile();
      if (picked != null && mounted) setState(() => _sound = picked);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not use that sound.')),
      );
    } finally {
      if (mounted) setState(() => _pickingSound = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addCondition() async {
    final type = await showModalBottomSheet<ConditionType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in ConditionType.values)
              ListTile(
                leading: Icon(iconFor(t)),
                title: Text(labelFor(t)),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final c = await showConditionEditor(context, type);
    if (c != null) setState(() => _conditions.add(c));
  }

  Future<void> _editCondition(int index) async {
    final old = _conditions[index];
    final c = await showConditionEditor(context, old.type, initial: old);
    if (c != null) setState(() => _conditions[index] = c);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_conditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one trigger.')),
      );
      return;
    }
    final i = widget.initial;
    Navigator.pop(
      context,
      Reminder(
        id: i?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: _title.text.trim(),
        note: _note.text.trim(),
        conditions: _conditions,
        combinator: _combinator,
        repeat: _repeat,
        delivery: _delivery,
        sound: _sound,
        enabled: true,
        lastTriggeredAt: i?.lastTriggeredAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New reminder' : 'Edit reminder'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Remind me to…',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            Text('Triggers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_conditions.length > 1) ...[
              SegmentedButton<Combinator>(
                segments: const [
                  ButtonSegment(
                    value: Combinator.all,
                    label: Text('All must match'),
                  ),
                  ButtonSegment(
                    value: Combinator.any,
                    label: Text('Any can match'),
                  ),
                ],
                selected: {_combinator},
                onSelectionChanged: (s) =>
                    setState(() => _combinator = s.first),
              ),
              const SizedBox(height: 8),
            ],
            for (var i = 0; i < _conditions.length; i++) ...[
              if (i > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _combinator == Combinator.all ? 'AND' : 'OR',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
              Card(
                child: ListTile(
                  leading: Icon(iconFor(_conditions[i].type)),
                  title: Text(_conditions[i].describe()),
                  onTap: () => _editCondition(i),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _conditions.removeAt(i)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addCondition,
              icon: const Icon(Icons.add),
              label: const Text('Add trigger'),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat'),
              subtitle: Text(
                _repeat
                    ? 'Fires every time the triggers become true'
                    : 'Fires once, then switches off',
              ),
              value: _repeat,
              onChanged: (v) => setState(() => _repeat = v),
            ),
            const Divider(height: 32),
            Text('How to remind you', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<Delivery>(
              segments: const [
                ButtonSegment(
                  value: Delivery.notification,
                  icon: Icon(Icons.notifications_outlined),
                  label: Text('Notification'),
                ),
                ButtonSegment(
                  value: Delivery.alarm,
                  icon: Icon(Icons.alarm),
                  label: Text('Alarm'),
                ),
              ],
              selected: {_delivery},
              onSelectionChanged: (s) => setState(() {
                _delivery = s.first;
                // A ringtone picked for the other mode is the wrong kind.
                if (_sound.kind == SoundKind.ringtone) {
                  _sound = ReminderSound.defaultSound;
                }
              }),
            ),
            const SizedBox(height: 4),
            Text(
              _delivery == Delivery.alarm
                  ? 'Rings loudly over the lock screen until you tap Done or Snooze.'
                  : 'A normal notification with Snooze and Done buttons.',
              style: theme.textTheme.bodySmall,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('Sound'),
              subtitle: Text(_sound.label),
              trailing: _pickingSound
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _pickingSound ? null : _chooseSound,
            ),
          ],
        ),
      ),
    );
  }
}
