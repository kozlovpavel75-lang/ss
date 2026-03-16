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

// ─────────────────────────────────────────────
// ГЛОБАЛЬНИЙ СТАН
// ─────────────────────────────────────────────
ValueNotifier<bool> isMatrixMode = ValueNotifier(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const PromptApp());
}

// ─────────────────────────────────────────────
// КОЛЬОРИ
// ─────────────────────────────────────────────
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
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content,
      'category': category, 'isFavorite': isFavorite};
  factory Prompt.fromJson(Map<String, dynamic> j) => Prompt(
      id: j['id'], title: j['title'], content: j['content'],
      category: j['category'], isFavorite: j['isFavorite'] ?? false);
  List<String> get variables {
    final reg = RegExp(r'\{([^}]+)\}');
    return reg.allMatches(content).map((m) => m.group(1)!).toSet().toList();
  }
}

class PDFDoc {
  String id, name, path;
  PDFDoc({required this.id, required this.name, required this.path});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory PDFDoc.fromJson(Map<String, dynamic> j) =>
      PDFDoc(id: j['id'], name: j['name'], path: j['path']);
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
  static const _chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#\$%^&*";
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
            fontSize: 16, fontFamily: 'monospace',
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
      builder: (_, matrix, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.bg,
          fontFamily: 'monospace',
          appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: matrix ? Colors.black87 : AppColors.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: matrix ? const BorderSide(color: Colors.green) : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: matrix ? const BorderSide(color: Colors.green) : const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: matrix ? const BorderSide(color: Colors.greenAccent, width: 2) : const BorderSide(color: AppColors.uaBlue, width: 2),
            ),
            labelStyle: TextStyle(color: matrix ? Colors.greenAccent : AppColors.textSec),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.uaBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// СПЛЕШ ЕКРАН
// ─────────────────────────────────────────────
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
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SizedBox.expand(child: Image.asset('assets/splash.png', fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('🔱', style: TextStyle(fontSize: 64)),
        SizedBox(height: 16),
        Text('UKR_OSINT', style: TextStyle(color: AppColors.uaYellow, fontSize: 22, letterSpacing: 4)),
      ])),
    )),
  );
}

// ─────────────────────────────────────────────
// ГОЛОВНИЙ ЕКРАН
// ─────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<Prompt> prompts = []; List<PDFDoc> docs = []; List<String> logs = [];
  int _taps = 0;
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  static const cats = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];

  @override void initState() {
    super.initState();
    _tc = TabController(length: cats.length, vsync: this);
    _tc.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  @override void dispose() { _tc.dispose(); _searchCtrl.dispose(); super.dispose(); }

  String _uid() => '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999).toString().padLeft(4,'0')}';

  void _load() async {
    final p = await SharedPreferences.getInstance();
    final pS = p.getString('prompts'); final dS = p.getString('docs'); final lS = p.getStringList('logs');
    if (!mounted) return;
    setState(() {
      if (pS != null) try { prompts = (json.decode(pS) as List).map((i) => Prompt.fromJson(i)).toList(); } catch(_) {}
      if (dS != null) try { docs    = (json.decode(dS) as List).map((i) => PDFDoc.fromJson(i)).toList(); } catch(_) {}
      if (lS != null) logs = lS;
      if (prompts.isEmpty) prompts = [Prompt(id: '1', title: 'ПОШУК ПЕРСОНИ', category: 'ФО', content: 'Аналіз даних: {ПІБ}\nМісто: {Місто}', isFavorite: true)];
    });
  }

  void _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('prompts', json.encode(prompts.map((i) => i.toJson()).toList()));
    await p.setString('docs',    json.encode(docs.map((i) => i.toJson()).toList()));
    await p.setStringList('logs', logs.take(100).toList());
  }

  void _log(String a) {
    if (!mounted) return;
    final now = DateTime.now();
    final ts = "[${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}]";
    setState(() { logs.insert(0, "$ts $a"); if (logs.length > 100) logs.removeLast(); });
    _save();
  }

  void _import() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null || r.files.single.path == null) return;
    try {
      String c = await File(r.files.single.path!).readAsString();
      List<Prompt> imp = [];
      for (var b in c.split('===')) {
        if (b.trim().isEmpty) continue;
        String cat = 'МОНІТОРИНГ', title = 'БЕЗ НАЗВИ', text = ''; bool isT = false;
        for (var l in b.trim().split('\n')) {
          String lw = l.toLowerCase().trim();
          if (lw.startsWith('категорія:')) {
            String raw = l.substring(10).trim().toUpperCase();
            if (raw.contains('ФІЗ') || raw == 'ФО') cat = 'ФО';
            else if (raw.contains('ЮР') || raw == 'ЮО') cat = 'ЮО';
            else if (raw.contains('ГЕО')) cat = 'ГЕОІНТ';
            else cat = 'МОНІТОРИНГ';
          } else if (lw.startsWith('назва:')) { title = l.substring(6).trim(); }
            else if (lw.startsWith('текст:')) { text = l.substring(6).trim(); isT = true; }
            else if (isT) text += "\n$l";
        }
        if (text.isNotEmpty && title.isNotEmpty) imp.add(Prompt(id: _uid(), title: title, content: text.trim(), category: cat));
      }
      if (!mounted) return;
      setState(() => prompts.addAll(imp));
      _log("Імпортовано: ${imp.length} записів з TXT");
      _save();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Успішно імпортовано ${imp.length} промптів', style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: AppColors.bgCard,
      ));
    } catch(e) { _log("Помилка імпорту TXT"); }
  }

  void _addP({Prompt? p}) {
    final tC = TextEditingController(text: p?.title ?? '');
    final cC = TextEditingController(text: p?.content ?? '');
    String sC = (p != null && ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].contains(p.category)) ? p.category : 'ФО';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (c, setS) => AlertDialog(
      backgroundColor: isMatrixMode.value ? Colors.black87 : AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isMatrixMode.value ? Colors.green : AppColors.uaBlue, width: 0.5)),
      title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ', style: TextStyle(color: isMatrixMode.value ? Colors.greenAccent : AppColors.textPri, fontWeight: FontWeight.w500, letterSpacing: 1.5, fontSize: 15)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(dropdownColor: AppColors.bgCard, isExpanded: true, value: sC,
          items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setS(() => sC = v!)),
        const SizedBox(height: 10),
        TextField(controller: tC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'НАЗВА')),
        const SizedBox(height: 10),
        TextField(controller: cC, maxLines: 4, style: const TextStyle(color: AppColors.textPri, fontSize: 13), decoration: const InputDecoration(labelText: 'ЗМІСТ {VAR}')),
      ])),
      actions: [
        if (p != null) TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            setState(() { p.title = "█████████"; p.content = "████████████████"; });
            HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 600));
            if (!mounted) return;
            setState(() => prompts.remove(p)); _save();
          },
          child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.redAccent)),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('СКАСУВАТИ', style: TextStyle(color: isMatrixMode.value ? Colors.green : AppColors.textSec))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isMatrixMode.value ? Colors.green.withOpacity(0.2) : AppColors.uaBlue),
          onPressed: () {
            if (tC.text.trim().isEmpty) return;
            setState(() {
              if (p == null) { prompts.add(Prompt(id: _uid(), title: tC.text.trim(), content: cC.text.trim(), category: sC)); _log("Створено: ${tC.text.trim()}"); }
              else { p.title = tC.text.trim(); p.content = cC.text.trim(); p.category = sC; _log("Оновлено: ${tC.text.trim()}"); }
            });
            _save(); Navigator.pop(ctx);
          },
          child: Text('ЗБЕРЕГТИ', style: TextStyle(color: isMatrixMode.value ? Colors.greenAccent : Colors.white)),
        ),
      ],
    )));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r == null || r.files.single.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${r.files.single.name}';
    await File(r.files.single.path!).copy(path);
    if (!mounted) return;
    setState(() => docs.add(PDFDoc(id: _uid(), name: r.files.single.name, path: path)));
    _log("Додано документ: ${r.files.single.name}");
    _save();
  }

  List<Prompt> _filtered(String cat) {
    var items = prompts.where((p) => p.category == cat).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((p) => p.title.toLowerCase().contains(q) || p.content.toLowerCase().contains(q)).toList();
    }
    items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
    return items;
  }

  // ── APPBAR ──
  PreferredSizeWidget _appBar() {
    final m = isMatrixMode.value;
    if (_searchActive) return AppBar(
      leading: IconButton(icon: Icon(Icons.arrow_back, color: m ? Colors.greenAccent : AppColors.textSec), onPressed: () => setState(() { _searchActive = false; _searchQuery = ''; _searchCtrl.clear(); })),
      title: TextField(
        controller: _searchCtrl, autofocus: true,
        style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri, fontSize: 15),
        decoration: const InputDecoration(hintText: 'Пошук...', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
      bottom: _tabBar(),
    );

    return AppBar(
      title: GestureDetector(
        onTap: () { if (++_taps >= 7) { isMatrixMode.value = !isMatrixMode.value; _taps = 0; HapticFeedback.vibrate(); } },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🔱', style: TextStyle(fontSize: 20, color: m ? Colors.greenAccent : AppColors.uaYellow)),
          const SizedBox(width: 8),
          Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.5, fontSize: 17, color: m ? Colors.greenAccent : AppColors.uaYellow)),
        ]),
      ),
      actions: [
        IconButton(icon: Icon(Icons.search, color: m ? Colors.greenAccent : AppColors.textSec, size: 22), onPressed: () => setState(() => _searchActive = true)),
        IconButton(icon: Icon(Icons.analytics, color: m ? Colors.green : AppColors.uaYellow, size: 22), onPressed: _showStats),
        IconButton(icon: Icon(Icons.receipt_long, color: m ? Colors.green : AppColors.textSec, size: 22), onPressed: _showLogs),
        IconButton(icon: Icon(Icons.download, color: m ? Colors.greenAccent : AppColors.accent, size: 22), onPressed: _import),
      ],
      bottom: _tabBar(),
    );
  }

  TabBar _tabBar() => TabBar(
    controller: _tc, isScrollable: true,
    labelColor: isMatrixMode.value ? Colors.greenAccent : AppColors.uaYellow,
    unselectedLabelColor: AppColors.textSec,
    indicatorColor: isMatrixMode.value ? Colors.greenAccent : AppColors.uaYellow,
    tabs: cats.map((c) => Tab(text: c)).toList(),
  );

  void _showStats() {
    final m = isMatrixMode.value;
    final s = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0};
    int tot = prompts.length;
    for (var p in prompts) if (s.containsKey(p.category)) s[p.category] = s[p.category]! + 1;
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: m ? Colors.black87 : AppColors.bg,
      title: Text('СТАТИСТИКА БАЗИ', style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: s.entries.map((e) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}', style: TextStyle(color: m ? Colors.greenAccent : AppColors.accent, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: tot == 0 ? 0 : e.value / tot, color: m ? Colors.green : AppColors.uaBlue, backgroundColor: Colors.white10),
        const SizedBox(height: 10),
      ])).toList()),
    ));
  }

  void _showLogs() => showDialog(context: context, builder: (c) => AlertDialog(
    backgroundColor: Colors.black,
    title: const Text('ЖУРНАЛ ДІЙ', style: TextStyle(color: Colors.greenAccent)),
    content: SizedBox(width: double.maxFinite, height: 300, child: logs.isEmpty
        ? const Center(child: Text('НЕМАЄ ЗАПИСІВ', style: TextStyle(color: Colors.white24)))
        : ListView.builder(itemCount: logs.length, itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(logs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontFamily: 'monospace'))))),
    actions: [
      TextButton(onPressed: () { setState(() { logs.clear(); _save(); }); Navigator.pop(c); }, child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent))),
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('CLOSE', style: TextStyle(color: Colors.white54))),
    ],
  ));

  @override Widget build(BuildContext context) {
    final m = isMatrixMode.value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _appBar(),
      body: Stack(children: [
        // Фон
        if (m) const MatrixEffect() else CustomPaint(painter: _TopoGridPainter(), child: Container()),
        // Синьо-жовта смужка
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false, child: Column(children: [
          SizedBox(height: AppBar().preferredSize.height + 48),
          Container(height: 2, decoration: const BoxDecoration(gradient: LinearGradient(
            colors: [AppColors.uaBlue, AppColors.uaBlue, AppColors.uaYellow, AppColors.uaYellow],
            stops: [0, 0.5, 0.5, 1],
          ))),
        ]))),
        // Контент
        SafeArea(child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TabBarView(controller: _tc, children: cats.map((cat) {
            if (cat == 'ІНСТРУМЕНТИ') return ToolsMenu(onLog: _log);
            if (cat == 'ДОКУМЕНТИ') return _buildDocs();
            return _buildPromptList(cat);
          }).toList()),
        )),
      ]),
      floatingActionButton: _tc.index == 4 ? null : FloatingActionButton(
        backgroundColor: m ? Colors.green.withOpacity(0.3) : AppColors.uaBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: m ? Colors.greenAccent : AppColors.uaYellow, width: 1.5)),
        onPressed: () => _tc.index == 5 ? _pickPDF() : _addP(),
        child: Icon(_tc.index == 5 ? Icons.picture_as_pdf : Icons.add, color: m ? Colors.greenAccent : Colors.white),
      ),
    );
  }

  Widget _buildDocs() {
    final m = isMatrixMode.value;
    if (docs.isEmpty) return const Center(child: Text('[ ФАЙЛІВ НЕМАЄ ]', style: TextStyle(color: Colors.white24)));
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: docs.length,
      itemBuilder: (c, i) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.white.withOpacity(m ? 0.02 : 0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
        child: ListTile(
          leading: Icon(Icons.picture_as_pdf, color: m ? Colors.green : AppColors.accent),
          title: Text(docs[i].name, style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))),
          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () {
            showDialog(context: context, builder: (_) => AlertDialog(
              backgroundColor: AppColors.bgCard,
              title: const Text('Видалити документ?', style: TextStyle(fontSize: 15)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ні', style: TextStyle(color: AppColors.textSec))),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { setState(() => docs.removeAt(i)); _save(); Navigator.pop(context); }, child: const Text('Так')),
              ],
            ));
          }),
        ),
      ),
    );
  }

  Widget _buildPromptList(String cat) {
    final m = isMatrixMode.value;
    final items = _filtered(cat);
    if (items.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.inbox_outlined, color: AppColors.textHint, size: 48),
      const SizedBox(height: 12),
      Text(_searchQuery.isNotEmpty ? 'Нічого не знайдено' : '[ ПУСТО ]', style: const TextStyle(color: Colors.white24)),
    ]));

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: items.length,
      onReorder: _searchQuery.isNotEmpty ? (_, __) {} : (oldIdx, newIdx) {
        setState(() {
          if (newIdx > oldIdx) newIdx -= 1;
          final item = items.removeAt(oldIdx); items.insert(newIdx, item);
          prompts.removeWhere((p) => p.category == cat); prompts.addAll(items);
        });
        _save();
      },
      itemBuilder: (ctx, i) {
        final p = items[i];
        return Card(
          key: ValueKey(p.id),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: Colors.white.withOpacity(m ? 0.02 : (p.isFavorite ? 0.05 : 0.03)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.isFavorite ? AppColors.uaYellow.withOpacity(0.3) : AppColors.border),
          ),
          child: ListTile(
            leading: IconButton(
              icon: Icon(p.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: p.isFavorite ? (m ? Colors.green : AppColors.uaYellow) : Colors.white24),
              onPressed: () { setState(() => p.isFavorite = !p.isFavorite); _save(); },
            ),
            title: Text(p.title, style: TextStyle(fontWeight: FontWeight.bold, color: m ? Colors.greenAccent : AppColors.textPri)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: m ? Colors.green : Colors.grey, fontSize: 11)),
              if (p.variables.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 4, children: p.variables.take(4).map((v) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('{$v}', style: const TextStyle(fontSize: 9, color: AppColors.textSec, fontFamily: 'monospace')),
                )).toList()),
              ),
            ]),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: p, onLog: _log))),
            onLongPress: () => _addP(p: p),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// МЕНЮ ІНСТРУМЕНТІВ — всі 9 збережено
// ─────────────────────────────────────────────
class ToolsMenu extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenu({super.key, required this.onLog});

  @override Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 12, bottom: 90),
    children: [
      _t(context, 'DORKS',       'Google Конструктор (Новини, Документи)',      Icons.travel_explore,      DorksScreen(onLog: onLog)),
      _t(context, 'СКАНЕР',      'Екстракція (IP/Телефон/Email/Соцмережі)',     Icons.radar,               ScannerScreen(onLog: onLog)),
      _t(context, 'EXIF',        'Аналіз метаданих фотографій',                 Icons.image_search,        ExifScreen(onLog: onLog)),
      _t(context, 'ІПН',         'Дешифратор РНОКПП (дата/стать/вік)',          Icons.fingerprint,         IpnScreen(onLog: onLog)),
      _t(context, 'ФІНАНСИ',     'Перевірка карток (Алгоритм Луна)',            Icons.credit_card,         FinScreen(onLog: onLog)),
      _t(context, 'АВТО',        'Визначення регіону за номером',               Icons.directions_car,      AutoScreen(onLog: onLog)),
      _t(context, 'НІКНЕЙМИ',    'Генератор варіантів нікнеймів',               Icons.psychology,          NickScreen(onLog: onLog)),
      _t(context, 'ХРОНОЛОГІЯ',  'Таймлайн подій розслідування',                Icons.timeline,            TimeScreen(onLog: onLog)),
      _t(context, 'СЕЙФ',        'Захищений менеджер паролів',                  Icons.lock,                VaultScreen(onLog: onLog)),
    ],
  );

  Widget _t(BuildContext ctx, String t, String s, IconData i, Widget sc) => Card(
    color: Colors.white.withOpacity(0.03),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(width: 40, height: 40,
        decoration: BoxDecoration(color: AppColors.uaBlue.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(i, color: AppColors.uaYellow, size: 20),
      ),
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
      subtitle: Text(s, style: const TextStyle(fontSize: 10, color: AppColors.textSec)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => sc)),
    ),
  );
}

// ─────────────────────────────────────────────
// ГЕНЕРАТОР ПРОМПТІВ — з підсвіткою та методиками
// ─────────────────────────────────────────────
class GenScreen extends StatefulWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override State<GenScreen> createState() => _GenScreenState();
}

class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _c = {};
  bool _comp = false;
  List<TextSpan> _spans = [];
  int _visLen = 0;
  Timer? _typingTimer;

  // ── РОЗШИРЕНИЙ СПИСОК МЕТОДИК ──
  final List<PromptEnhancer> _enhancers = [
    PromptEnhancer(
      name: 'CoT — Chain of Thought',
      desc: 'Покрокове мислення: модель пояснює хід міркувань перед відповіддю',
      pros: 'Висока точність на складних задачах, менше галюцинацій',
      cons: 'Значно збільшує довжину відповіді та витрату токенів',
      conflicts: 'Конфліктує з JSON Format (порушує структуру)',
      rec: 'Логічні задачі, аналіз, дедукція, математика',
      payload: 'Пояснюй свій хід думок крок за кроком (Step-by-step) перед тим як дати фінальну відповідь.',
    ),
    PromptEnhancer(
      name: 'ToT — Tree of Thoughts',
      desc: 'Дерево думок: генерує кілька гіпотез, оцінює і обирає найкращу',
      pros: 'Найкращий для неоднозначних даних, аналіз конкуруючих версій',
      cons: 'Дуже повільно, великий контекст, дорого по токенах',
      conflicts: 'Конфліктує з BLUF (протилежні підходи до структури)',
      rec: 'OSINT з мало даних, коли треба розглянути кілька версій',
      payload: 'Згенеруй 3 різні гіпотези щодо запиту. Для кожної: обґрунтування, слабкі місця, ймовірність. Потім обери та обґрунтуй найімовірнішу.',
    ),
    PromptEnhancer(
      name: 'Persona — OSINT Аналітик',
      desc: 'Рольова інструкція: модель виступає як старший аналітик',
      pros: 'Сухий, фаховий стиль без "води", підходить для звітів',
      cons: 'Може відмовляти на "чутливі" запити через роль',
      conflicts: 'Слабо конфліктує з CoT (можна комбінувати)',
      rec: 'Офіційні звіти, аналітичні записки, брифінги',
      payload: 'Дій як старший OSINT-аналітик з 10-річним досвідом. Відповідь має бути точною, сухою, без емоцій та загальних фраз. Факти і висновки — тільки на основі наданих даних.',
    ),
    PromptEnhancer(
      name: 'BLUF — Bottom Line Up Front',
      desc: 'Військовий формат: висновок першим, деталі після',
      pros: 'Економія часу, ідеально для керівництва та оперативних зведень',
      cons: 'Можна пропустити важливий контекст у деталях',
      conflicts: 'Конфліктує з ToT (там висновок — в кінці)',
      rec: 'Оперативні зведення, доповіді керівництву, терміновий аналіз',
      payload: 'Використовуй формат BLUF (Bottom Line Up Front): перший рядок — головний висновок в 1-2 реченні. Потім: деталі, обґрунтування, джерела.',
    ),
    PromptEnhancer(
      name: 'JSON Output',
      desc: 'Структурований вивід: результат тільки у валідному JSON',
      pros: 'Машиночитаємий формат, легко парсити і вставляти в бази',
      cons: 'Втрачається контекст, модель іноді додає текст поза JSON',
      conflicts: 'Конфліктує з CoT та ToT (ламає формат)',
      rec: 'Екстракція сутностей, парсинг, передача даних між системами',
      payload: 'Поверни результат ВИКЛЮЧНО у форматі валідного JSON. Без тексту, пояснень або markdown до чи після. Тільки JSON-об\'єкт.',
    ),
    PromptEnhancer(
      name: 'DSP — Decomposed Subtasks',
      desc: 'Декомпозиція: розбиває складне завдання на підзадачі',
      pros: 'Ефективний на многокрокових задачах, зменшує помилки',
      cons: 'Довга відповідь, може "загубитися" в підзадачах',
      conflicts: 'Добре поєднується з CoT; погано з JSON',
      rec: 'Складний OSINT-аналіз, розслідування, стратегічне планування',
      payload: 'Розбий це завдання на підзадачі. Для кожної підзадачі: сформулюй питання, дай відповідь, зроби мікровисновок. Фінальний висновок — після всіх підзадач.',
    ),
    PromptEnhancer(
      name: 'ReAct — Reason + Act',
      desc: 'Чергує міркування і "дії" (що б зробила модель далі)',
      pros: 'Добре імітує агентну поведінку, показує процес роботи',
      cons: 'Може галюцинувати "дії" яких не виконала',
      conflicts: 'Погано поєднується з BLUF та JSON',
      rec: 'Симуляція кроків розслідування, планування операцій',
      payload: 'Чергуй ДУМКА → ДІЯ → СПОСТЕРЕЖЕННЯ. Думка: що аналізую. Дія: що роблю. Спостереження: що отримав. Повторюй цикл до фінального висновку.',
    ),
    PromptEnhancer(
      name: 'Критик — Devil\'s Advocate',
      desc: 'Після відповіді модель сама критикує свої висновки',
      pros: 'Підвищує надійність, знаходить слабкі місця в аналізі',
      cons: 'Подвоює обсяг відповіді',
      conflicts: 'Конфліктує з BLUF (затягує структуру)',
      rec: 'Перевірка версій, оцінка ризиків, верифікація даних',
      payload: 'Після надання відповіді — зіграй роль критика: знайди 2-3 слабких місця у власних висновках, альтернативні пояснення і що може спростувати твій аналіз.',
    ),
    PromptEnhancer(
      name: 'Few-Shot — Приклади',
      desc: 'Надає моделі приклади формату відповіді перед основним запитом',
      pros: 'Стабільний формат виводу, модель точніше розуміє очікування',
      cons: 'Витрачає токени на приклади, треба готувати вручну',
      conflicts: 'Добре поєднується з Persona та JSON',
      rec: 'Коли потрібен чіткий повторюваний формат (таблиці, профілі)',
      payload: 'Приклад формату відповіді: [ПОЛЕ]: [ЗНАЧЕННЯ]. Дотримуйся цього формату для всіх результатів. Якщо дані відсутні — пиши "N/A".',
    ),
    PromptEnhancer(
      name: 'Confidence Score — Впевненість',
      desc: 'Модель додає оцінку достовірності до кожного твердження',
      pros: 'Чесність щодо невизначеності, ключово для OSINT',
      cons: 'Відсотки умовні, можуть вводити в оману',
      conflicts: 'Добре поєднується з майже усіма методиками',
      rec: 'Верифікація даних, оцінка джерел, звіти з невизначеністю',
      payload: 'До кожного ключового твердження або висновку додай оцінку достовірності: [HIGH / MEDIUM / LOW] та коротке пояснення чому саме так.',
    ),
  ];

  @override void initState() {
    super.initState();
    final r = RegExp(r'\{([^}]+)\}');
    for (var m in r.allMatches(widget.p.content)) _c[m.group(1)!] = TextEditingController();
    if (_c.isEmpty) _compile();
  }

  @override void dispose() {
    _typingTimer?.cancel();
    for (final c in _c.values) c.dispose();
    super.dispose();
  }

  void _compile() {
    _spans.clear();
    String t = widget.p.content; int last = 0;
    final r = RegExp(r'\{([^}]+)\}');

    // Основний текст з підсвіткою: зелений = текст промпту, червоний = введені дані
    for (var m in r.allMatches(t)) {
      if (m.start > last) _spans.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      final val = _c[m.group(1)!]?.text ?? '';
      _spans.add(TextSpan(
        text: val.isEmpty ? "{${m.group(1)}}" : val,
        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
      ));
      last = m.end;
    }
    if (last < t.length) _spans.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));

    // Активні методики — жовтим
    final sel = _enhancers.where((e) => e.isSelected).toList();
    if (sel.isNotEmpty) {
      _spans.add(const TextSpan(text: "\n\n### SYSTEM_INSTRUCTIONS:\n", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)));
      for (var e in sel) _spans.add(TextSpan(text: "— ${e.payload}\n", style: const TextStyle(color: Colors.yellow)));
    }

    // Анімація typing
    setState(() { _comp = true; _visLen = 0; });
    _typingTimer?.cancel();
    final total = _spans.fold(0, (s, x) => s + (x.text?.length ?? 0));
    _typingTimer = Timer.periodic(const Duration(milliseconds: 5), (tm) {
      if (!mounted) return;
      setState(() { _visLen += 15; if (_visLen >= total) tm.cancel(); });
    });
    widget.onLog("Компіляція: ${widget.p.title}");
    FocusScope.of(context).unfocus();
  }

  // Повертає видиму частину (typing effect)
  List<TextSpan> _visible() {
    final res = <TextSpan>[]; int c = 0;
    for (var x in _spans) {
      final len = x.text?.length ?? 0;
      if (c + len <= _visLen) { res.add(x); c += len; }
      else { res.add(TextSpan(text: x.text!.substring(0, _visLen - c), style: x.style)); break; }
    }
    return res;
  }

  String get _plainText => _spans.map((x) => x.text ?? '').join();

  void _showEnhancers() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (_, setM) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('⚡ ТАКТИЧНЕ ПІДСИЛЕННЯ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.uaYellow, fontSize: 16, letterSpacing: 1)),
          const SizedBox(height: 4),
          const Text('Додає інструкції до промпту. Впливає на стиль і формат відповіді LLM.',
              style: TextStyle(fontSize: 10, color: AppColors.textSec), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Expanded(child: ListView.builder(
            itemCount: _enhancers.length,
            itemBuilder: (_, i) {
              final e = _enhancers[i];
              return Card(
                color: e.isSelected ? AppColors.uaBlue.withOpacity(0.15) : Colors.white.withOpacity(0.03),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: e.isSelected ? AppColors.uaYellow.withOpacity(0.4) : AppColors.border),
                ),
                child: CheckboxListTile(
                  value: e.isSelected,
                  activeColor: AppColors.uaYellow,
                  checkColor: Colors.black,
                  onChanged: (v) { setM(() => e.isSelected = v!); if (_comp) _compile(); },
                  title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPri)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),
                    Text(e.desc, style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
                    const SizedBox(height: 6),
                    // Плюси
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('+ ', style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
                      Expanded(child: Text(e.pros, style: const TextStyle(fontSize: 10, color: Colors.greenAccent))),
                    ]),
                    // Мінуси
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('− ', style: TextStyle(fontSize: 10, color: AppColors.danger)),
                      Expanded(child: Text(e.cons, style: const TextStyle(fontSize: 10, color: AppColors.danger))),
                    ]),
                    // Конфлікти
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('⚠ ', style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
                      Expanded(child: Text(e.conflicts, style: const TextStyle(fontSize: 10, color: Colors.orangeAccent))),
                    ]),
                    // Рекомендація
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('✓ ', style: TextStyle(fontSize: 10, color: AppColors.accent)),
                      Expanded(child: Text(e.rec, style: const TextStyle(fontSize: 10, color: AppColors.accent))),
                    ]),
                    const SizedBox(height: 4),
                  ]),
                  isThreeLine: true,
                ),
              );
            },
          )),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('ЗАСТОСУВАТИ')),
        ]),
      )),
    );
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF091630),
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ГЕНЕРАТОР ПРОМПТІВ', style: TextStyle(fontSize: 13, letterSpacing: 1.5)),
      Text(widget.p.title, style: const TextStyle(fontSize: 10, color: AppColors.textSec), overflow: TextOverflow.ellipsis),
    ])),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // ── Поля параметрів ──
        if (!_comp) ...[
          Expanded(child: ListView(children: _c.keys.map((k) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(controller: _c[k], style: const TextStyle(color: AppColors.textPri), decoration: InputDecoration(labelText: k)),
          )).toList())),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
            onPressed: _compile,
            child: const Text('КОМПІЛЮВАТИ ЗАПИТ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ],
        // ── Результат ──
        if (_comp) ...[
          // Кнопка підсилення
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _enhancers.any((e) => e.isSelected) ? AppColors.uaYellow : AppColors.border),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(Icons.flash_on, color: _enhancers.any((e) => e.isSelected) ? AppColors.uaYellow : Colors.white38, size: 18),
            label: Text(
              _enhancers.any((e) => e.isSelected)
                  ? '⚡ АКТИВНІ: ${_enhancers.where((e) => e.isSelected).map((e) => e.name.split(' ')[0]).join(', ')}'
                  : 'ТАКТИЧНЕ ПІДСИЛЕННЯ',
              style: TextStyle(
                color: _enhancers.any((e) => e.isSelected) ? AppColors.uaYellow : Colors.white38,
                fontSize: 12, letterSpacing: 0.8,
              ),
            ),
            onPressed: _showEnhancers,
          ),
          const SizedBox(height: 10),
          // Вікно результату
          Expanded(child: Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _comp ? AppColors.success.withOpacity(0.3) : AppColors.border)),
            child: SingleChildScrollView(child: RichText(text: TextSpan(children: _visible()))),
          )),
          const SizedBox(height: 10),
          // Кнопки дій
          Row(children: [
            if (_c.isNotEmpty) ...[
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () => setState(() => _comp = false),
                child: const Icon(Icons.refresh, color: Colors.white54),
              )),
              const SizedBox(width: 8),
            ],
            Expanded(flex: 2, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue, minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.copy, size: 16, color: Colors.white),
              label: const Text('COPY', style: TextStyle(color: Colors.white, letterSpacing: 1)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _plainText));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
              },
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.send, size: 16, color: Colors.white),
              label: const Text('В LLM', style: TextStyle(color: Colors.white, letterSpacing: 1)),
              onPressed: () { Share.share(_plainText); widget.onLog("Промпт: відправлено в LLM"); },
            )),
          ]),
        ],
      ]),
    ),
  );
}

// ─────────────────────────────────────────────
// PDF ПЕРЕГЛЯДАЧ
// ─────────────────────────────────────────────
class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: Text(doc.name, overflow: TextOverflow.ellipsis)),
    body: PDFView(filePath: doc.path),
  );
}

// ─────────────────────────────────────────────
// DORKS
// ─────────────────────────────────────────────
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController(); List<Map<String, String>> _d = [];
  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _d = [
      {'t': 'ДОКУМЕНТИ',          'd': 'PDF, Word, Excel, CSV на сайті',       'q': 'site:$s ext:pdf OR ext:docx OR ext:xlsx OR ext:csv'},
      {'t': 'НОВИНИ / ЗГАДКИ',    'd': 'Згадки в новинах та пресі',            'q': '"$s" inurl:news OR intitle:news'},
      {'t': 'ВІДКРИТІ ДИРЕКТОРІЇ','d': 'Пошук індексів файлів',                'q': 'site:$s intitle:"index of"'},
      {'t': 'СОЦМЕРЕЖІ',          'd': "Зв'язок з соцмережами та профілями",   'q': 'site:linkedin.com/in OR site:facebook.com "$s"'},
      {'t': 'ПІДДОМЕНИ',          'd': 'Тестові та робочі піддомени',          'q': 'site:*.$s -www'},
      {'t': 'КОНФІГИ / БАЗИ',     'd': 'Файли налаштувань, SQL дампи',         'q': 'site:$s ext:env OR ext:sql OR ext:db OR ext:log'},
      {'t': 'АДМІН-ПАНЕЛІ',       'd': 'Пошук панелей керування',              'q': 'site:$s inurl:admin OR inurl:login OR inurl:dashboard'},
      {'t': 'API / КЛЮЧІ',        'd': 'Відкриті API endpoints та ключі',      'q': 'site:$s inurl:api OR "api_key" OR "secret_key"'},
      {'t': 'КАМЕРИ / IoT',       'd': 'Відкриті відеокамери та пристрої',     'q': 'site:$s inurl:"/view/index.shtml" OR intitle:"webcam"'},
      {'t': 'EMAIL / КОНТАКТИ',   'd': 'Публічні пошти та контактні дані',     'q': '"@$s" email OR site:$s email'},
    ]);
    widget.onLog("Dorks: згенеровано для $s");
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('КОНСТРУКТОР DORKS'),
      actions: [if (_d.isNotEmpty) TextButton(
        onPressed: () { Clipboard.setData(ClipboardData(text: _d.map((e) => e['q']).join('\n'))); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано всі dorks'), backgroundColor: AppColors.uaBlue)); },
        child: const Text('COPY ALL', style: TextStyle(color: AppColors.uaYellow, fontSize: 12)),
      )]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), decoration: const InputDecoration(labelText: 'ЦІЛЬОВИЙ ДОМЕН АБО КЛЮЧОВЕ СЛОВО'))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue), onPressed: _gen, child: const Text('ЗГЕНЕРУВАТИ', style: TextStyle(color: Colors.white))),
      Expanded(child: _d.isEmpty
          ? const Center(child: Text('Введіть домен і натисніть ЗГЕНЕРУВАТИ', style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _d.length,
              itemBuilder: (c, i) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                color: Colors.white.withOpacity(0.03),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
                child: ListTile(
                  title: Text(_d[i]['t']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 12)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_d[i]['d']!, style: const TextStyle(fontSize: 10, color: AppColors.textSec)),
                    const SizedBox(height: 4),
                    Text(_d[i]['q']!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textPri)),
                  ]),
                  trailing: IconButton(icon: const Icon(Icons.copy, size: 16, color: AppColors.uaYellow), onPressed: () {
                    Clipboard.setData(ClipboardData(text: _d[i]['q']!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
                  }),
                ),
              ),
            ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// СКАНЕР — розширений (з підтримкою DOCX)
// ─────────────────────────────────────────────
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController();
  List<Map<String, String>> _r = [];
  late AnimationController _anim;
  bool _scanning = false;

  static const _typeConf = {
    'IP':         (icon: Icons.dns_outlined,          color: Color(0xFF6FA8DC), label: 'IP-адреси'),
    'ТЕЛЕФОН':    (icon: Icons.phone_outlined,         color: Color(0xFFE8A05A), label: 'Телефони'),
    'EMAIL':      (icon: Icons.alternate_email,        color: Color(0xFF80D8B0), label: 'Електронні адреси'),
    'СОЦМЕРЕЖА':  (icon: Icons.share_outlined,         color: Color(0xFFA78BFA), label: 'Соцмережі / посилання'),
    'GPS':        (icon: Icons.location_on_outlined,   color: Color(0xFF4ADE80), label: 'GPS координати'),
    'HASH':       (icon: Icons.tag,                    color: Color(0xFFFF6B6B), label: 'Хеші (MD5/SHA)'),
  };

  @override void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  @override void dispose() { _anim.dispose(); _c.dispose(); super.dispose(); }

  void _loadFile() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx']);
    if (r == null) return;
    final file = File(r.files.single.path!); String txt = "";
    if (r.files.single.extension == 'docx') {
      final arc = ZipDecoder().decodeBytes(await file.readAsBytes());
      for (var f in arc) if (f.name == 'word/document.xml') txt = utf8.decode(f.content as List<int>).replaceAll(RegExp(r'<[^>]*>'), ' ');
    } else { txt = await file.readAsString(); }
    setState(() => _c.text = txt);
  }

  void _scan() async {
    FocusScope.of(context).unfocus();
    setState(() { _scanning = true; _r.clear(); }); _anim.repeat();
    await Future.delayed(const Duration(seconds: 2));
    final t = _c.text;

    final results = <Map<String, String>>[];
    RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'IP'}));
    RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'ТЕЛЕФОН'}));
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'EMAIL'}));
    RegExp(r'(?:https?:\/\/)?(?:www\.)?(?:t\.me|instagram\.com|facebook\.com|vk\.com|x\.com|twitter\.com)\/[a-zA-Z0-9_.\-]+').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'СОЦМЕРЕЖА'}));
    RegExp(r'[-+]?(?:[1-8]?\d(?:\.\d+)?|90(?:\.0+)?)[,\s]+[-+]?(?:180(?:\.0+)?|(?:(?:1[0-7]\d)|(?:[1-9]?\d))(?:\.\d+)?)').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'GPS'}));
    RegExp(r'\b[0-9a-fA-F]{32}\b|\b[0-9a-fA-F]{40}\b|\b[0-9a-fA-F]{64}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'HASH'}));

    _anim.stop();
    if (!mounted) return;
    setState(() { _r = results; _scanning = false; });
    widget.onLog("Сканер: знайдено ${_r.length} об'єктів");
  }

  bool _isEnemy(String v) => v.contains('.ru') || v.contains('+7') || v.contains('vk.com') || v.contains('mail.ru');

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      title: const Text('РАДАР-СКАНЕР'),
      actions: [
        IconButton(icon: const Icon(Icons.file_open, color: AppColors.accent), onPressed: _loadFile, tooltip: 'Завантажити файл'),
        if (_r.isNotEmpty) TextButton(
          onPressed: () { Clipboard.setData(ClipboardData(text: _r.map((e) => e['v']).join('\n'))); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано все'), backgroundColor: AppColors.uaBlue)); },
          child: const Text('COPY ALL', style: TextStyle(color: AppColors.uaYellow, fontSize: 12)),
        ),
      ],
    ),
    body: Column(children: [
      Stack(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), decoration: const InputDecoration(labelText: 'ВВЕДІТЬ АБО ЗАВАНТАЖТЕ ТЕКСТ'))),
        if (_scanning) AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Positioned(top: 20 + (_anim.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.red, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)]))),
        ),
      ]),
      ElevatedButton(onPressed: _scan, child: const Text('СКАНУВАТИ', style: TextStyle(color: Colors.white, letterSpacing: 1))),
      Expanded(child: _r.isEmpty
          ? const Center(child: Text('Введіть текст і натисніть СКАНУВАТИ', style: TextStyle(color: Colors.white24)))
          : _buildResults(),
      ),
    ]),
  );

  Widget _buildResults() {
    final grouped = <String, List<String>>{};
    for (var item in _r) { grouped.putIfAbsent(item['t']!, () => []).add(item['v']!); }
    return ListView(padding: const EdgeInsets.all(8), children: grouped.entries.map((entry) {
      final conf = _typeConf[entry.key];
      final icon = conf?.icon ?? Icons.tag;
      final color = conf?.color ?? AppColors.accent;
      final label = conf?.label ?? entry.key;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(7)), child: Icon(icon, color: color, size: 17)),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSec, letterSpacing: 0.5)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text('${entry.value.length}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold))),
          ])),
          const Divider(color: AppColors.border, height: 0),
          ...entry.value.map((v) => InkWell(
            onTap: () { Clipboard.setData(ClipboardData(text: v)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано: $v'), backgroundColor: AppColors.uaBlue, duration: const Duration(seconds: 1))); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: _isEnemy(v) ? Colors.red.withOpacity(0.08) : null),
              child: Row(children: [
                if (_isEnemy(v)) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.warning_amber, color: Colors.redAccent, size: 14)),
                Expanded(child: Text(v, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: _isEnemy(v) ? Colors.redAccent : AppColors.textPri))),
                const Text('copy', style: TextStyle(fontSize: 10, color: AppColors.uaYellow, letterSpacing: 0.5)),
              ]),
            ),
          )),
          InkWell(
            onTap: () { Clipboard.setData(ClipboardData(text: entry.value.join('\n'))); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано ${label.toLowerCase()}'), backgroundColor: AppColors.uaBlue, duration: const Duration(seconds: 1))); },
            child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))), child: const Text('+ copy all', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.accent, letterSpacing: 0.5))),
          ),
        ]),
      );
    }).toList());
  }
}

// ─────────────────────────────────────────────
// EXIF АНАЛІЗАТОР
// ─────────────────────────────────────────────
class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _d = {};
  void _p() async {
    try {
      FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
      if (r == null) return;
      final bytes = await File(r.files.single.path!).readAsBytes();
      final t = await readExifFromBytes(bytes);
      if (!mounted) return;
      setState(() => _d = t.isEmpty ? {'Статус': 'Метадані відсутні або очищені'} : t);
      widget.onLog("EXIF: проаналізовано ${r.files.single.name}");
    } catch (e) {
      if (!mounted) return;
      setState(() => _d = {'Помилка': 'Не вдалося прочитати метадані: $e'});
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('EXIF АНАЛІЗАТОР')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: ElevatedButton.icon(
        icon: const Icon(Icons.image_search, size: 18), label: const Text('ОБРАТИ ФОТО'),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
        onPressed: _p,
      )),
      Expanded(child: _d.isEmpty
          ? const Center(child: Text('ЧЕКАЮ НА ФАЙЛ...', style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _d.length,
              itemBuilder: (c, i) => Card(
                color: Colors.white.withOpacity(0.03),
                margin: const EdgeInsets.only(bottom: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
                child: ListTile(dense: true,
                  title: Text(_d.keys.elementAt(i), style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                  subtitle: Text(_d.values.elementAt(i).toString(), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  onTap: () => Clipboard.setData(ClipboardData(text: '${_d.keys.elementAt(i)}: ${_d.values.elementAt(i)}')),
                ),
              ),
            ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// ІПН ДЕШИФРАТОР
// ─────────────────────────────────────────────
class IpnScreen extends StatefulWidget {
  final Function(String) onLog;
  const IpnScreen({super.key, required this.onLog});
  @override State<IpnScreen> createState() => _IpnScreenState();
}
class _IpnScreenState extends State<IpnScreen> {
  final _c = TextEditingController(); Map<String, String>? _r;
  void _decode() {
    String s = _c.text.trim(); if (s.length != 10) return;
    try {
      DateTime d = DateTime(1899, 12, 31).add(Duration(days: int.parse(s.substring(0, 5))));
      int age = DateTime.now().year - d.year;
      setState(() => _r = {
        'ДАТА НАРОДЖЕННЯ': "${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}",
        'ПОВНИХ РОКІВ': "$age",
        'СТАТЬ': int.parse(s[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча',
      });
      widget.onLog("ІПН: дешифровано");
    } catch(_) {}
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('ДЕШИФРАТОР ІПН')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'ВВЕДІТЬ 10 ЦИФР РНОКПП')),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _decode, child: const Text('ДЕШИФРУВАТИ', style: TextStyle(color: Colors.white))),
      const SizedBox(height: 20),
      if (_r != null) ..._r!.entries.map((e) => ListTile(
        title: Text(e.key, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
      )),
    ])),
  );
}

// ─────────────────────────────────────────────
// ВАЛІДАТОР КАРТОК (Алгоритм Луна)
// ─────────────────────────────────────────────
class FinScreen extends StatefulWidget {
  final Function(String) onLog;
  const FinScreen({super.key, required this.onLog});
  @override State<FinScreen> createState() => _FinScreenState();
}
class _FinScreenState extends State<FinScreen> {
  final _c = TextEditingController(); String _r = "";
  void _check() {
    String cc = _c.text.replaceAll(' ', '').replaceAll('-', ''); if (cc.isEmpty) return;
    int s = 0; bool a = false;
    for (int i = cc.length - 1; i >= 0; i--) {
      int n = int.tryParse(cc[i]) ?? 0;
      if (a) { n *= 2; if (n > 9) n -= 9; }
      s += n; a = !a;
    }
    setState(() => _r = s % 10 == 0 ? "✅ ВАЛІДНА КАРТКА" : "❌ НЕ КОРЕКТНА (ПОМИЛКА ЛУНА)");
    widget.onLog("Фінанси: перевірка картки");
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('ВАЛІДАТОР КАРТОК')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, style: const TextStyle(color: AppColors.textPri, fontFamily: 'monospace', letterSpacing: 2), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'НОМЕР КАРТКИ')),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _check, child: const Text('ПЕРЕВІРИТИ (АЛГОРИТМ ЛУНА)', style: TextStyle(color: Colors.white))),
      const SizedBox(height: 30),
      Text(_r, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _r.contains('ВАЛІДНА') ? Colors.greenAccent : Colors.redAccent)),
    ])),
  );
}

// ─────────────────────────────────────────────
// АВТО НОМЕРИ
// ─────────────────────────────────────────────
class AutoScreen extends StatefulWidget {
  final Function(String) onLog;
  const AutoScreen({super.key, required this.onLog});
  @override State<AutoScreen> createState() => _AutoScreenState();
}
class _AutoScreenState extends State<AutoScreen> {
  final _c = TextEditingController(); String _r = "";
  static const _reg = {'AA':'м. Київ','KA':'м. Київ','TT':'м. Київ','AB':'Вінницька обл.','KB':'Вінницька обл.','AC':'Волинська обл.','AE':'Дніпропетровська обл.','KE':'Дніпропетровська обл.','AH':'Донецька обл.','AM':'Житомирська обл.','AO':'Закарпатська обл.','AP':'Запорізька обл.','AT':'Івано-Франківська обл.','AI':'Київська обл.','BA':'Кіровоградська обл.','BB':'Луганська обл.','BC':'Львівська обл.','HC':'Львівська обл.','BE':'Миколаївська обл.','BH':'Одеська обл.','HH':'Одеська обл.','BI':'Полтавська обл.','BK':'Рівненська обл.','BM':'Сумська обл.','BO':'Тернопільська обл.','AX':'Харківська обл.','KX':'Харківська обл.','BT':'Херсонська обл.','BX':'Хмельницька обл.','CA':'Черкаська обл.','CB':'Чернігівська обл.','CE':'Чернівецька обл.','AK':'АР Крим','CH':'м. Севастополь'};
  void _check() { String s = _c.text.trim().toUpperCase(); if (s.length < 2) return; setState(() => _r = _reg[s.substring(0, 2)] ?? "Невідомий регіон / Новий формат"); widget.onLog("Авто: пошук регіону"); }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('АВТО НОМЕРИ')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, style: const TextStyle(color: AppColors.textPri, letterSpacing: 2), textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'НОМЕР (напр. АА1234ВВ)')),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _check, child: const Text('ВИЗНАЧИТИ РЕГІОН', style: TextStyle(color: Colors.white))),
      const SizedBox(height: 30),
      if (_r.isNotEmpty) Text(_r, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
    ])),
  );
}

// ─────────────────────────────────────────────
// ГЕНЕРАТОР НІКНЕЙМІВ
// ─────────────────────────────────────────────
class NickScreen extends StatefulWidget {
  final Function(String) onLog;
  const NickScreen({super.key, required this.onLog});
  @override State<NickScreen> createState() => _NickScreenState();
}
class _NickScreenState extends State<NickScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _gen() {
    String s = _c.text.trim().toLowerCase().replaceAll(' ', '_'); if (s.isEmpty) return;
    setState(() => _r = [s, "${s}_osint", "the_$s", "real_$s", "${s}2025", "${s}2026", "$s.ua", "sec_$s", "$s.priv", "${s}_analyst", "ua_$s", "$s@gmail.com", "$s@proton.me", "$s@ukr.net"]);
    widget.onLog("Нікнейми: генерація для $s");
    FocusScope.of(context).unfocus();
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('ГЕНЕРАТОР НІКІВ'),
      actions: [if (_r.isNotEmpty) TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: _r.join('\n'))); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано всі варіанти'), backgroundColor: AppColors.uaBlue)); }, child: const Text('COPY ALL', style: TextStyle(color: AppColors.uaYellow, fontSize: 12)))],
    ),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'БАЗОВЕ СЛОВО АБО ПРІЗВИЩЕ'))),
      ElevatedButton(onPressed: _gen, child: const Text('ЗГЕНЕРУВАТИ ВАРІАНТИ', style: TextStyle(color: Colors.white))),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _r.length,
        itemBuilder: (c, i) => Card(
          color: Colors.white.withOpacity(0.03),
          margin: const EdgeInsets.only(bottom: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
          child: ListTile(dense: true,
            title: Text(_r[i], style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            trailing: IconButton(icon: const Icon(Icons.copy, size: 16, color: AppColors.uaYellow), onPressed: () { Clipboard.setData(ClipboardData(text: _r[i])); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1))); }),
          ),
        ),
      )),
    ]),
  );
}

// ─────────────────────────────────────────────
// ХРОНОЛОГІЯ ПОДІЙ
// ─────────────────────────────────────────────
class TimeScreen extends StatefulWidget {
  final Function(String) onLog;
  const TimeScreen({super.key, required this.onLog});
  @override State<TimeScreen> createState() => _TimeScreenState();
}
class _TimeScreenState extends State<TimeScreen> {
  List<Map<String, String>> _events = [];
  @override void initState() { super.initState(); _load(); }
  void _load() async { final p = await SharedPreferences.getInstance(); final d = p.getString('timeline'); if (d != null && mounted) setState(() => _events = List<Map<String, String>>.from(json.decode(d).map((x) => Map<String, String>.from(x)))); }
  void _save() async { final p = await SharedPreferences.getInstance(); p.setString('timeline', json.encode(_events)); }
  void _add() {
    final dC = TextEditingController(text: "${DateTime.now().day.toString().padLeft(2,'0')}.${DateTime.now().month.toString().padLeft(2,'0')}.${DateTime.now().year}");
    final tC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('НОВА ПОДІЯ', style: TextStyle(color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: dC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Дата')),
        const SizedBox(height: 10),
        TextField(controller: tC, maxLines: 3, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Опис події')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
        ElevatedButton(onPressed: () { setState(() => _events.add({'d': dC.text, 't': tC.text})); _save(); Navigator.pop(c); widget.onLog("Таймлайн: додано подію"); }, child: const Text('ДОДАТИ', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('ХРОНОЛОГІЯ')),
    body: _events.isEmpty
        ? const Center(child: Text('ПОДІЙ НЕМАЄ', style: TextStyle(color: Colors.white24)))
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: _events.length,
            itemBuilder: (c, i) => Card(
              color: Colors.white.withOpacity(0.03),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
              child: ListTile(
                leading: const Icon(Icons.circle, size: 10, color: AppColors.uaBlue),
                title: Text(_events[i]['d']!, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                subtitle: Text(_events[i]['t']!, style: const TextStyle(color: AppColors.textSec)),
                trailing: IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () { setState(() => _events.removeAt(i)); _save(); }),
              ),
            ),
          ),
    floatingActionButton: FloatingActionButton(
      backgroundColor: AppColors.uaBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.uaYellow, width: 1.5)),
      onPressed: _add,
      child: const Icon(Icons.add, color: Colors.white),
    ),
  );
}

// ─────────────────────────────────────────────
// СЕЙФ З ПАРОЛЕМ
// ─────────────────────────────────────────────
class VaultScreen extends StatefulWidget {
  final Function(String) onLog;
  const VaultScreen({super.key, required this.onLog});
  @override State<VaultScreen> createState() => _VaultScreenState();
}
class _VaultScreenState extends State<VaultScreen> {
  bool _unlocked = false, _isFirst = true;
  String _savedMp = "";
  final _mp = TextEditingController();
  List<Map<String, String>> _vault = [];

  @override void initState() { super.initState(); _load(); }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString('vault'); final mp = p.getString('master_pass');
    if (mp != null && mp.isNotEmpty) { _isFirst = false; _savedMp = mp; }
    if (d != null && mounted) setState(() => _vault = List<Map<String, String>>.from(json.decode(d).map((x) => Map<String, String>.from(x))));
    if (mounted) setState(() {});
  }

  void _saveVault() async { final p = await SharedPreferences.getInstance(); p.setString('vault', json.encode(_vault)); }

  void _setPass() async {
    if (_mp.text.length < 4) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Мінімум 4 символи!'), backgroundColor: Colors.red)); return; }
    final p = await SharedPreferences.getInstance(); p.setString('master_pass', _mp.text);
    setState(() { _savedMp = _mp.text; _isFirst = false; _unlocked = true; });
    widget.onLog("Сейф: встановлено майстер-пароль");
  }

  void _checkPass() {
    if (_mp.text == _savedMp) { setState(() => _unlocked = true); widget.onLog("Сейф: успішний вхід"); }
    else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('НЕВІРНИЙ ПАРОЛЬ!'), backgroundColor: Colors.red)); }
  }

  void _addEntry() {
    final rC = TextEditingController(), lC = TextEditingController(), pC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('НОВИЙ ЗАПИС', style: TextStyle(color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: rC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Ресурс (Сайт/Додаток)')),
        const SizedBox(height: 8),
        TextField(controller: lC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Логін / Email')),
        const SizedBox(height: 8),
        TextField(controller: pC, obscureText: true, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Пароль')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
        ElevatedButton(onPressed: () { setState(() => _vault.add({'r': rC.text, 'l': lC.text, 'p': pC.text})); _saveVault(); Navigator.pop(c); widget.onLog("Сейф: додано запис"); }, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  @override Widget build(BuildContext context) {
    if (_isFirst) return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ [НАЛАШТУВАННЯ]')),
      body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.security, size: 64, color: Colors.blueAccent),
        const SizedBox(height: 20),
        const Text('Створіть майстер-пароль. Він не підлягає відновленню!', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 20),
        TextField(controller: _mp, obscureText: true, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'ПРИДУМАЙТЕ ПАРОЛЬ')),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _setPass, child: const Text('СТВОРИТИ СЕЙФ', style: TextStyle(color: Colors.white))),
      ]))),
    );
    if (!_unlocked) return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ [ЗАБЛОКОВАНО]')),
      body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock, size: 64, color: AppColors.uaYellow),
        const SizedBox(height: 20),
        TextField(controller: _mp, obscureText: true, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'МАЙСТЕР-ПАРОЛЬ'), onSubmitted: (_) => _checkPass()),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _checkPass, child: const Text('ВІДЧИНИТИ', style: TextStyle(color: Colors.white))),
      ]))),
    );
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ [ВІДКРИТО]'), actions: [
        IconButton(icon: const Icon(Icons.lock_open, color: Colors.red), onPressed: () => setState(() { _unlocked = false; _mp.clear(); })),
      ]),
      body: _vault.isEmpty
          ? const Center(child: Text('СЕЙФ ПУСТИЙ', style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: _vault.length,
              itemBuilder: (c, i) => Card(
                color: Colors.white.withOpacity(0.04),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
                child: ListTile(
                  leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.uaYellow.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.security, color: AppColors.uaYellow, size: 18)),
                  title: Text(_vault[i]['r']!, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  subtitle: Text("${_vault[i]['l']!}\n••••••••", style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
                  isThreeLine: true,
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(icon: const Icon(Icons.copy, size: 18, color: AppColors.uaYellow), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: () { Clipboard.setData(ClipboardData(text: _vault[i]['p']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль скопійовано'), backgroundColor: AppColors.uaBlue)); }),
                    const SizedBox(height: 6),
                    IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: () { setState(() => _vault.removeAt(i)); _saveVault(); }),
                  ]),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.uaBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.uaYellow, width: 1.5)),
        onPressed: _addEntry,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ГРА KREMLIN COTTON (пасхалка — 7 тапів по назві)
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
        for (int i = 0; i < targets.length; i++) { targets[i] += 0.015; if (targets[i] > 1.1) targets[i] = -0.1; }
        if (bY >= 0) {
          bY += 0.04;
          if (bY > 0.85) {
            for (int i = 0; i < targets.length; i++) { if ((bX - targets[i]).abs() < 0.1) { score++; targets[i] = -0.5; widget.onLog("БАВОВНА! Ціль №$score"); } }
            bY = -1; bX = -1;
          }
        }
      });
    });
  }

  @override void dispose() { _timer?.cancel(); _fire.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width, h = MediaQuery.of(context).size.height;
    return Scaffold(backgroundColor: Colors.black, body: GestureDetector(
      onTapDown: (d) {
        final x = d.globalPosition.dx / w;
        if (x < 0.3) setState(() => dX = (dX - 0.1).clamp(0.05, 0.95));
        else if (x > 0.7) setState(() => dX = (dX + 0.1).clamp(0.05, 0.95));
        else if (bY < 0) setState(() { bX = dX; bY = 0.15; });
      },
      child: Stack(children: [
        Positioned(bottom: 0, left: 0, right: 0, height: 180, child: Stack(children: [
          Container(decoration: const BoxDecoration(color: Color(0xFF0A152F), borderRadius: BorderRadius.vertical(top: Radius.circular(30)))),
          Positioned(bottom: 0, left: w * 0.4, width: w * 0.2, height: 160, child: Column(children: [
            Container(width: w * 0.15, height: 100, color: AppColors.uaBlue),
            Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.uaYellow)),
          ])),
        ])),
        AnimatedBuilder(animation: _fire, builder: (_, __) => Positioned(bottom: 160, left: w * 0.45, width: w * 0.1, height: 30, child: Container(decoration: BoxDecoration(color: Colors.orange.withOpacity(_fire.value * 0.8), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.orange, blurRadius: 20 * _fire.value)])))),
        ...targets.map((tx) => AnimatedPositioned(duration: Duration.zero, bottom: 60, left: tx * w, child: const Column(children: [CircleAvatar(radius: 6, backgroundColor: Colors.grey), Icon(Icons.person, color: Colors.white, size: 35)]))),
        if (bY >= 0) AnimatedPositioned(duration: Duration.zero, top: bY * h, left: bX * w, child: const Icon(Icons.wb_sunny, color: Colors.orange, size: 30)),
        AnimatedPositioned(duration: const Duration(milliseconds: 100), top: 80, left: dX * w - 30, child: const Icon(Icons.airplanemode_active, color: AppColors.accent, size: 60)),
        Positioned(top: 40, left: 20, child: Text('SCORE: $score\nSTATUS: HOT_ZONE', style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
        Positioned(bottom: 20, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white24), onPressed: () => Navigator.pop(context))),
      ]),
    ));
  }
}
