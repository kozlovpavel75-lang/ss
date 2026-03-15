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

// Глобальний стан теми Матриці
ValueNotifier<bool> isMatrixMode = ValueNotifier(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
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
  String name, desc, bestWith, payload;
  bool isSelected;
  PromptEnhancer({required this.name, required this.desc, required this.bestWith, required this.payload, this.isSelected = false});
}

// --- ВІЗУАЛ: СІТКА ТА ЕФЕКТИ ---
class TopoGridPainter extends CustomPainter {
  final bool isGreen;
  TopoGridPainter(this.isGreen);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isGreen ? Colors.green.withOpacity(0.05) : const Color(0xFF0057B7).withOpacity(0.03)..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  final _chars = "ABCDEF0123456789#%&*@";
  @override
  void initState() {
    super.initState();
    int frame = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) return;
      setState(() {
        frame++; _display = "";
        for (int i = 0; i < widget.text.length; i++) {
          if (frame > i + 3) _display += widget.text[i];
          else _display += _chars[math.Random().nextInt(_chars.length)];
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
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: matrix ? Colors.black : const Color(0xFF0A152F),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: matrix ? const BorderSide(color: Colors.green) : BorderSide.none),
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
    body: Container(width: double.infinity, height: double.infinity, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/splash.png'), fit: BoxFit.cover))),
  );
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
        prompts = [Prompt(id: '1', title: 'ПОШУК ПЕРСОНИ', category: 'ФО', content: 'Аналіз: {ПІБ}', isFavorite: true)];
      }
    });
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    await prefs.setString('docs_data', json.encode(docs.map((d) => d.toJson()).toList()));
    await prefs.setStringList('audit_logs', auditLogs);
  }

  void _importTxt() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null && result.files.single.path != null) {
      try {
        String content = await File(result.files.single.path!).readAsString();
        List<Prompt> imported = [];
        for (var block in content.split('===')) {
          if (block.trim().isEmpty) continue;
          String cat = 'МОНІТОРИНГ', title = '', text = '';
          bool isText = false;
          for (var line in block.trim().split('\n')) {
            String l = line.toLowerCase().trim();
            if (l.startsWith('категорія:')) {
              String rawCat = l.replaceFirst('категорія:', '').trim();
              if (rawCat == 'фо' || rawCat.contains('фіз')) cat = 'ФО';
              else if (rawCat == 'юо' || rawCat.contains('юр')) cat = 'ЮО';
              else if (rawCat.contains('гео')) cat = 'ГЕОІНТ';
            }
            else if (l.startsWith('назва:')) title = line.replaceFirst(RegExp(r'Назва:', caseSensitive: false), '').trim();
            else if (l.startsWith('текст:')) { text = line.replaceFirst(RegExp(r'Текст:', caseSensitive: false), '').trim(); isText = true; }
            else if (isText) text += '\n$line';
          }
          if (title.isNotEmpty && text.isNotEmpty) {
            imported.add(Prompt(id: DateTime.now().millisecondsSinceEpoch.toString() + title, title: title, content: text.trim(), category: cat));
          }
        }
        setState(() => prompts.addAll(imported));
        _logAction("Імпортовано ${imported.length} промптів");
        _save();
      } catch (e) { _logAction("Помилка імпорту"); }
    }
  }

  void _showAuditLog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: isMatrixMode.value ? Colors.black : const Color(0xFF040E22),
      title: const Text('AUDIT_LOG'),
      content: SizedBox(width: double.maxFinite, height: 300, child: ListView.builder(itemCount: auditLogs.length, itemBuilder: (c, i) => Text(auditLogs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent)))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ЗАКРИТИ'))],
    ));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path)));
      _logAction("Додано PDF");
      _save();
    }
  }

  void _addOrEditPrompt({Prompt? p}) {
    final tCtrl = TextEditingController(text: p?.title ?? '');
    final cCtrl = TextEditingController(text: p?.content ?? '');
    String selectedCat = p?.category ?? 'ФО';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setS) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F),
      title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(isExpanded: true, value: selectedCat, items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setS(() => selectedCat = v!)),
        TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'НАЗВА')),
        TextField(controller: cCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'ТЕКСТ {VAR}')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          setState(() {
            if (p == null) prompts.add(Prompt(id: DateTime.now().toString(), title: tCtrl.text, content: cCtrl.text, category: selectedCat));
            else { p.title = tCtrl.text; p.content = cCtrl.text; p.category = selectedCat; }
          });
          _save(); Navigator.pop(ctx);
        }, child: const Text('ЗБЕРЕГТИ'))
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () { if (++_matrixTaps >= 7) { isMatrixMode.value = !isMatrixMode.value; _matrixTaps = 0; HapticFeedback.vibrate(); } },
          child: Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: isMatrixMode.value ? Colors.greenAccent : Colors.white)),
        ),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: () { /* Показати Дашборд */ }),
          IconButton(icon: const Icon(Icons.receipt_long, color: Colors.white70), onPressed: _showAuditLog),
          IconButton(icon: const Icon(Icons.download, color: Color(0xFF0057B7)), onPressed: _importTxt),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: Stack(children: [
        CustomPaint(painter: TopoGridPainter(isMatrixMode.value), child: Container()),
        TabBarView(controller: _tabController, children: categories.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
          if (cat == 'ДОКУМЕНТИ') return _buildDocs();
          final items = prompts.where((p) => p.category == cat).toList();
          if (items.isEmpty) return _buildEmptyState('АРХІВ ПУСТИЙ');
          items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
            child: ListTile(
              leading: IconButton(icon: Icon(items[i].isFavorite ? Icons.star : Icons.star_border, color: items[i].isFavorite ? uaYellow : Colors.white24), onPressed: () { setState(() => items[i].isFavorite = !items[i].isFavorite); _save(); }),
              title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _logAction))),
              onLongPress: () => _addOrEditPrompt(p: items[i]),
            ),
          ));
        }).toList()),
      ]),
      floatingActionButton: _tabController.index == 4 ? null : FloatingActionButton(
        backgroundColor: const Color(0xFF0057B7),
        onPressed: () => _tabController.index == 5 ? _pickPDF() : _addOrEditPrompt(),
        child: Icon(_tabController.index == 5 ? Icons.picture_as_pdf : Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text("   _     _\n  (o)___(o)\n   (     )\n    '---'", style: TextStyle(color: isMatrixMode.value ? Colors.green : Colors.white12, fontSize: 18)),
    const SizedBox(height: 10), Text("[ $msg ]", style: const TextStyle(color: Colors.white24, letterSpacing: 2)),
  ]));

  Widget _buildDocs() => docs.isEmpty ? _buildEmptyState('ФАЙЛІВ НЕМАЄ') : ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
    child: ListTile(leading: const Icon(Icons.file_copy, color: Colors.white54), title: Text(docs[i].name), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i])))),
  ));
}

// --- DORKS (РЕАЛЬНИЙ КОНСТРУКТОР) ---
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
    setState(() { _d = [
      {'t': 'DOCS', 'q': 'site:$s ext:pdf OR ext:doc OR ext:docx'},
      {'t': 'LOGS', 'q': 'site:$s ext:log OR ext:txt "password"'},
      {'t': 'SQL', 'q': 'site:$s ext:sql OR ext:db OR ext:bak'},
      {'t': 'ADMIN', 'q': 'site:$s inurl:admin OR inurl:login'},
    ]; });
    widget.onLog("Dorks: $s");
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DORKS')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ДОМЕН'))),
      ElevatedButton(onPressed: _gen, child: const Text('GENERATE')),
      Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.all(8), child: ListTile(title: Text(_d[i]['t']!), subtitle: Text(_d[i]['q']!), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _d[i]['q']!))))))),
    ]),
  );
}

// --- СКАНЕР (З ЛАЗЕРОМ ТА ІМПОРТОМ) ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController();
  List<String> _r = [];
  late AnimationController _lCtrl;
  bool _isScanning = false;

  @override
  void initState() { super.initState(); _lCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  @override
  void dispose() { _lCtrl.dispose(); super.dispose(); }

  void _load() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx']);
    if (r != null) {
      final file = File(r.files.single.path!); String text = "";
      if (r.files.single.extension == 'docx') {
        final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
        for (var f in archive) if (f.name == 'word/document.xml') text = utf8.decode(f.content).replaceAll(RegExp(r'<[^>]*>'), ' ');
      } else text = await file.readAsString();
      setState(() { _c.text = text; });
    }
  }

  void _scan() async {
    setState(() { _isScanning = true; _r.clear(); });
    _lCtrl.repeat(); await Future.delayed(const Duration(seconds: 2));
    String t = _c.text;
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(t).map((m) => "IP: ${m.group(0)}").toList();
    final phs = RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(t).map((m) => "PH: ${m.group(0)}").toList();
    setState(() { _r = [...ips, ...phs]; _isScanning = false; });
    _lCtrl.stop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SCANNER'), actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _load)]),
    body: Column(children: [
      Stack(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'INPUT_DATA'))),
        if (_isScanning) AnimatedBuilder(animation: _lCtrl, builder: (c, _) => Positioned(top: 20 + (_lCtrl.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.redAccent, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)])))),
      ]),
      ElevatedButton(onPressed: _scan, child: const Text('RUN_SCAN')),
      Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => Card(color: _r[i].contains('+7') ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05), child: ListTile(title: Text(_r[i], style: TextStyle(color: _r[i].contains('+7') ? Colors.redAccent : Colors.greenAccent)))))),
    ]),
  );
}

// --- ІНШІ ІНСТРУМЕНТИ (ПОВНА ЛОГІКА) ---

class IpnDecoderScreen extends StatefulWidget {
  final Function(String) onLog;
  const IpnDecoderScreen({super.key, required this.onLog});
  @override
  State<IpnDecoderScreen> createState() => _IpnDecoderScreenState();
}
class _IpnDecoderScreenState extends State<IpnDecoderScreen> {
  final _c = TextEditingController(); Map<String, String>? _res;
  void _decode() {
    String s = _c.text.trim(); if (s.length != 10) return;
    DateTime dob = DateTime(1899, 12, 31).add(Duration(days: int.parse(s.substring(0, 5))));
    setState(() => _res = {'ДАТА': "${dob.day}.${dob.month}.${dob.year}", 'СТАТЬ': int.parse(s[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча'});
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('IPN')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    TextField(controller: _c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '10 ЦИФР')),
    ElevatedButton(onPressed: _decode, child: const Text('DECODE')),
    if (_res != null) ..._res!.entries.map((e) => ListTile(title: Text(e.key), subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent))))
  ])));
}

class FinValidatorScreen extends StatefulWidget {
  final Function(String) onLog;
  const FinValidatorScreen({super.key, required this.onLog});
  @override
  State<FinValidatorScreen> createState() => _FinValidatorScreenState();
}
class _FinValidatorScreenState extends State<FinValidatorScreen> {
  final _c = TextEditingController(); String _r = "";
  void _check() {
    String cc = _c.text.replaceAll(' ', ''); int sum = 0; bool alt = false;
    for (int i = cc.length - 1; i >= 0; i--) {
      int n = int.parse(cc[i]); if (alt) { n *= 2; if (n > 9) n -= 9; }
      sum += n; alt = !alt;
    }
    setState(() => _r = sum % 10 == 0 ? "ВАЛІДНА" : "НЕ КОРЕКТНА");
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('CARD')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР')),
    ElevatedButton(onPressed: _check, child: const Text('CHECK')),
    Text(_r, style: TextStyle(fontSize: 20, color: _r == "ВАЛІДНА" ? Colors.greenAccent : Colors.redAccent))
  ])));
}

class AutoModuleScreen extends StatefulWidget {
  final Function(String) onLog;
  const AutoModuleScreen({super.key, required this.onLog});
  @override
  State<AutoModuleScreen> createState() => _AutoModuleScreenState();
}
class _AutoModuleScreenState extends State<AutoModuleScreen> {
  final _c = TextEditingController(); String _r = "";
  final Map<String, String> _reg = {'AA': 'Київ', 'KA': 'Київ', 'BC': 'Львів', 'HC': 'Львів', 'AE': 'Дніпро', 'KE': 'Дніпро'};
  void _check() {
    String s = _c.text.trim().toUpperCase(); if (s.length < 2) return;
    setState(() => _r = _reg[s.substring(0, 2)] ?? "Невідомий регіон");
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('AUTO')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР (АА1234ВВ)')),
    ElevatedButton(onPressed: _check, child: const Text('CHECK')),
    Text(_r, style: const TextStyle(fontSize: 20, color: Colors.greenAccent))
  ])));
}

class PasswordManagerScreen extends StatefulWidget {
  final Function(String) onLog;
  const PasswordManagerScreen({super.key, required this.onLog});
  @override
  State<PasswordManagerScreen> createState() => _PasswordManagerScreenState();
}
class _PasswordManagerScreenState extends State<PasswordManagerScreen> {
  List<Map<String, String>> _v = [];
  void _add() { setState(() => _v.add({'s': 'Resource', 'p': 'Pass123'})); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('VAULT')), body: ListView.builder(itemCount: _v.length, itemBuilder: (c, i) => ListTile(title: Text(_v[i]['s']!), subtitle: Text(_v[i]['p']!))), floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)));
}

// --- ЕКРАН ГЕНЕРАЦІЇ ---
class GenScreen extends StatefulWidget {
  final Prompt p;
  final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  State<GenScreen> createState() => _GenScreenState();
}
class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _isC = false; List<TextSpan> _spans = []; int _limit = 0; Timer? _t;
  @override
  void initState() {
    super.initState();
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(widget.p.content)) _ctrls[m.group(1)!] = TextEditingController();
  }
  void _compile() {
    _spans.clear(); String t = widget.p.content; int last = 0;
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(t)) {
      if (m.start > last) _spans.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      String val = _ctrls[m.group(1)!]!.text;
      _spans.add(TextSpan(text: val.isEmpty ? "{${m.group(1)}}" : val, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)));
      last = m.end;
    }
    if (last < t.length) _spans.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));
    setState(() { _isC = true; _limit = 0; });
    _t = Timer.periodic(const Duration(milliseconds: 5), (timer) {
      if (!mounted) return;
      setState(() { _limit += 10; if (_limit >= _len()) timer.cancel(); });
    });
  }
  int _len() => _spans.map((s) => s.text!.length).fold(0, (a, b) => a + b);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      if (!_isC) ...[..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k))), ElevatedButton(onPressed: _compile, child: const Text('COMPILE'))],
      if (_isC) Expanded(child: Container(width: double.infinity, color: Colors.black, padding: const EdgeInsets.all(12), child: SingleChildScrollView(child: RichText(text: TextSpan(children: _getVisible()))))),
      if (_isC) Row(children: [Expanded(child: ElevatedButton(onPressed: () => setState(() => _isC = false), child: const Text('RESET'))), const SizedBox(width: 10), Expanded(child: ElevatedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _spans.map((s) => s.text).join())), child: const Text('COPY')))]),
    ])),
  );
  List<TextSpan> _getVisible() {
    List<TextSpan> res = []; int cur = 0;
    for (var s in _spans) {
      if (cur + s.text!.length <= _limit) { res.add(s); cur += s.text!.length; }
      else { res.add(TextSpan(text: s.text!.substring(0, _limit - cur), style: s.style)); break; }
    }
    return res;
  }
}

class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(10), children: [
    _t(context, 'DORKS', 'Google Constructor', Icons.travel_explore, DorksScreen(onLog: onLog)),
    _t(context, 'SCANNER', 'Laser Extraction', Icons.radar, ScannerScreen(onLog: onLog)),
    _t(context, 'IPN', 'Brute Decoder', Icons.fingerprint, IpnDecoderScreen(onLog: onLog)),
    _t(context, 'FINANCE', 'Card Validator', Icons.credit_card, FinValidatorScreen(onLog: onLog)),
    _t(context, 'AUTO', 'VIN & Regions', Icons.directions_car, AutoModuleScreen(onLog: onLog)),
    _t(context, 'VAULT', 'Passwords', Icons.lock, PasswordManagerScreen(onLog: onLog)),
  ]);
  Widget _t(ctx, t, s, i, scr) => Card(margin: const EdgeInsets.symmetric(vertical: 6), color: Colors.white.withOpacity(0.03), child: ListTile(leading: Icon(i, color: const Color(0xFFFFD700)), title: Text(t), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr))));
}

class NicknameGenScreen extends StatelessWidget {
  final Function(String) onLog;
  const NicknameGenScreen({super.key, required this.onLog});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('NICK')), body: const Center(child: Text('RANDOM_GEN_ACTIVE')));
}

class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
}
