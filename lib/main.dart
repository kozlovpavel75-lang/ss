import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:exif/exif.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const PromptApp());
}

// --- МОДЕЛІ ДАНИХ ---
class Prompt {
  String id, title, content, category;
  Prompt({required this.id, required this.title, required this.content, required this.category});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content, 'category': category};
  factory Prompt.fromJson(Map<String, dynamic> json) => Prompt(id: json['id'], title: json['title'], content: json['content'], category: json['category']);
}

class PDFDoc {
  String id, name, path;
  PDFDoc({required this.id, required this.name, required this.path});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory PDFDoc.fromJson(Map<String, dynamic> json) => PDFDoc(id: json['id'], name: json['name'], path: json['path']);
}

// --- ГОЛОВНИЙ ДОДАТОК ---
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040E22),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF0A152F),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
      home: const SplashScreen(),
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
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const MainScreen()));
      }
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: Image.asset('assets/splash.png',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity));
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
  int _secretCounter = 0;

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
  final Color uaYellow = const Color(0xFFFFD700);
  final Color uaBlue = const Color(0xFF0057B7);

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
        prompts = [Prompt(id: '1', title: 'Пошук ФО', category: 'ФО', content: 'Аналіз: {ПІБ}')];
        _logAction("Ініціалізація бази даних");
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
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      shape: RoundedRectangleBorder(side: BorderSide(color: uaYellow)),
      title: const Text('SYS.INFO', style: TextStyle(fontFamily: 'monospace')),
      content: Text('ЗАПИСІВ: ${prompts.length}\nДОКУМЕНТІВ: ${docs.length}', style: const TextStyle(fontFamily: 'monospace')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: TextStyle(color: uaYellow)))],
    ));
  }
  
  void _addOrEditPrompt({Prompt? p}) {
    final tCtrl = TextEditingController(text: p?.title ?? '');
    final cCtrl = TextEditingController(text: p?.content ?? '');
    String selectedCat = p?.category ?? 'ФО';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF0A152F),
        title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            dropdownColor: const Color(0xFF0A152F),
            value: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].contains(selectedCat) ? selectedCat : 'ФО',
            items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (val) => setDialogState(() => selectedCat = val!),
            decoration: const InputDecoration(labelText: 'КАТЕГОРІЯ'),
          ),
          const SizedBox(height: 10),
          TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'НАЗВА')),
          const SizedBox(height: 10),
          TextField(controller: cCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'КОНТЕНТ {VAR}')),
        ]),
        actions: [
          if (p != null) TextButton(onPressed: () { setState(() => prompts.remove(p)); _logAction("Видалено: ${p.title}"); _save(); Navigator.pop(ctx); }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: uaBlue),
            onPressed: () {
              setState(() {
                if (p == null) {
                  prompts.add(Prompt(id: DateTime.now().toString(), title: tCtrl.text, content: cCtrl.text, category: selectedCat));
                  _logAction("Створено: ${tCtrl.text}");
                } else {
                  p.title = tCtrl.text; p.content = cCtrl.text; p.category = selectedCat;
                  _logAction("Оновлено: ${tCtrl.text}");
                }
              });
              _save(); Navigator.pop(ctx);
            }, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.white))
          )
        ],
      )
    ));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path)));
      _logAction("Додано PDF: ${r.files.single.name}");
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: () {
            _showSysInfo();
            if (++_secretCounter >= 5) {
              _secretCounter = 0;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CottonGame()));
            }
          }),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: TabBarView(
        controller: _tabController,
        children: categories.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
          if (cat == 'ДОКУМЕНТИ') return _buildDocs();
          final items = prompts.where((p) => p.category == cat).toList();
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
            child: ListTile(
              title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)), 
              subtitle: Text(items[i].content, maxLines: 1, overflow: TextOverflow.ellipsis), 
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _logAction))),
              onLongPress: () => _addOrEditPrompt(p: items[i]),
            ),
          ));
        }).toList(),
      ),
      floatingActionButton: _tabController.index == 4 ? null : FloatingActionButton(
        backgroundColor: uaBlue,
        onPressed: () => _tabController.index == 5 ? _pickPDF() : _addOrEditPrompt(),
        child: Icon(_tabController.index == 5 ? Icons.picture_as_pdf : Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildDocs() => ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
    child: ListTile(
      title: Text(docs[i].name), leading: const Icon(Icons.file_copy, color: Colors.white54), 
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))),
      trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white24), onPressed: () {
        setState(() => docs.removeAt(i));
        _save();
      }),
    ),
  ));
}

// --- ІНСТРУМЕНТИ ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 10),
    children: [
      _t(context, 'ВАРІАНТИ НІКНЕЙМУ', 'Офлайн генерація логінів/пошт', Icons.psychology, NicknameGenScreen(onLog: onLog)),
      _t(context, 'DORKS', 'Кібер-конструктор (тільки копіювання)', Icons.travel_explore, DorksScreen(onLog: onLog)),
      _t(context, 'СКАНЕР', 'Екстракція даних', Icons.radar, ScannerScreen(onLog: onLog)),
      _t(context, 'EXIF', 'Аналіз метаданих фотографії', Icons.image_search, ExifScreen(onLog: onLog)),
    ]
  );
  
  Widget _t(ctx, t, s, i, scr) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.white.withOpacity(0.03),
    child: ListTile(leading: Icon(i, color: const Color(0xFFFFD700)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr)))
  );
}

// --- ВАРІАНТИ НІКНЕЙМУ ---
class NicknameGenScreen extends StatefulWidget {
  final Function(String) onLog;
  const NicknameGenScreen({super.key, required this.onLog});
  @override
  State<NicknameGenScreen> createState() => _NicknameGenScreenState();
}

class _NicknameGenScreenState extends State<NicknameGenScreen> {
  final _c = TextEditingController();
  List<String> _res = [];

  void _generate() {
    String s = _c.text.trim().toLowerCase();
    if (s.isEmpty) return;
    setState(() {
      _res = [
        s, "${s}_osint", "${s}_private", "the_$s", "real_$s", "${s}2026",
        "$s.ua", "$s.dev", "$s.sec", "${s}_archive",
        "$s@gmail.com", "$s@proton.me", "$s@ukr.net", "$s.osint@mail.com"
      ];
    });
    widget.onLog("Згенеровано нікнейми для: $s");
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ВАРІАНТИ НІКНЕЙМУ')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, decoration: const InputDecoration(labelText: 'ОСНОВНЕ СЛОВО / НІК')),
      const SizedBox(height: 10),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
        onPressed: _generate, child: const Text('ГЕНЕРУВАТИ ОФЛАЙН', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ),
      const SizedBox(height: 10),
      Expanded(child: ListView.builder(itemCount: _res.length, itemBuilder: (ctx, i) => Card(
        color: Colors.white.withOpacity(0.05),
        child: ListTile(
          title: Text(_res[i], style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)), 
          trailing: const Icon(Icons.copy, size: 18, color: Colors.white54), 
          onTap: () {
            Clipboard.setData(ClipboardData(text: _res[i]));
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF0057B7), content: Text('Скопійовано: ${_res[i]}'), duration: const Duration(seconds: 1)));
          }
        ),
      )))
    ])),
  );
}

// --- ВИПРАВЛЕНИЙ DORKS SCREEN З АНІМАЦІЄЮ ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}

class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<String> _d = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  void _gen() {
    String s = _t.text.trim();
    if (s.isEmpty) return;
    
    for (var i = 0; i < _d.length; i++) {
       _listKey.currentState?.removeItem(0, (ctx, anim) => const SizedBox());
    }

    setState(() {
      _d = [
        "site:$s ext:pdf",
        "site:$s inurl:admin",
        "site:$s \"password\" ext:txt",
        "site:$s intitle:\"index of\"",
        "site:$s \"login\" | \"account\"",
        "site:pastebin.com \"$s\""
      ];
    });

    widget.onLog("Dorks для: $s");

    Future.delayed(const Duration(milliseconds: 50), () {
      for (var i = 0; i < _d.length; i++) {
        _listKey.currentState?.insertItem(i, duration: Duration(milliseconds: 300 + (i * 100)));
      }
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GOOGLE DORKS')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ ДОМЕН'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
          onPressed: _gen, child: const Text('ГЕНЕРУВАТИ МАСИВ', style: TextStyle(fontWeight: FontWeight.bold))
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedList(
            key: _listKey,
            initialItemCount: _d.length,
            itemBuilder: (context, index, animation) {
              return SlideTransition(
                position: animation.drive(Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutQuart))),
                child: FadeTransition(
                  opacity: animation,
                  child: Card(
                    color: Colors.white.withOpacity(0.05),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      title: Text(_d[index], style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
                      trailing: const Icon(Icons.copy, color: Colors.white24),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _d[index]));
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF0057B7), content: Text('СКОПІЙОВАНО: ${_d[index]}'), duration: const Duration(seconds: 1)));
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        )
      ]),
    );
  }
}

// --- СКАНЕР ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _scan() {
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(_c.text).map((m) => "IP: ${m.group(0)}").toList();
    final ems = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(_c.text).map((m) => "EMAIL: ${m.group(0)}").toList();
    setState(() => _r = [...ips, ...ems]);
    widget.onLog("Сканер: знайдено ${_r.length} артефактів");
    FocusScope.of(context).unfocus();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('СКАНЕР')), 
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'Вставте текст для аналізу'))), 
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)),
        onPressed: _scan, child: const Text('ЕКСТРАКЦІЯ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ), 
      const SizedBox(height: 10),
      Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (ctx, i) => Card(
        color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          title: Text(_r[i], style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
          trailing: const Icon(Icons.copy, size: 18, color: Colors.white54),
          onTap: () {
            Clipboard.setData(ClipboardData(text: _r[i]));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано')));
          }
        )
      )))
    ])
  );
}

// --- ВИПРАВЛЕНИЙ EXIF SCREEN ---
class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override
  State<ExifScreen> createState() => _ExifScreenState();
}

class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _data = {};
  bool _isLoading = false;
  String _error = '';

  void _pick() async {
    setState(() { _isLoading = true; _error = ''; _data.clear(); });

    try {
      FilePickerResult? r = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // Критично важливо для Android 13+
      );

      if (r != null) {
        final bytes = r.files.single.bytes ?? await File(r.files.single.path!).readAsBytes();
        final tags = await readExifFromBytes(bytes);

        if (tags.isEmpty) {
          _error = 'Метадані відсутні (можливо, були видалені месенджером або соцмережею)';
        } else {
          _data = tags;
        }
        widget.onLog("EXIF: Аналіз файлу ${r.files.single.name}");
      }
    } catch (e) {
      _error = 'Помилка доступу до файлу: $e';
      widget.onLog("ERR: Помилка EXIF");
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EXIF АНАЛІЗАТОР')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
              onPressed: _isLoading ? null : _pick,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('ОБРАТИ ФОТО', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_error, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          Expanded(
            child: ListView.builder(
              itemCount: _data.length,
              itemBuilder: (ctx, i) {
                final key = _data.keys.elementAt(i);
                final value = _data[key].toString();
                return Card(
                  color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    title: Text(key, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: "$key: $value"));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дані скопійовано')));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- ПРАВИЛЬНИЙ GEN SCREEN ---
class GenScreen extends StatefulWidget {
  final Prompt p;
  final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  State<GenScreen> createState() => _GenScreenState();
}

class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  String _res = '';
  
  @override
  void initState() {
    super.initState();
    _res = widget.p.content;
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(widget.p.content)) {
      _ctrls[m.group(1)!] = TextEditingController();
    }
  }
  
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        ..._ctrls.keys.map((k) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k)),
        )),
        const SizedBox(height: 10),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
          onPressed: () {
            String t = widget.p.content;
            _ctrls.forEach((k,v) => t = t.replaceAll('{$k}', v.text.isEmpty ? '{$k}' : v.text));
            setState(() => _res = t);
            widget.onLog("Згенеровано промпт: ${widget.p.title}");
            FocusScope.of(context).unfocus();
          },
          child: const Text('КОМПІЛЮВАТИ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
        ),
        const SizedBox(height: 10),
        Expanded(child: Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(child: SelectableText(_res, style: const TextStyle(fontFamily: 'monospace')))
        )),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _res));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано')));
            }, child: const Text('COPY')
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            onPressed: () => Share.share(_res),
            child: const Text('SHARE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
          ))
        ])
      ])
    )
  );
}

// --- PDF ТА БАВОВНА ---
class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
}

class CottonGame extends StatelessWidget {
  const CottonGame({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.local_fire_department, size: 100, color: Colors.orange), 
    const SizedBox(height: 20),
    const Text('РЕЖИМ БАВОВНА АКТИВОВАНО', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)), 
    const SizedBox(height: 20),
    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(context), child: const Text('ПОВЕРНУТИСЯ', style: TextStyle(color: Colors.white)))
  ])));
}
