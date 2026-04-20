import 'dart:convert';
import 'dart:typed_data';

String base64UrlNoPadEncode(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uint8List base64UrlNoPadDecode(String value) {
  final normalized = base64Url.normalize(value);
  return Uint8List.fromList(base64Url.decode(normalized));
}

String base64StdNoPadEncode(List<int> bytes) {
  return base64Encode(bytes).replaceAll('=', '');
}

Uint8List base64StdNoPadDecode(String value) {
  final padding = (4 - value.length % 4) % 4;
  return Uint8List.fromList(base64.decode(value + ('=' * padding)));
}
