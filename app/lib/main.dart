import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'devices.dart';

void main() => runApp(const FasoApp());

class FasoApp extends StatelessWidget {
  const FasoApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'FASO',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true)
            .copyWith(scaffoldBackgroundColor: const Color(0xFF05060F)),
        home: const Home(),
      );
}

enum Mode { idle, listening, thinking, speaking }

class Msg {
  Msg(this.me, this.text);
  final bool me;
  final String text;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final stt = SpeechToText();
  final tts = FlutterTts();
  final ctrl = TextEditingController();
  final msgs = <Msg>[];
  late final AnimationController anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  Mode mode = Mode.idle;
  String mac = '', haUrl = '', haToken = '', haEntity = '';

  @override
  void initState() {
    super.initState();
    tts.setLanguage('fr-FR');
    tts.awaitSpeakCompletion(true);
    msgs.add(Msg(false, 'Bonjour, je suis FASO. Appuyez sur le micro ou écrivez-moi.'));
  }

  void add(bool me, String t) => setState(() => msgs.add(Msg(me, t)));

  Future<bool> ask(String q) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(content: Text(q), actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Refuser')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Autoriser')),
        ]),
      ) ??
      false;

  Future<void> settings() async {
    final f = [mac, haUrl, haToken, haEntity].map((v) => TextEditingController(text: v)).toList();
    const labels = ['Adresse MAC du PC', 'Home Assistant : adresse (http://192.168.x.x:8123)', 'Home Assistant : jeton d’accès', 'Entité de la télé (media_player.xxx)'];
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Réglages'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 4; i++)
              TextField(controller: f[i], obscureText: i == 2, decoration: InputDecoration(labelText: labels[i])),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    mac = f[0].text.trim();
    haUrl = f[1].text.trim();
    haToken = f[2].text.trim();
    haEntity = f[3].text.trim();
  }

  Future<void> listen() async {
    if (mode == Mode.listening) {
      await stt.stop();
      setState(() => mode = Mode.idle);
      return;
    }
    final ok = await stt.initialize(onError: (e) => setState(() => mode = Mode.idle));
    if (!ok) {
      add(false, 'Micro refusé ou reconnaissance vocale indisponible.');
      return;
    }
    await tts.stop();
    setState(() => mode = Mode.listening);
    await stt.listen(
      localeId: 'fr_FR',
      onResult: (r) {
        if (r.finalResult) {
          setState(() => mode = Mode.idle);
          send(r.recognizedWords);
        }
      },
    );
  }

  Future<void> send(String t) async {
    t = t.trim();
    if (t.isEmpty) return;
    add(true, t);
    setState(() => mode = Mode.thinking);
    final a = await answer(t);
    add(false, a);
    setState(() => mode = Mode.speaking);
    await tts.speak(a);
    if (mounted) setState(() => mode = Mode.idle);
  }

  Future<String> answer(String t) async {
    final l = t.toLowerCase();
    if (RegExp(r'allume.*(ordi|\bpc\b)').hasMatch(l)) {
      if (mac.isEmpty) return 'Indiquez d’abord l’adresse MAC de votre PC (bouton réglages).';
      if (!await ask('FASO veut envoyer le signal de réveil à votre PC. Autoriser ?')) {
        return 'D’accord, je n’envoie rien.';
      }
      try {
        await wakeOnLan(mac);
        return 'Signal envoyé. Il ne marche que si le réveil réseau est activé sur le PC.';
      } catch (e) {
        return 'Échec : $e';
      }
    }
    if (RegExp(r'(télé|\btv\b)').hasMatch(l)) {
      final on = l.contains('allume'), off = RegExp(r'éteins|éteindre').hasMatch(l);
      if (!on && !off) return 'Dites « allume la télé » ou « éteins la télé ».';
      if (haUrl.isEmpty || haToken.isEmpty || haEntity.isEmpty) {
        return 'Configurez Home Assistant dans les réglages pour piloter la télé.';
      }
      final verbe = on ? 'allumer' : 'éteindre';
      if (!await ask('FASO veut $verbe la télé via Home Assistant. Autoriser ?')) return 'D’accord, je ne fais rien.';
      try {
        await haCall(haUrl, haToken, on ? 'media_player.turn_on' : 'media_player.turn_off', haEntity);
        return on ? 'Commande d’allumage envoyée.' : 'Commande d’extinction envoyée.';
      } catch (e) {
        return 'Échec : $e';
      }
    }
    if (l.contains('heure')) {
      final n = DateTime.now();
      return 'Il est ${n.hour} heures ${n.minute}.';
    }
    if (RegExp(r'^(salut|bonjour|coucou)').hasMatch(l)) return 'Bonjour ! Que puis-je faire pour vous ?';
    return 'Mode démo : aucun modèle d’IA n’est connecté.';
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(0, -1),
                  radius: 1.2,
                  colors: [Color(0xFF241A6B), Color(0xFF05060F)])),
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Row(children: [
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                        colors: [Color(0xFF4D7CFF), Color(0xFFA35CFF)]).createShader(r),
                    child: const Text('FASO',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                            color: Colors.white)),
                  ),
                  const Spacer(),
                  if (mode == Mode.listening)
                    const Text('● Micro actif', style: TextStyle(color: Color(0xFFFF5C7A))),
                  IconButton(onPressed: settings, icon: const Icon(Icons.settings)),
                ]),
              ),
              SizedBox(
                height: 200,
                child: AnimatedBuilder(
                  animation: anim,
                  builder: (_, __) => CustomPaint(
                      painter: OrbPainter(anim.value, mode), size: Size.infinite),
                ),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  for (final m in msgs)
                    Align(
                      alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * .8),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: m.me ? const Color(0xFF4D4DD0) : Colors.white10),
                        child: Text(m.text),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      onSubmitted: (t) {
                        ctrl.clear();
                        send(t);
                      },
                      decoration: const InputDecoration(
                          hintText: 'Écrivez ou parlez à FASO…',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(18)))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      onPressed: listen,
                      icon: Icon(mode == Mode.listening ? Icons.stop : Icons.mic)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class OrbPainter extends CustomPainter {
  OrbPainter(this.t, this.mode);
  final double t;
  final Mode mode;
  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final fast = mode == Mode.idle ? 1.0 : 3.0;
    final base = mode == Mode.listening ? const Color(0xFFFF5C7A) : const Color(0xFF4D7CFF);
    for (var i = 0; i < 3; i++) {
      final p = (t * fast + i / 3) % 1.0;
      c.drawCircle(
          ctr,
          52 + p * 60,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = base.withOpacity((1 - p) * .5));
    }
    final r = 52 + sin(t * 2 * pi * fast) * 4;
    c.drawCircle(
        ctr,
        r + 30,
        Paint()
          ..color = const Color(0xFFA35CFF).withOpacity(.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    c.drawCircle(
        ctr,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.3, -.35),
            colors: [Colors.white, base, const Color(0xFFA35CFF), const Color(0xFF1B0B4A)],
            stops: const [0, .25, .75, 1],
          ).createShader(Rect.fromCircle(center: ctr, radius: r)));
  }

  @override
  bool shouldRepaint(OrbPainter o) => true;
}
