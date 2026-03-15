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

ValueNotifier<bool> isMatrixMode = ValueNotifier(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const PromptApp());
}

// --- МОДЕЛІ ДАНИХ ---
class Prompt {
  String id, title, content, category; bool isFavorite;
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
  String name, desc, pros, cons, rec, payload; bool isSelected;
  PromptEnhancer({required this.name, required this.desc, required this.pros, required this.cons, required this.rec, required this.payload, this.isSelected = false});
}

// --- ВІЗУАЛ ---
class TopoGridPainter extends CustomPainter {
  final bool isGreen; TopoGridPainter(this.isGreen);
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isGreen ? Colors.green.withOpacity(0.05) : const Color(0xFF0057B7).withOpacity(0.03)..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      setState(() { f++; _disp = ""; for (int i = 0; i < widget.text.length; i++) { if (f > i + 3) _disp += widget.text[i]; else _disp += "X#&?@"[math.Random().nextInt(5)]; } if (f > widget.text.length + 10) t.cancel(); });
    });
  }
  @override void dispose() { _t?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => Text(_disp, style: widget.style);
}

// --- APP ---
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (ctx, matrix, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: matrix ? Colors.black : const Color(0xFF040E22),
          primaryColor: matrix ? Colors.greenAccent : const Color(0xFF0057B7),
          fontFamily: 'monospace',
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override void initState() { super.initState(); Timer(const Duration(milliseconds: 1800), () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()))); }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Container(width: double.infinity, height: double.infinity, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/splash.png'), fit: BoxFit.cover))));
}

// --- ГОЛОВНИЙ ЕКРАН ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<Prompt> prompts = []; List<PDFDoc> docs = []; List<String> logs = [];
  int _taps = 0;
  final List<String> cats = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];

  @override void initState() { super.initState(); _tc = TabController(length: cats.length, vsync: this); _tc.addListener(() { setState(() {}); }); _load(); }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    final pS = p.getString('prompts'); final dS = p.getString('docs'); final lS = p.getStringList('logs');
    setState(() {
      if (pS != null) prompts = (json.decode(pS) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dS != null) docs = (json.decode(dS) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (lS != null) logs = lS;
      if (prompts.isEmpty) prompts = [Prompt(id: '1', title: 'ПОШУК ПЕРСОНИ', category: 'ФО', content: 'Аналіз даних: {ПІБ}\nМісто: {Місто}', isFavorite: true)];
    });
  }

  void _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('prompts', json.encode(prompts.map((i) => i.toJson()).toList()));
    await p.setString('docs', json.encode(docs.map((i) => i.toJson()).toList()));
    await p.setStringList('logs', logs);
  }

  void _log(String a) { setState(() => logs.insert(0, "[${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2,'0')}] $a")); _save(); }

  void _import() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r != null) {
      String c = await File(r.files.single.path!).readAsString();
      List<Prompt> imp = [];
      for (var b in c.split('===')) {
        if (b.trim().isEmpty) continue;
        String cat = 'МОНІТОРИНГ', title = 'БЕЗ НАЗВИ', text = ''; bool isT = false;
        for (var l in b.trim().split('\n')) {
          String lw = l.toLowerCase().trim();
          if (lw.startsWith('категорія:')) cat = l.split(':').last.trim().toUpperCase();
          else if (lw.startsWith('назва:')) title = l.split(':').last.trim();
          else if (lw.startsWith('текст:')) { text = l.split(':').last.trim(); isT = true; }
          else if (isT) text += "\n$l";
        }
        if (text.isNotEmpty) imp.add(Prompt(id: DateTime.now().millisecondsSinceEpoch.toString() + title, title: title, content: text.trim(), category: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].contains(cat) ? cat : 'ФО'));
      }
      setState(() => prompts.addAll(imp)); _log("Імпорт: ${imp.length} записів"); _save();
    }
  }

  void _addP({Prompt? p}) {
    final tC = TextEditingController(text: p?.title ?? ''); final cC = TextEditingController(text: p?.content ?? '');
    String sC = p?.category ?? 'ФО';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (c, setS) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F), title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(isExpanded: true, value: sC, items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setS(() => sC = v!)),
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'НАЗВА')),
        const SizedBox(height: 10), TextField(controller: cC, maxLines: 3, decoration: const InputDecoration(labelText: 'ЗМІСТ {VAR}')),
      ]),
      actions: [
        if (p != null) TextButton(onPressed: () { setState(() => prompts.remove(p)); _save(); Navigator.pop(ctx); }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          setState(() { if (p == null) prompts.add(Prompt(id: DateTime.now().toString(), title: tC.text, content: cC.text, category: sC)); else { p.title = tC.text; p.content = cC.text; p.category = sC; } });
          _save(); Navigator.pop(ctx);
        }, child: const Text('ЗБЕРЕГТИ'))
      ],
    )));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory(); final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path))); _save();
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: () { if (++_taps >= 7) { isMatrixMode.value = !isMatrixMode.value; _taps = 0; HapticFeedback.vibrate(); } }, child: Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: isMatrixMode.value ? Colors.greenAccent : Colors.white))),
        actions: [
          IconButton(icon: const Icon(Icons.analytics, color: Colors.yellow), onPressed: () {
            Map<String, int> s = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0}; int tot = prompts.length;
            for (var p in prompts) if (s.containsKey(p.category)) s[p.category] = s[p.category]! + 1;
            showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: const Color(0xFF040E22), title: const Text('SYS_STATS'), content: Column(mainAxisSize: MainAxisSize.min, children: s.entries.map((e) => Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}')]), LinearProgressIndicator(value: tot == 0 ? 0 : e.value / tot, color: Colors.blue), const SizedBox(height: 8)])).toList())));
          }),
          IconButton(icon: const Icon(Icons.receipt_long), onPressed: () => showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('LOGS'), content: SizedBox(width: double.maxFinite, height: 300, child: ListView.builder(itemCount: logs.length, itemBuilder: (cc, i) => Text(logs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent))))))),
          IconButton(icon: const Icon(Icons.download, color: Colors.blue), onPressed: _import),
        ],
        bottom: TabBar(controller: _tc, isScrollable: true, tabs: cats.map((c) => Tab(text: c)).toList()),
      ),
      body: Stack(children: [
        CustomPaint(painter: TopoGridPainter(isMatrixMode.value), child: Container()),
        TabBarView(controller: _tc, children: cats.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenu(onLog: _log);
          if (cat == 'ДОКУМЕНТИ') return docs.isEmpty ? const Center(child: Text('[ ФАЙЛІВ НЕМАЄ ]')) : ListView.builder(itemCount: docs.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05), child: ListTile(leading: const Icon(Icons.picture_as_pdf), title: Text(docs[i].name), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() => docs.removeAt(i)); _save(); }))));
          final items = prompts.where((p) => p.category == cat).toList();
          if (items.isEmpty) return const Center(child: Text('[ ПУСТО ]'));
          items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
            child: ListTile(
              leading: IconButton(icon: Icon(items[i].isFavorite ? Icons.star : Icons.star_border, color: items[i].isFavorite ? Colors.yellow : Colors.white24), onPressed: () { setState(() => items[i].isFavorite = !items[i].isFavorite); _save(); }),
              title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(items[i].content, maxLines: 1),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _log))),
              onLongPress: () => _addP(p: items[i]),
            ),
          ));
        }).toList()),
      ]),
      floatingActionButton: _tc.index == 4 ? null : FloatingActionButton(backgroundColor: const Color(0xFF0057B7), onPressed: () => _tc.index == 5 ? _pickPDF() : _addP(), child: Icon(_tc.index == 5 ? Icons.picture_as_pdf : Icons.add, color: Colors.white)),
    );
  }
}

// --- TOOLS MENU ---
class ToolsMenu extends StatelessWidget {
  final Function(String) onLog; const ToolsMenu({super.key, required this.onLog});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    _t(context, 'DORKS', 'Google Конструктор', Icons.travel_explore, DorksScreen(onLog: onLog)),
    _t(context, 'SCANNER', 'Екстракція (IP/Ph/Email)', Icons.radar, ScannerScreen(onLog: onLog)),
    _t(context, 'EXIF', 'Аналіз метаданих', Icons.image_search, ExifScreen(onLog: onLog)),
    _t(context, 'IPN', 'Дешифратор РНОКПП', Icons.fingerprint, IpnScreen(onLog: onLog)),
    _t(context, 'FINANCE', 'Алгоритм Луна', Icons.credit_card, FinScreen(onLog: onLog)),
    _t(context, 'AUTO', 'Регіони України', Icons.directions_car, AutoScreen(onLog: onLog)),
    _t(context, 'NICKNAMES', 'Генератор', Icons.psychology, NickScreen(onLog: onLog)),
    _t(context, 'TIMELINE', 'Хронологія', Icons.timeline, TimeScreen(onLog: onLog)),
    _t(context, 'VAULT', 'Менеджер паролів', Icons.lock, VaultScreen(onLog: onLog)),
  ]);
  Widget _t(ctx, t, s, i, sc) => Card(color: Colors.white.withOpacity(0.03), child: ListTile(leading: Icon(i, color: Colors.yellow), title: Text(t), subtitle: Text(s, style: const TextStyle(fontSize: 10)), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => sc))));
}

// --- DORKS ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog; const DorksScreen({super.key, required this.onLog});
  @override State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController(); List<Map<String, String>> _d = [];
  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    setState(() => _d = [
      {'t': 'DOCUMENTS', 'd': 'Пошук документів на сайті', 'q': 'site:$s ext:pdf OR ext:docx OR ext:txt OR ext:csv'},
      {'t': 'DATABASES', 'd': 'Дампи баз даних', 'q': 'site:$s ext:sql OR ext:db OR ext:bak OR ext:dump'},
      {'t': 'CONFIGS', 'd': 'Файли конфігурацій', 'q': 'site:$s ext:env OR ext:conf OR ext:ini OR ext:xml'},
      {'t': 'CAMERAS', 'd': 'Відкриті веб-камери', 'q': 'site:$s inurl:view/view.shtml OR inurl:axis-cgi/jpg'},
      {'t': 'ADMIN PANELS', 'd': 'Панелі авторизації', 'q': 'site:$s inurl:admin OR inurl:login OR inurl:wp-admin'},
      {'t': 'PASSWORDS', 'd': 'Логи з паролями', 'q': 'site:$s "password" ext:txt OR ext:log'}
    ]); widget.onLog("Dorks: $s");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('DORKS')), body: Column(children: [ Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ДОМЕН'))), ElevatedButton(onPressed: _gen, child: const Text('GENERATE')), Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.all(8), child: ListTile(title: Text(_d[i]['t']!), subtitle: Text(_d[i]['d']!), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _d[i]['q']!))))))) ]));
}

// --- SCANNER ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog; const ScannerScreen({super.key, required this.onLog});
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController(); List<Map<String, String>> _r = []; late AnimationController _l; bool _sc = false;
  @override void initState() { super.initState(); _l = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  @override void dispose() { _l.dispose(); super.dispose(); }
  void _load() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx']);
    if (r != null) {
      final file = File(r.files.single.path!); String txt = "";
      if (r.files.single.extension == 'docx') { final arc = ZipDecoder().decodeBytes(await file.readAsBytes()); for (var f in arc) if (f.name == 'word/document.xml') txt = utf8.decode(f.content).replaceAll(RegExp(r'<[^>]*>'), ' '); } else txt = await file.readAsString();
      setState(() => _c.text = txt);
    }
  }
  void _scan() async {
    setState(() { _sc = true; _r.clear(); }); _l.repeat(); await Future.delayed(const Duration(seconds: 2));
    String t = _c.text;
    final i = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'IP'});
    final p = RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'PHONE'});
    final e = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'EMAIL'});
    final u = RegExp(r'(?:https?:\/\/)?(?:www\.)?(?:t\.me|instagram\.com|facebook\.com|vk\.com|x\.com)\/[a-zA-Z0-9_.-]+').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'SOCIAL'});
    setState(() { _r = [...i, ...p, ...e, ...u]; _sc = false; }); _l.stop(); widget.onLog("Scan: ${_r.length} obj");
  }
  bool _en(String v) => v.contains('.ru') || v.contains('+7') || v.contains('vk.com') || v.contains('mail.ru');
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('SCANNER'), actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _load)]), body: Column(children: [
    Stack(children: [ Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'INPUT'))), if (_sc) AnimatedBuilder(animation: _l, builder: (c, _) => Positioned(top: 20 + (_l.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.red, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)])))) ]),
    ElevatedButton(onPressed: _scan, child: const Text('RUN SCAN')),
    Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => Card(color: _en(_r[i]['v']!) ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.05), child: ListTile(title: Text(_r[i]['v']!, style: TextStyle(color: _en(_r[i]['v']!) ? Colors.redAccent : Colors.greenAccent)), subtitle: Text(_r[i]['t']!, style: const TextStyle(fontSize: 10)), trailing: IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: _r[i]['v']!)))))))
  ]));
}

// --- EXIF ---
class ExifScreen extends StatefulWidget {
  final Function(String) onLog; const ExifScreen({super.key, required this.onLog});
  @override State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _d = {};
  void _p() async { FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image); if (r != null) { final t = await readExifFromBytes(await File(r.files.single.path!).readAsBytes()); setState(() => _d = t); widget.onLog("Exif analyzed"); } }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('EXIF')), body: Column(children: [ ElevatedButton(onPressed: _p, child: const Text('PICK PHOTO')), Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => ListTile(title: Text(_d.keys.elementAt(i), style: const TextStyle(fontSize: 12)), subtitle: Text(_d.values.elementAt(i).toString(), style: const TextStyle(color: Colors.greenAccent))))) ]));
}

// --- IPN ---
class IpnScreen extends StatefulWidget {
  final Function(String) onLog; const IpnScreen({super.key, required this.onLog});
  @override State<IpnScreen> createState() => _IpnScreenState();
}
class _IpnScreenState extends State<IpnScreen> {
  final _c = TextEditingController(); Map<String, String>? _r;
  void _d() {
    String s = _c.text.trim(); if (s.length != 10) return;
    DateTime d = DateTime(1899, 12, 31).add(Duration(days: int.parse(s.substring(0, 5)))); int a = DateTime.now().year - d.year;
    setState(() => _r = {'ДАТА НАРОДЖЕННЯ': "${d.day}.${d.month}.${d.year}", 'ВІК': "$a", 'СТАТЬ': int.parse(s[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча'});
    widget.onLog("IPN decoded");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('IPN')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '10 ЦИФР')), const SizedBox(height: 10), ElevatedButton(onPressed: _d, child: const Text('DECODE')), if (_r != null) ..._r!.entries.map((e) => ListTile(title: Text(e.key), subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent, fontSize: 18)))) ])));
}

// --- FINANCE ---
class FinScreen extends StatefulWidget {
  final Function(String) onLog; const FinScreen({super.key, required this.onLog});
  @override State<FinScreen> createState() => _FinScreenState();
}
class _FinScreenState extends State<FinScreen> {
  final _c = TextEditingController(); String _r = "";
  void _ch() {
    String cc = _c.text.replaceAll(' ', ''); if (cc.isEmpty) return;
    int s = 0; bool a = false; for (int i = cc.length - 1; i >= 0; i--) { int n = int.parse(cc[i]); if (a) { n *= 2; if (n > 9) n -= 9; } s += n; a = !a; }
    setState(() => _r = s % 10 == 0 ? "ВАЛІДНА КАРТКА" : "НЕ КОРЕКТНА"); widget.onLog("Fin check");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('FINANCE')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР КАРТКИ')), const SizedBox(height: 10), ElevatedButton(onPressed: _ch, child: const Text('LUHN CHECK')), const SizedBox(height: 20), Text(_r, style: TextStyle(fontSize: 24, color: _r.contains('ВАЛІДНА') ? Colors.greenAccent : Colors.redAccent)) ])));
}

// --- AUTO ---
class AutoScreen extends StatefulWidget {
  final Function(String) onLog; const AutoScreen({super.key, required this.onLog});
  @override State<AutoScreen> createState() => _AutoScreenState();
}
class _AutoScreenState extends State<AutoScreen> {
  final _c = TextEditingController(); String _r = "";
  final Map<String, String> _reg = {'AA': 'м. Київ', 'KA': 'м. Київ', 'TT': 'м. Київ', 'AB': 'Вінницька', 'KB': 'Вінницька', 'AC': 'Волинська', 'AE': 'Дніпропетровська', 'KE': 'Дніпропетровська', 'AH': 'Донецька', 'AM': 'Житомирська', 'AO': 'Закарпатська', 'AP': 'Запорізька', 'AT': 'Івано-Франківська', 'AI': 'Київська обл', 'BA': 'Кіровоградська', 'BB': 'Луганська', 'BC': 'Львівська', 'HC': 'Львівська', 'BE': 'Миколаївська', 'BH': 'Одеська', 'HH': 'Одеська', 'BI': 'Полтавська', 'BK': 'Рівненська', 'BM': 'Сумська', 'BO': 'Тернопільська', 'AX': 'Харківська', 'KX': 'Харківська', 'BT': 'Херсонська', 'BX': 'Хмельницька', 'CA': 'Черкаська', 'CB': 'Чернігівська', 'CE': 'Чернівецька', 'AK': 'АР Крим', 'CH': 'м. Севастополь'};
  void _ch() { String s = _c.text.trim().toUpperCase(); if (s.length < 2) return; setState(() => _r = _reg[s.substring(0, 2)] ?? "Невідомий регіон / Новий формат"); widget.onLog("Auto check"); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('AUTO')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР (АА1234ВВ)')), const SizedBox(height: 10), ElevatedButton(onPressed: _ch, child: const Text('CHECK REGION')), const SizedBox(height: 20), Text(_r, style: const TextStyle(fontSize: 24, color: Colors.greenAccent)) ])));
}

// --- NICKNAMES ---
class NickScreen extends StatefulWidget {
  final Function(String) onLog; const NickScreen({super.key, required this.onLog});
  @override State<NickScreen> createState() => _NickScreenState();
}
class _NickScreenState extends State<NickScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _g() { String s = _c.text.trim().toLowerCase(); if (s.isEmpty) return; setState(() => _r = [s, "${s}_osint", "the_$s", "real_$s", "${s}2026", "$s.ua", "$s.dev", "$s.sec", "$s@gmail.com", "$s@proton.me"]); widget.onLog("Nicks gen"); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('NICKS')), body: Column(children: [ Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, decoration: const InputDecoration(labelText: 'БАЗОВЕ СЛОВО'))), ElevatedButton(onPressed: _g, child: const Text('GENERATE')), Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => ListTile(title: Text(_r[i], style: const TextStyle(color: Colors.greenAccent)), trailing: IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: _r[i])))))) ]));
}

// --- TIMELINE ---
class TimeScreen extends StatefulWidget {
  final Function(String) onLog; const TimeScreen({super.key, required this.onLog});
  @override State<TimeScreen> createState() => _TimeScreenState();
}
class _TimeScreenState extends State<TimeScreen> {
  List<Map<String, String>> _e = [];
  @override void initState() { super.initState(); _l(); }
  void _l() async { final p = await SharedPreferences.getInstance(); final d = p.getString('tl'); if (d != null) setState(() => _e = List<Map<String, String>>.from(json.decode(d).map((x) => Map<String, String>.from(x)))); }
  void _s() async { final p = await SharedPreferences.getInstance(); p.setString('tl', json.encode(_e)); }
  void _a() {
    final dC = TextEditingController(), tC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('НОВА ПОДІЯ'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: dC, decoration: const InputDecoration(labelText: 'Дата (ДД.ММ.РР)')), TextField(controller: tC, decoration: const InputDecoration(labelText: 'Подія'))]), actions: [ElevatedButton(onPressed: () { setState(() => _e.add({'d': dC.text, 't': tC.text})); _s(); Navigator.pop(c); }, child: const Text('ADD'))]));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('TIMELINE')), body: ListView.builder(itemCount: _e.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.circle, size: 12, color: Colors.blue), title: Text(_e[i]['d']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)), subtitle: Text(_e[i]['t']!), trailing: IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () { setState(() => _e.removeAt(i)); _s(); }))), floatingActionButton: FloatingActionButton(onPressed: _a, child: const Icon(Icons.add)));
}

// --- VAULT ---
class VaultScreen extends StatefulWidget {
  final Function(String) onLog; const VaultScreen({super.key, required this.onLog});
  @override State<VaultScreen> createState() => _VaultScreenState();
}
class _VaultScreenState extends State<VaultScreen> {
  List<Map<String, String>> _v = [];
  @override void initState() { super.initState(); _l(); }
  void _l() async { final p = await SharedPreferences.getInstance(); final d = p.getString('vt'); if (d != null) setState(() => _v = List<Map<String, String>>.from(json.decode(d).map((x) => Map<String, String>.from(x)))); }
  void _s() async { final p = await SharedPreferences.getInstance(); p.setString('vt', json.encode(_v)); }
  void _a() {
    final sC = TextEditingController(), pC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('СХОВИЩЕ'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: sC, decoration: const InputDecoration(labelText: 'Ресурс/Логін')), TextField(controller: pC, decoration: const InputDecoration(labelText: 'Пароль'))]), actions: [ElevatedButton(onPressed: () { setState(() => _v.add({'s': sC.text, 'p': pC.text})); _s(); Navigator.pop(c); }, child: const Text('SAVE'))]));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('VAULT')), body: ListView.builder(itemCount: _v.length, itemBuilder: (c, i) => Card(color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.all(8), child: ListTile(leading: const Icon(Icons.lock, color: Colors.yellow), title: Text(_v[i]['s']!, style: const TextStyle(color: Colors.greenAccent)), subtitle: Text(_v[i]['p']!), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: _v[i]['p']!))), IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () { setState(() => _v.removeAt(i)); _s(); })])))), floatingActionButton: FloatingActionButton(onPressed: _a, child: const Icon(Icons.add)));
}

// --- GEN SCREEN ---
class GenScreen extends StatefulWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override State<GenScreen> createState() => _GenScreenState();
}
class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _c = {}; bool _comp = false; List<TextSpan> _s = []; int _l = 0; Timer? _t;
  final List<PromptEnhancer> _e = [
    PromptEnhancer(name: 'CoT (Chain of Thought)', desc: 'Покрокове мислення', pros: 'Висока точність', cons: 'Довга відповідь', rec: 'Для логіки', payload: 'Пояснюй хід думок крок за кроком (Step-by-step) перед фінальною відповіддю.'),
    PromptEnhancer(name: 'ToT (Tree of Thoughts)', desc: 'Дерево думок', pros: 'Аналіз гіпотез', cons: 'Повільно', rec: 'Коли мало даних', payload: 'Згенеруй 3 гіпотези. Проаналізуй кожну і обери найбільш імовірну.'),
    PromptEnhancer(name: 'Persona (Експерт)', desc: 'Професійна роль', pros: 'Сухий стиль', cons: '-', rec: 'Для звітів', payload: 'Дій як старший OSINT-аналітик. Твоя відповідь має бути максимально точною.'),
    PromptEnhancer(name: 'BLUF', desc: 'Висновок спочатку', pros: 'Економія часу', cons: 'Менше деталей', rec: 'Для керівництва', payload: 'Використовуй формат BLUF (Bottom Line Up Front).'),
    PromptEnhancer(name: 'JSON', desc: 'Видача кодом', pros: 'Машинний формат', cons: 'Тільки текст', rec: 'Для екстракції', payload: 'Поверни результат ВИКЛЮЧНО у форматі валідного JSON.'),
  ];

  @override void initState() { super.initState(); final r = RegExp(r'\{([^}]+)\}'); for (var m in r.allMatches(widget.p.content)) _c[m.group(1)!] = TextEditingController(); }
  
  void _compF() {
    _s.clear(); String t = widget.p.content; int last = 0; final r = RegExp(r'\{([^}]+)\}');
    for (var m in r.allMatches(t)) {
      if (m.start > last) _s.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      String v = _c[m.group(1)!]!.text; _s.add(TextSpan(text: v.isEmpty ? "{${m.group(1)}}" : v, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))); last = m.end;
    }
    if (last < t.length) _s.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));
    
    final sel = _e.where((e) => e.isSelected).toList();
    if (sel.isNotEmpty) {
      _s.add(const TextSpan(text: "\n\n### SYSTEM_INSTRUCTIONS:\n", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)));
      for (var e in sel) _s.add(TextSpan(text: "- ${e.payload}\n", style: const TextStyle(color: Colors.yellow)));
    }
    
    setState(() { _comp = true; _l = 0; }); _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 5), (tm) { if (!mounted) return; setState(() { _l += 15; if (_l >= _s.map((e) => e.text!.length).fold(0, (a,b)=>a+b)) tm.cancel(); }); });
    widget.onLog("Comp: ${widget.p.title}");
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.p.title)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    if (!_comp) ...[..._c.keys.map((k) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: _c[k], decoration: InputDecoration(labelText: k)))), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), onPressed: _compF, child: const Text('КОМПІЛЮВАТИ'))],
    if (_comp) ...[
      ElevatedButton.icon(icon: const Icon(Icons.flash_on, color: Colors.yellow), label: const Text('ТАКТИЧНЕ ПІДСИЛЕННЯ'), onPressed: () {
        showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF0A152F), builder: (c) => StatefulBuilder(builder: (cc, sM) => Container(padding: const EdgeInsets.all(16), height: MediaQuery.of(context).size.height * 0.7, child: Column(children: [
          const Text('ПІДСИЛЕННЯ ПРОМПТУ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.yellow)), const SizedBox(height: 10),
          Expanded(child: ListView.builder(itemCount: _e.length, itemBuilder: (ccc, i) => Card(color: Colors.white.withOpacity(0.05), child: CheckboxListTile(title: Text(_e[i].name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_e[i].desc, style: const TextStyle(fontSize: 12)), Text("ПЕРЕВАГИ: ${_e[i].pros}", style: const TextStyle(fontSize: 10, color: Colors.greenAccent)), Text("ДЛЯ: ${_e[i].rec}", style: const TextStyle(fontSize: 10, color: Colors.blueAccent))]), value: _e[i].isSelected, onChanged: (v) { sM(() => _e[i].isSelected = v!); if (_comp) _compF(); })))),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), onPressed: () => Navigator.pop(c), child: const Text('ЗАКРИТИ'))
        ]))));
      }), const SizedBox(height: 10),
      Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.black, child: SingleChildScrollView(child: RichText(text: TextSpan(children: _gV()))))), const SizedBox(height: 10),
      Row(children: [Expanded(child: ElevatedButton(onPressed: () => setState(() => _comp = false), child: const Text('РЕСЕТ'))), const SizedBox(width: 10), Expanded(child: ElevatedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _s.map((x) => x.text).join())), child: const Text('COPY')))]),
    ]
  ])));
  List<TextSpan> _gV() { List<TextSpan> r = []; int c = 0; for (var x in _s) { if (c + x.text!.length <= _l) { r.add(x); c += x.text!.length; } else { r.add(TextSpan(text: x.text!.substring(0, _l - c), style: x.style)); break; } } return r; }
}

class PDFViewerScreen extends StatelessWidget { final PDFDoc doc; const PDFViewerScreen({super.key, required this.doc}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path)); }
