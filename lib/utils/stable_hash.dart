/// FNV-1a hash of [s], non-negative and within 31 bits. Unlike
/// [String.hashCode] it is guaranteed to be the same across isolates and app
/// runs, which notification/alarm ids and channel names rely on.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final v = h & 0x7fffffff;
  return v == 0 ? 1 : v;
}
