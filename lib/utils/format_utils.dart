String formatCompactCount(int value) {
  final absValue = value.abs();
  if (absValue >= 1000000000) {
    final formatted = (value / 1000000000).toStringAsFixed(
      absValue >= 10000000000 ? 0 : 1,
    );
    return '${trimTrailingZero(formatted)}b';
  }
  if (absValue >= 1000000) {
    final formatted = (value / 1000000).toStringAsFixed(
      absValue >= 10000000 ? 0 : 1,
    );
    return '${trimTrailingZero(formatted)}m';
  }
  if (absValue >= 1000) {
    final formatted = (value / 1000).toStringAsFixed(
      absValue >= 10000 ? 0 : 1,
    );
    return '${trimTrailingZero(formatted)}k';
  }
  return value.toString();
}

String trimTrailingZero(String value) {
  return value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
}
