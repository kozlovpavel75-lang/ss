import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:exif/exif.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'db.dart';
import 'migration.dart';
import 'crypto.dart';

// ─────────────────────────────────────────────
// ГЛОБАЛЬНИЙ СТАН
// ─────────────────────────────────────────────
ValueNotifier<bool> isMatrixMode  = ValueNotifier(false);
ValueNotifier<bool> isKyivMode    = ValueNotifier(false);

const Map<String, Color> catColors = {
  'ФО':         Color(0xFF6FA8DC),
  'ЮО':         Color(0xFFE8D98C),
  'ГЕОІНТ':     Color(0xFF4ADE80),
  'МОНІТОРИНГ': Color(0xFFE8A05A),
};
Color catColor(String cat) => catColors[cat] ?? AppColors.accent;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  await CryptoHelper.instance.init();
  await MigrationHelper.migrate();
  runApp(const PromptApp());
}

class AppColors {
  static const bg        = Color(0xFF040E22);
  static const bgCard    = Color(0xFF0A152F);
  static const bgDeep    = Color(0xFF040B16);
  static const uaBlue    = Color(0xFF0057B7);
  static const uaYellow  = Color(0xFFE8D98C);
  static const accent    = Color(0xFF6FA8DC);
  static const textPri   = Color(0xFFEEEEEE);
  static const textSec   = Color(0x99FFFFFF);
  static const textHint  = Color(0x40FFFFFF);
  static const border    = Color(0x14FFFFFF);
  static const success   = Color(0xFF4ADE80);
  static const danger    = Color(0xFFFF6B6B);
}

// ─────────────────────────────────────────────
// МОДЕЛІ ДАНИХ
// ─────────────────────────────────────────────
class Prompt {
  String id, title, content, category;
  bool isFavorite;
  Prompt({required this.id, required this.title, required this.content,
          required this.category, this.isFavorite = false});
  
  List<String> get variables {
    final reg = RegExp(r'\{([^}]+)\}');
    return reg.allMatches(content).map((m) => m.group(1)!).toSet().toList();
  }
}

class PDFDoc {
  String id, name, path;
  PDFDoc({required this.id, required this.name, required this.path});
}

class PromptEnhancer {
  final String name, desc, pros, cons, conflicts, rec, payload;
  bool isSelected;
  PromptEnhancer({
    required this.name, required this.desc, required this.pros,
    required this.cons, required this.conflicts, required this.rec,
    required this.payload, this.isSelected = false,
  });
}

// ─────────────────────────────────────────────
// ВІЗУАЛЬНІ ЕФЕКТИ
// ─────────────────────────────────────────────
class MatrixEffect extends StatefulWidget {
  const MatrixEffect({super.key});
  @override State<MatrixEffect> createState() => _MatrixEffectState();
}
class _MatrixEffectState extends State<MatrixEffect> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<double> _y = List.generate(40, (i) => math.Random().nextDouble() * -500);
  final List<int>    _s = List.generate(40, (i) => 3 + math.Random().nextInt(5));
  static const _chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*";
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(painter: _MatrixPainter(_y, _s, _chars), child: Container()),
  );
}

class _MatrixPainter extends CustomPainter {
  final List<double> yPos; final List<int> speeds; final String chars;
  _MatrixPainter(this.yPos, this.speeds, this.chars);
  @override void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black);
    for (int i = 0; i < yPos.length; i++) {
      double x = i * 20.0; if (x > size.width) break;
      yPos[i] += speeds[i];
      if (yPos[i] > size.height) yPos[i] = math.Random().nextDouble() * -200;
      for (int j = 0; j < 12; j++) {
        final char = chars[math.Random().nextInt(chars.length)];
        final tp = TextPainter(
          text: TextSpan(text: char, style: TextStyle(
            color: j == 0 ? Colors.white : Colors.greenAccent.withOpacity(math.max(0, 1 - (j * 0.1))),
            fontSize: 16, fontFamily: 'JetBrainsMono',
          )),
          textDirection: TextDirection.ltr,
        );
        tp.layout(); tp.paint(canvas, Offset(x, yPos[i] - (j * 16)));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter _) => true;
}

class _TopoGridPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.uaBlue.withOpacity(0.03)..strokeWidth = 1.0;
    for (double i = 0; i < size.width;  i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), p);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), p);
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

class _DonutPainter extends CustomPainter {
  final Map<String, int> stats;
  final int total;
  const _DonutPainter(this.stats, this.total);

  @override void paint(Canvas canvas, Size size) {
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeW = 18.0;
    const gap     = 0.04;

    double startAngle = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = strokeW..strokeCap = StrokeCap.butt;

    for (final entry in stats.entries) {
      if (entry.value == 0) continue;
      final sweep = (entry.value / total) * (2 * math.pi) - gap;
      paint.color = catColor(entry.key);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
      startAngle += sweep + gap;
    }

    final tp = TextPainter(
      text: TextSpan(text: '$total', style: const TextStyle(color: AppColors.textPri, fontSize: 22, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
  @override bool shouldRepaint(covariant _DonutPainter old) => old.stats != stats || old.total != total;
}

class _KyivNightPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF020B1A));
    final starPaint = Paint()..color = Colors.white;
    final rng = math.Random(42);
    for (int i = 0; i < 120; i++) {
      final x = rng.nextDouble() * w; final y = rng.nextDouble() * h * 0.6;
      final r = rng.nextDouble() * 1.2 + 0.3; final op = rng.nextDouble() * 0.6 + 0.2;
      canvas.drawCircle(Offset(x, y), r, starPaint..color = Colors.white.withOpacity(op));
    }
    canvas.drawCircle(Offset(w * 0.82, h * 0.12), 22, Paint()..color = const Color(0xFFE8D98C).withOpacity(0.9));
    canvas.drawCircle(Offset(w * 0.82 + 14, h * 0.12), 18, Paint()..color = const Color(0xFF020B1A));

    final cityPath = Path(); cityPath.moveTo(0, h);
    cityPath.lineTo(0, h * 0.72); cityPath.lineTo(w, h * 0.70); cityPath.lineTo(w, h); cityPath.close();
    canvas.drawPath(cityPath, Paint()..color = const Color(0xFF0A1628));
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

class ScrambleText extends StatefulWidget {
  final String text; final TextStyle style;
  const ScrambleText({super.key, required this.text, required this.style});
  @override State<ScrambleText> createState() => _ScrambleTextState();
}
class _ScrambleTextState extends State<ScrambleText> {
  String _disp = ""; Timer? _t;
  @override void initState() {
    super.initState(); int f = 0;
    _t = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) return;
      setState(() {
        f++; _disp = "";
        for (int i = 0; i < widget.text.length; i++) {
          if (f > i + 3) _disp += widget.text[i];
          else _disp += "X#&?@"[math.Random().nextInt(5)];
        }
        if (f > widget.text.length + 10) t.cancel();
      });
    });
  }
  @override void dispose() { _t?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => Text(_disp, style: widget.style);
}

// ─────────────────────────────────────────────
// КОРЕНЕВИЙ ВІДЖЕТ
// ─────────────────────────────────────────────
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (_, matrix, __) => ValueListenableBuilder<bool>(
      valueListenable: isKyivMode,
      builder: (_, kyiv, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.bg,
          fontFamily: 'JetBrainsMono',
          appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: matrix ? Colors.black87 : AppColors.bgCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.uaBlue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    });
  }
  @override Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('🔱', style: TextStyle(fontSize: 64)),
      SizedBox(height: 16),
      Text('UKR_OSINT', style: TextStyle(color: AppColors.uaYellow, fontSize: 22, letterSpacing: 4)),
    ])),
  );
}

// ─────────────────────────────────────────────
// ГОЛОВНИЙ ЕКРАН
// ─────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late TabController _tc;
  List<Prompt> prompts = []; List<PDFDoc> docs = []; List<String> logs = [];
  int _taps = 0; bool _searchActive = false; String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  late AnimationController _countCtrl;
  late Animation<double> _countAnim;
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;

  static const cats = ['HOME', 'ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];

  @override void initState() {
    super.initState();
    _tc = TabController(length: cats.length, vsync: this, initialIndex: 1);
    _tc.addListener(() { if (mounted) setState(() {}); });
    _countCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _countAnim = CurvedAnimation(parent: _countCtrl, curve: Curves.easeOutCubic);
    _scrollCtrl.addListener(() { if (mounted) setState(() => _scrollOffset = _scrollCtrl.offset); });
    _load();
  }

  void _load() async {
    final db = DatabaseHelper.instance;
    final dbP = await db.getPrompts();
    final dbD = await db.getDocs();
    final dbL = await db.getLogs();
    if (!mounted) return;
    setState(() {
      prompts = dbP.map((p) => Prompt(id: p.id, title: p.title, content: p.content, category: p.category, isFavorite: p.isFavorite)).toList();
      docs = dbD.map((d) => PDFDoc(id: d.id, name: d.name, path: d.path)).toList();
      logs = dbL;
    });
    _countCtrl.forward();
  }

  void _log(String a) {
    final msg = "[\${DateTime.now().hour}:\${DateTime.now().minute}] \$a";
    setState(() { logs.insert(0, msg); });
    DatabaseHelper.instance.insertLog(msg);
  }

  void _addP({Prompt? p}) {
    final tC = TextEditingController(text: p?.title ?? '');
    final cC = TextEditingController(text: p?.content ?? '');
    String sC = p?.category ?? 'ФО';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: sC, items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => sC = v!),
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'НАЗВА')),
        TextField(controller: cC, maxLines: 3, decoration: const InputDecoration(labelText: 'ЗМІСТ {VAR}')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          final np = DbPrompt(id: p?.id ?? '\${DateTime.now().millisecondsSinceEpoch}', title: tC.text, content: cC.text, category: sC, isFavorite: p?.isFavorite ?? false);
          if (p == null) DatabaseHelper.instance.insertPrompt(np); else DatabaseHelper.instance.updatePrompt(np);
          _load(); Navigator.pop(ctx);
        }, child: const Text('ЗБЕРЕГТИ')),
      ],
    ));
  }

  @override Widget build(BuildContext context) {
    final m = isMatrixMode.value; final k = isKyivMode.value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: () { if (++_taps >= 7) { isMatrixMode.value = !m; _taps = 0; } },
          child: const Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.location_city), onPressed: () => isKyivMode.value = !k),
          IconButton(icon: const Icon(Icons.receipt_long), onPressed: () => _showLogs()),
        ],
        bottom: TabBar(controller: _tc, isScrollable: true, tabs: cats.map((c) => Tab(text: c)).toList()),
      ),
      body: Stack(children: [
        Positioned.fill(child: m ? const MatrixEffect() : k ? CustomPaint(painter: _KyivNightPainter()) : CustomPaint(painter: _TopoGridPainter())),
        SafeArea(child: TabBarView(controller: _tc, children: [
          _buildHome(),
          _buildPromptList('ФО'), _buildPromptList('ЮО'), _buildPromptList('ГЕОІНТ'), _buildPromptList('МОНІТОРИНГ'),
          ToolsMenu(onLog: _log),
          _buildDocs(),
        ])),
      ]),
      floatingActionButton: _tc.index == 0 ? null : FloatingActionButton(onPressed: () => _addP(), child: const Icon(Icons.add)),
    );
  }

  void _showLogs() => showDialog(context: context, builder: (c) => AlertDialog(
    backgroundColor: Colors.black, title: const Text('LOGS'),
    content: SizedBox(height: 300, width: 300, child: ListView(children: logs.map((l) => Text(l, style: const TextStyle(fontSize: 10, color: Colors.green))).toList())),
  ));

  Widget _buildHome() {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
      const Text('ОПЕРАТИВНИЙ ЦЕНТР', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _statItem('ЗАПИСІВ', prompts.length.toString()),
        _statItem('ДОКС', docs.length.toString()),
      ]),
      const SizedBox(height: 30),
      const Text('ШВИДКИЙ ДОСТУП'),
      Wrap(children: [
        ActionChip(label: const Text('СКАНЕР'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(onLog: _log)))),
        ActionChip(label: const Text('МОРЗЕ'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MorseScreen(onLog: _log)))),
      ]),
    ]));
  }

  Widget _statItem(String l, String v) => Column(children: [Text(v, style: const TextStyle(fontSize: 24, color: AppColors.uaYellow)), Text(l, style: const TextStyle(fontSize: 10))]);

  Widget _buildPromptList(String cat) {
    final list = prompts.where((p) => p.category == cat).toList();
    return ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(
      title: Text(list[i].title),
      subtitle: Text(list[i].content, maxLines: 1),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: list[i], onLog: _log))),
    ));
  }

  Widget _buildDocs() => ListView.builder(itemCount: docs.length, itemBuilder: (c, i) => ListTile(title: Text(docs[i].name)));
}

// ─────────────────────────────────────────────
// ІНСТРУМЕНТИ
// ─────────────────────────────────────────────
class ToolsMenu extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenu({super.key, required this.onLog});
  @override Widget build(BuildContext context) => ListView(children: [
    ListTile(leading: const Icon(Icons.radar), title: const Text('СКАНЕР'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(onLog: onLog)))),
    ListTile(leading: const Icon(Icons.image_search), title: const Text('EXIF'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExifScreen(onLog: onLog)))),
    ListTile(leading: const Icon(Icons.directions_car), title: const Text('АВТО'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AutoScreen(onLog: onLog)))),
    ListTile(leading: const Icon(Icons.vibration), title: const Text('МОРЗЕ'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MorseScreen(onLog: onLog)))),
  ]);
}

// ─────────────────────────────────────────────
// СКАНЕР
// ─────────────────────────────────────────────
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _scan() {
    final t = _c.text; final res = <String>[];
    RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b').allMatches(t).forEach((m) => res.add("IP: \${m.group(0)}"));
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(t).forEach((m) => res.add("MAIL: \${m.group(0)}"));
    setState(() => _r = res); widget.onLog("Scanner: found \${res.length}");
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RADAR SCANNER')),
    body: Column(children: [
      TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(hintText: 'Paste text here...')),
      ElevatedButton(onPressed: _scan, child: const Text('SCAN')),
      Expanded(child: ListView(children: _r.map((s) => ListTile(title: Text(s))).toList())),
    ]),
  );
}

// ─────────────────────────────────────────────
// EXIF
// ─────────────────────────────────────────────
class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, String> _d = {};
  void _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r == null) return;
    final bytes = await File(r.files.single.path!).readAsBytes();
    final data = await readExifFromBytes(bytes);
    setState(() => _d = data.map((k, v) => MapEntry(k, v.toString())));
    widget.onLog("EXIF analyzed");
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('EXIF ANALYZER')),
    body: Column(children: [
      ElevatedButton(onPressed: _pick, child: const Text('PICK IMAGE')),
      Expanded(child: ListView(children: _d.entries.map((e) => ListTile(title: Text(e.key), subtitle: Text(e.value))).toList())),
    ]),
  );
}

// ─────────────────────────────────────────────
// АВТО / VIN
// ─────────────────────────────────────────────
class AutoScreen extends StatefulWidget {
  final Function(String) onLog;
  const AutoScreen({super.key, required this.onLog});
  @override State<AutoScreen> createState() => _AutoScreenState();
}
class _AutoScreenState extends State<AutoScreen> {
  final _vinC = TextEditingController(); String _res = "";
  static const Map<String, String> _vinYear = {
    'A':'1980 / 2010','B':'1981 / 2011','C':'1982 / 2012','D':'1983 / 2013',
    'E':'1984 / 2014','F':'1985 / 2015','G':'1986 / 2016','H':'1987 / 2017',
    'J':'1988 / 2018','K':'1989 / 2019','L':'1990 / 2020','M':'1991 / 2021',
    'N':'1992 / 2022','P':'1993 / 2023','R':'1994 / 2024','S':'1995 / 2025',
    'T':'1996 / 2026','V':'1997','W':'1998','X':'1999','Y':'2000',
    '1':'2001','2':'2002','3':'2003','4':'2004','5':'2005','6':'2006',
    '7':'2007','8':'2008','9':'2009',
  };
  void _check() {
    final v = _vinC.text.toUpperCase(); if (v.length < 10) return;
    final y = _vinYear[v[9]] ?? "Unknown";
    setState(() => _res = "Year: \$y"); widget.onLog("VIN checked");
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AUTO / VIN')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _vinC, decoration: const InputDecoration(labelText: 'VIN CODE')),
      ElevatedButton(onPressed: _check, child: const Text('DECODE')),
      Text(_res, style: const TextStyle(fontSize: 18, color: Colors.greenAccent)),
    ])),
  );
}

// ─────────────────────────────────────────────
// ГЕНЕРАТОР
// ─────────────────────────────────────────────
class GenScreen extends StatefulWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override State<GenScreen> createState() => _GenScreenState();
}
class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  String _res = "";
  @override void initState() {
    super.initState();
    for (var v in widget.p.variables) _ctrls[v] = TextEditingController();
  }
  void _gen() {
    String t = widget.p.content;
    _ctrls.forEach((k, v) => t = t.replaceAll('{\$k}', v.text));
    setState(() => _res = t); widget.onLog("Prompt generated");
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      ..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k))),
      ElevatedButton(onPressed: _gen, child: const Text('GENERATE')),
      const SizedBox(height: 20),
      Expanded(child: Container(padding: const EdgeInsets.all(8), color: Colors.black, child: SingleChildScrollView(child: Text(_res)))),
      ElevatedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _res)), child: const Text('COPY')),
    ])),
  );
}

// ─────────────────────────────────────────────
// МОРЗЕ
// ─────────────────────────────────────────────
class MorseScreen extends StatefulWidget {
  final Function(String) onLog;
  const MorseScreen({super.key, required this.onLog});
  @override State<MorseScreen> createState() => _MorseScreenState();
}
class _MorseScreenState extends State<MorseScreen> {
  final _t = TextEditingController(); String _m = "";
  void _conv() {
    const map = {'A':'.-','B':'-...','C':'-.-.','S':'...','U':'..-'}; // Short demo map
    setState(() => _m = _t.text.toUpperCase().split('').map((c) => map[c] ?? '?').join(' '));
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MORSE CODE')),
    body: Column(children: [
      TextField(controller: _t), ElevatedButton(onPressed: _conv, child: const Text('CONVERT')),
      Text(_m, style: const TextStyle(fontSize: 24, letterSpacing: 4)),
    ]),
  );
}

// ─────────────────────────────────────────────
// ПАСХАЛКА - ГРА
// ─────────────────────────────────────────────
class CottonGame extends StatefulWidget {
  final Function(String) onLog;
  const CottonGame({super.key, required this.onLog});
  @override State<CottonGame> createState() => _CottonGameState();
}
class _CottonGameState extends State<CottonGame> with SingleTickerProviderStateMixin {
  double dX = 0.5, bX = -1, bY = -1;
  List<double> targets = [0.1, 0.4, 0.7, 0.9];
  int score = 0; Timer? _timer;
  late AnimationController _fire;

  @override void initState() {
    super.initState();
    _fire = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < targets.length; i++) { 
          targets[i] += 0.015; 
          if (targets[i] > 1.1) targets[i] = -0.1; 
        }
        if (bY >= 0) {
          bY += 0.04;
          if (bY > 0.85) {
            for (int i = 0; i < targets.length; i++) { 
              if ((bX - targets[i]).abs() < 0.1) { score++; targets[i] = -0.5; widget.onLog("Cotton hit!"); } 
            }
            bY = -1; bX = -1;
          }
        }
      });
    });
  }
  @override void dispose() { _timer?.cancel(); _fire.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width; final h = MediaQuery.of(context).size.height;
    return Scaffold(backgroundColor: Colors.black, body: GestureDetector(
      onTapDown: (d) {
        final x = d.globalPosition.dx / w;
        if (x < 0.3) setState(() => dX = (dX - 0.1).clamp(0.05, 0.95));
        else if (x > 0.7) setState(() => dX = (dX + 0.1).clamp(0.05, 0.95));
        else if (bY < 0) setState(() { bX = dX; bY = 0.15; });
      },
      child: Stack(children: [
        Positioned(top: 40, left: 20, child: Text('SCORE: \$score')),
        AnimatedPositioned(duration: const Duration(milliseconds: 100), top: 80, left: dX * w - 30, child: const Icon(Icons.airplanemode_active, color: Colors.blue, size: 60)),
        if (bY >= 0) AnimatedPositioned(duration: Duration.zero, top: bY * h, left: bX * w, child: const Icon(Icons.wb_sunny, color: Colors.orange)),
        ...targets.map((tx) => Positioned(bottom: 60, left: tx * w, child: const Icon(Icons.person, color: Colors.white))),
        Positioned(bottom: 20, right: 20, child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
      ]),
    ));
  }
}
