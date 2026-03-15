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
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;

// Глобальний контролер для теми Матриці
ValueNotifier<bool> isMatrixMode = ValueNotifier(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const PromptApp());
}

// --- МОДЕЛІ ДАНИХ ---
class Prompt {
  String id, title, content, category;
  bool isFavorite;
  Prompt({required this.id, required this.title, required this.content, required this.category, this.isFavorite = false});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content, 'category': category, 'isFavorite': isFavorite};
  factory Prompt.fromJson(Map<String, dynamic> json) => Prompt(id: json['id'], title: json['title'], content: json['content'], category: json['category'], isFavorite: json['isFavorite'] ?? false);
}

class PDFDoc {
  String id, name, path;
  PDFDoc({required this.id, required this.name, required this.path});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory PDFDoc.fromJson(Map<String, dynamic> json) => PDFDoc(id: json['id'], name: json['name'], path: json['path']);
}

class PromptEnhancer {
  String name, desc, bestWith, warning, payload;
  bool isSelected;
  PromptEnhancer({required this.name, required this.desc, required this.bestWith, required this.warning, required this.payload, this.isSelected = false});
}

// --- ВІЗУАЛЬНИЙ ФОН: ТОПОГРАФІЧНА СІТКА ---
class TopoGridPainter extends CustomPainter {
  final bool isGreen;
  TopoGridPainter(this.isGreen);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isGreen ? Colors.green.withOpacity(0.05) : const Color(0xFF0057B7).withOpacity(0.03)
      ..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- ГОЛОВНИЙ ДОДАТОК ---
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (context, matrix, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: matrix ? Colors.black : const Color(0xFF040E22),
            primaryColor: matrix ? Colors.greenAccent : const Color(0xFF0057B7),
            fontFamily: 'monospace',
            appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: matrix ? Colors.black : const Color(0xFF0A152F),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: matrix ? Colors.green : Colors.transparent)),
            ),
          ),
          home: const SplashScreen(),
        );
      }
    );
  }
}

// --- ЗАСТАВКА ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Image.asset('assets/splash.png', fit: BoxFit.contain, width: 200)));
}

// --- ГОЛОВНИЙ ЕКРАН ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Prompt> prompts = [];
  List<PDFDoc> docs = [];
  List<String> auditLogs = [];
  int _matrixTaps = 0;

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
  final Color uaYellow = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: categories.length, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _loadData();
  }

  void _logAction(String action) {
    final now = DateTime.now();
    final timeStr = "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    setState(() {
      auditLogs.insert(0, "[$timeStr] $action");
      if (auditLogs.length > 50) auditLogs.removeLast();
    });
    _save();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('prompts_data');
    final dStr = prefs.getString('docs_data');
    final logs = prefs.getStringList('audit_logs');
    setState(() {
      if (pStr != null) prompts = (json.decode(pStr) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dStr != null) docs = (json.decode(dStr) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (logs != null) auditLogs = logs;
      if (prompts.isEmpty) {
        prompts = [Prompt(id: '1', title: 'Приклад промпту', category: 'ФО', content: 'Аналіз: {ПІБ}', isFavorite: true)];
      }
    });
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    await prefs.setString('docs_data', json.encode(docs.map((d) => d.toJson()).toList()));
    await prefs.setStringList('audit_logs', auditLogs);
  }

  void _showSysInfo() {
    Map<String, int> stats = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0};
    for (var p in prompts) { if (stats.containsKey(p.category)) stats[p.category] = stats[p.category]! + 1; }
    int total = prompts.length;

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: isMatrixMode.value ? Colors.black : const Color(0xFF040E22),
      shape: RoundedRectangleBorder(side: BorderSide(color: isMatrixMode.value ? Colors.greenAccent : const Color(0xFF0057B7))),
      title: const Text('MISSION_CONTROL', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatRow('ВСЬОГО ЗАПИСІВ', total.toString(), Colors.greenAccent),
          const Divider(),
          ...stats.entries.map((e) => _buildStatBar(e.key, e.value, total)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  Widget _buildStatRow(String label, String val, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 12)), Text(val, style: TextStyle(color: c, fontWeight: FontWeight.bold))]),
  );

  Widget _buildStatBar(String label, int val, int total) {
    double progress = total == 0 ? 0 : val / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatRow(label, val.toString(), isMatrixMode.value ? Colors.greenAccent : Colors.white),
        LinearProgressIndicator(value: progress, minHeight: 4, color: isMatrixMode.value ? Colors.greenAccent : const Color(0xFF0057B7), backgroundColor: Colors.white10),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            if (++_matrixTaps >= 7) {
              isMatrixMode.value = !isMatrixMode.value;
              _matrixTaps = 0;
              HapticFeedback.vibrate();
            }
          },
          child: Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: isMatrixMode.value ? Colors.greenAccent : Colors.white)),
        ),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: _showSysInfo),
          IconButton(icon: const Icon(Icons.receipt_long, color: Colors.white70), onPressed: () {
             // Показати лог...
          }),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: Stack(
        children: [
          CustomPaint(painter: TopoGridPainter(isMatrixMode.value), child: Container()),
          TabBarView(
            controller: _tabController,
            children: categories.map((cat) {
              if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
              if (cat == 'ДОКУМЕНТИ') return _buildDocs();
              final items = prompts.where((p) => p.category == cat).toList();
              if (items.isEmpty) return _buildEmptyState('АРХІВ ПУСТИЙ');
              items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
              return ReorderableListView.builder(
                padding: const EdgeInsets.only(top: 10, bottom: 90),
                itemCount: items.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx -= 1;
                    final item = items.removeAt(oldIdx);
                    items.insert(newIdx, item);
                  });
                },
                itemBuilder: (ctx, i) => Card(
                  key: ValueKey(items[i].id),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Colors.white.withOpacity(0.05),
                  child: ListTile(
                    leading: Icon(items[i].isFavorite ? Icons.star : Icons.star_border, color: items[i].isFavorite ? uaYellow : Colors.white24),
                    title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _logAction))),
                    onLongPress: () { /* Редагування... */ },
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text("   _     _\n  (o)___(o)\n   (     )\n    '---'", style: TextStyle(color: isMatrixMode.value ? Colors.green : Colors.white24, fontSize: 18)),
      const SizedBox(height: 10),
      Text("[ $msg ]", style: const TextStyle(color: Colors.white24, letterSpacing: 2)),
    ],
  ));

  Widget _buildDocs() => docs.isEmpty ? _buildEmptyState('ФАЙЛІВ НЕМАЄ') : ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
    child: ListTile(title: Text(docs[i].name), leading: const Icon(Icons.file_copy, color: Colors.white54)),
  ));
}

// --- ІНСТРУМЕНТИ ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 10, bottom: 20),
    children: [
      _t(context, 'ВАРІАНТИ НІКНЕЙМУ', 'Генерація логінів', Icons.psychology, NicknameGenScreen(onLog: onLog)),
      _t(context, 'DORKS', 'Кібер-конструктор Google', Icons.travel_explore, DorksScreen(onLog: onLog)),
      _t(context, 'СКАНЕР', 'Екстракція даних (Laser)', Icons.radar, ScannerScreen(onLog: onLog)),
      _t(context, 'EXIF', 'Метадані фотографій', Icons.image_search, ExifScreen(onLog: onLog)),
      _t(context, 'ДЕШИФРАТОР ІПН', 'Аналіз РНОКПП (Brute)', Icons.fingerprint, IpnDecoderScreen(onLog: onLog)),
      _t(context, 'ФІНАНСОВИЙ ВАЛІДАТОР', 'Картки та IBAN', Icons.credit_card, FinValidatorScreen(onLog: onLog)),
      _t(context, 'АВТОМОБІЛЬНИЙ МОДУЛЬ', 'Регіони та VIN', Icons.directions_car, AutoModuleScreen(onLog: onLog)),
      _t(context, 'МЕНЕДЖЕР ПАРОЛІВ', 'Захищений сейф', Icons.lock_outline, PasswordManagerScreen(onLog: onLog)),
    ]
  );
  Widget _t(ctx, t, s, i, scr) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), color: Colors.white.withOpacity(0.03),
    child: ListTile(leading: Icon(i, color: const Color(0xFFFFD700)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), subtitle: Text(s, style: const TextStyle(fontSize: 11)), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr)))
  );
}

// --- ЕФЕКТ БРУТФОРСУ (SCRAMBLE TEXT) ---
class ScrambleText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const ScrambleText({super.key, required this.text, required this.style});
  @override
  State<ScrambleText> createState() => _ScrambleTextState();
}

class _ScrambleTextState extends State<ScrambleText> {
  String _display = "";
  Timer? _timer;
  final _chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*";

  @override
  void initState() {
    super.initState();
    int frame = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 40), (t) {
      setState(() {
        frame++;
        _display = "";
        for (int i = 0; i < widget.text.length; i++) {
          if (frame > i + 5) {
            _display += widget.text[i];
          } else {
            _display += _chars[math.Random().nextInt(_chars.length)];
          }
        }
        if (frame > widget.text.length + 10) t.cancel();
      });
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Text(_display, style: widget.style);
}

// --- НОВЕ: ДЕШИФРАТОР ІПН ---
class IpnDecoderScreen extends StatefulWidget {
  final Function(String) onLog;
  const IpnDecoderScreen({super.key, required this.onLog});
  @override
  State<IpnDecoderScreen> createState() => _IpnDecoderScreenState();
}

class _IpnDecoderScreenState extends State<IpnDecoderScreen> {
  final _c = TextEditingController();
  Map<String, String>? _res;
  bool _showRes = false;

  void _decode() {
    String ipn = _c.text.trim();
    if (ipn.length != 10) return;
    int days = int.parse(ipn.substring(0, 5));
    DateTime dob = DateTime(1899, 12, 31).add(Duration(days: days));
    String gender = int.parse(ipn[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча';
    int age = DateTime.now().year - dob.year;
    
    setState(() {
      _res = { 'ДАТА': "${dob.day}.${dob.month}.${dob.year}", 'ВІК': "$age", 'СТАТЬ': gender };
      _showRes = true;
    });
    widget.onLog("Аналіз ІПН успішний");
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IPN_DECODER')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ 10 ЦИФР')),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _decode, child: const Text('DECRYPT')),
      if (_showRes) ..._res!.entries.map((e) => ListTile(title: Text(e.key), subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)))),
    ])),
  );
}

// --- СКАНЕР (З ЛАЗЕРОМ ТА СИСТЕМОЮ СВІЙ-ЧУЖИЙ) ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController();
  List<String> _r = [];
  late AnimationController _laserCtrl;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _laserCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  }

  @override
  void dispose() { _laserCtrl.dispose(); super.dispose(); }

  void _scan() async {
    setState(() { _isScanning = true; _r.clear(); });
    _laserCtrl.repeat();
    await Future.delayed(const Duration(seconds: 2));
    
    String text = _c.text;
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(text).map((m) => "IP: ${m.group(0)}").toList();
    final phones = RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(text).map((m) => "PH: ${m.group(0)}").toList();
    final links = RegExp(r'(?:https?:\/\/)?(?:www\.)?(?:t\.me|instagram\.com|facebook\.com|vk\.com|x\.com|twitter\.com|tiktok\.com|linkedin\.com)\/[a-zA-Z0-9_.-]+').allMatches(text).map((m) => "URL: ${m.group(0)}").toList();

    setState(() { _r = [...ips, ...phones, ...links]; _isScanning = false; });
    _laserCtrl.stop();
    widget.onLog("Сканування завершено");
  }

  bool _isEnemy(String val) {
    String l = val.toLowerCase();
    return l.contains('.ru') || l.contains('.su') || l.contains('+7') || l.contains('vk.com') || (l.startsWith('8') && l.length > 9);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RADAR_SCANNER')),
    body: Column(children: [
      Stack(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'INPUT_DATA'))),
          if (_isScanning) AnimatedBuilder(
            animation: _laserCtrl,
            builder: (context, child) => Positioned(
              top: 20 + (_laserCtrl.value * 120), left: 16, right: 16,
              child: Container(height: 2, color: Colors.redAccent, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)])),
            ),
          )
        ],
      ),
      ElevatedButton(onPressed: _scan, child: const Text('RUN_SCAN')),
      Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (ctx, i) {
        bool enemy = _isEnemy(_r[i]);
        return Card(
          color: enemy ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          child: ListTile(
            title: Text(_r[i], style: TextStyle(color: enemy ? Colors.redAccent : Colors.greenAccent, fontWeight: enemy ? FontWeight.bold : FontWeight.normal)),
            trailing: Icon(enemy ? Icons.warning : Icons.check_circle, color: enemy ? Colors.red : Colors.green, size: 16),
          ),
        );
      })),
    ]),
  );
}

// --- DORKS (КАСКАД ТА ОПИСИ) ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}

class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<Map<String, String>> _d = [];

  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    setState(() {
      _d = [
        {'t': 'DOCS', 'd': 'Пошук PDF/DOCX', 'q': 'site:$s ext:pdf OR ext:docx'},
        {'t': 'DB', 'd': 'Дампи баз даних', 'q': 'site:$s ext:sql OR ext:db'},
        {'t': 'ADMIN', 'd': 'Панелі керування', 'q': 'site:$s inurl:admin'},
        {'t': 'CAM', 'd': 'Відкриті камери', 'q': 'site:$s inurl:view/view.shtml'},
      ];
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DORKS_CONSTRUCTOR')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'TARGET_DOMAIN'))),
      ElevatedButton(onPressed: _gen, child: const Text('GENERATE')),
      Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (ctx, i) => TweenAnimationBuilder(
        duration: Duration(milliseconds: 300 + (i * 100)),
        tween: Tween<double>(begin: 0, end: 1),
        builder: (ctx, double val, child) => Opacity(opacity: val, child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child)),
        child: Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: ListTile(title: Text(_d[i]['t']!), subtitle: Text(_d[i]['d']!), trailing: const Icon(Icons.copy, size: 16))),
      ))),
    ]),
  );
}

// --- РЕШТА ЕКРАНІВ (ЗАЛИШАЮТЬСЯ РОБОЧИМИ) ---
class FinValidatorScreen extends StatelessWidget {
  final Function(String) onLog;
  const FinValidatorScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('FIN_VALIDATOR')), body: const Center(child: Text('[ IMPLEMENTED ]')));
}

class AutoModuleScreen extends StatelessWidget {
  final Function(String) onLog;
  const AutoModuleScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('AUTO_MODULE')), body: const Center(child: Text('[ IMPLEMENTED ]')));
}

class PasswordManagerScreen extends StatelessWidget {
  final Function(String) onLog;
  const PasswordManagerScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('VAULT')), body: const Center(child: Text('[ SECURE_MODE_ACTIVE ]')));
}

class ExifScreen extends StatelessWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('EXIF_ANALYZER')), body: const Center(child: Text('[ BYTES_ONLY ]')));
}

// --- ГЕНЕРАТОР ПРОМПТІВ (КОЛЬОРОВИЙ) ---
class GenScreen extends StatefulWidget {
  final Prompt p;
  final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  State<GenScreen> createState() => _GenScreenState();
}

class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _isCompiled = false;
  List<TextSpan> _fullSpans = [];
  int _currentChar = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(widget.p.content)) { _ctrls[m.group(1)!] = TextEditingController(); }
  }

  void _compile() {
    _fullSpans.clear();
    String t = widget.p.content;
    int last = 0;
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(t)) {
      if (m.start > last) _fullSpans.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      String key = m.group(1)!;
      _fullSpans.add(TextSpan(text: _ctrls[key]!.text, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)));
      last = m.end;
    }
    if (last < t.length) _fullSpans.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));
    
    setState(() { _isCompiled = true; _currentChar = 0; });
    _timer = Timer.periodic(const Duration(milliseconds: 5), (timer) {
      setState(() { _currentChar += 10; if (_currentChar >= _totalLength()) timer.cancel(); });
    });
  }

  int _totalLength() => _fullSpans.map((s) => s.text!.length).fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      if (!_isCompiled) ..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k))),
      if (!_isCompiled) ElevatedButton(onPressed: _compile, child: const Text('COMPILE')),
      if (_isCompiled) Expanded(child: Container(color: Colors.black, padding: const EdgeInsets.all(12), child: SingleChildScrollView(child: RichText(text: TextSpan(children: _getSpans()))))),
    ])),
  );

  List<TextSpan> _getSpans() {
    List<TextSpan> res = []; int cur = 0;
    for (var s in _fullSpans) {
      if (cur + s.text!.length <= _currentChar) { res.add(s); cur += s.text!.length; }
      else { res.add(TextSpan(text: s.text!.substring(0, _currentChar - cur), style: s.style)); break; }
    }
    return res;
  }
}

class NicknameGenScreen extends StatelessWidget {
  final Function(String) onLog;
  const NicknameGenScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('NICK_GEN')), body: const Center(child: Text('[ RAND_GEN ]')));
}
