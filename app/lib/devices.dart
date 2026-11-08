import 'dart:io';

/// Réveille un PC via Wake-on-LAN (le PC doit avoir le réveil réseau activé).
Future<void> wakeOnLan(String mac, {String broadcast = '255.255.255.255'}) async {
  final b = mac.split(RegExp('[:-]')).map((h) => int.parse(h, radix: 16)).toList();
  if (b.length != 6) throw const FormatException('Adresse MAC invalide');
  final packet = <int>[...List.filled(6, 0xFF), for (var i = 0; i < 16; i++) ...b];
  final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  s.broadcastEnabled = true;
  s.send(packet, InternetAddress(broadcast), 9);
  s.close();
}

// À ajouter ensuite : un module par appareil (télé Android TV, domotique),
// chacun séparé, avec confirmation avant toute action.

/// Appelle un service Home Assistant (ex. media_player.turn_on).
Future<void> haCall(String baseUrl, String token, String service, String entityId) async {
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final path = service.replaceFirst('.', '/');
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final r = await c.postUrl(Uri.parse('$base/api/services/$path'));
    r.headers.set('Authorization', 'Bearer $token');
    r.headers.contentType = ContentType.json;
    r.write('{"entity_id":"$entityId"}');
    final res = await r.close();
    if (res.statusCode >= 300) throw HttpException('Home Assistant a répondu ${res.statusCode}');
  } finally {
    c.close();
  }
}
