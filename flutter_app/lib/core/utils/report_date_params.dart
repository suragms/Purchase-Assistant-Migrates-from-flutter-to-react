/// Local calendar date + timezone offset for report API queries (Gulf UTC+4, etc.).
String apiDateLocal(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

int get localTzOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

Map<String, String> reportDateQueryParams({
  required DateTime from,
  required DateTime to,
}) {
  return {
    'from': apiDateLocal(from),
    'to': apiDateLocal(to),
    'tz_offset_minutes': localTzOffsetMinutes.toString(),
  };
}
