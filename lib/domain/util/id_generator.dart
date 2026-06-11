import 'dart:math';

final _random = Random();
int _sequence = 0;

/// Collision-proof ids. Timestamps alone are NOT unique — Windows clock
/// resolution quantizes `microsecondsSinceEpoch`, so sequential creates
/// can collide and silently overwrite rows via upsert. The counter and
/// random suffix make that impossible within and across sessions.
String newId(String prefix) {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final seq = (_sequence++).toRadixString(36);
  final salt = _random.nextInt(0x7FFFFFFF).toRadixString(36);
  return '$prefix-$time-$seq$salt';
}
