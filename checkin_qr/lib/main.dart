import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_sheets_service.dart';

void main() => runApp(const CheckInApp());

// Paleta
const Color kNavy = Color(0xFF0B1540);
const Color kNavyDark = Color(0xFF081033);

class CheckInApp extends StatelessWidget {
  const CheckInApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kNavy, brightness: Brightness.dark);
    return MaterialApp(
      title: 'PET CheckIn',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: kNavy,
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ===== Modelo de atividade (rótulo + coluna) =====
class ActivityOpt {
  final String label;
  final int colIndex; // zero-based (A=0,B=1,C=2,D=3,...)
  const ActivityOpt(this.label, this.colIndex);
}

// ===== Config do único evento (SEB) =====
class EventConfig {
  final String name;
  final String spreadsheetId;
  final String formUrl;
  final Map<String, List<ActivityOpt>> activitiesByDay;

  const EventConfig({
    required this.name,
    required this.spreadsheetId,
    required this.formUrl,
    required this.activitiesByDay,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // ÚNICO EVENTO
  final EventConfig _seb = const EventConfig(
    name: 'XVI SEB',
    spreadsheetId: '1htQOjCdE-Ij979bHXVLl4P5h6ExpeCxsjWDtA8pEhr4',
    formUrl:
        'https://docs.google.com/spreadsheets/d/1htQOjCdE-Ij979bHXVLl4P5h6ExpeCxsjWDtA8pEhr4/edit?gid=44183326',
    activitiesByDay: {
      // ATENÇÃO: índices são zero-based:
      // B=1, C=2, D=3, E=4, F=5, G=6, H=7, I=8...
      // O horário será gravado automaticamente na coluna à direita.
      'Segunda': [
        ActivityOpt('Palestra de Abertura', 1),   // B -> horário em C
        ActivityOpt('Palestra de SEB Normal', 3), // D -> horário em E  (CORRIGIDO)
        ActivityOpt('Workshop A/B', 5),           // F -> horário em G
        ActivityOpt('Workshop C/D', 7),           // H -> horário em I
      ],
      'Terca': [
        ActivityOpt('Palestra SEB - Específico', 1), // B -> horário em C
      ],
      'Quarta': [
        ActivityOpt('Mesa Redonda', 1),              // B -> horário em C
        ActivityOpt('Palestra SEB Normal 2', 3),     // D -> horário em E
        ActivityOpt('Cerimônia de Encerramento', 5), // F -> horário em G
      ],
    },
  );

  GoogleSheetsService? _sheets;
  bool _ready = false;

  // animações de UI
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final AnimationController _bgCtl;
  late final Animation<double> _bgAnim;

  @override
  void initState() {
    super.initState();
    _bgCtl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtl, curve: Curves.easeInOut);
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scale = Tween(begin: 0.98, end: 1.02).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bgCtl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _ensureSheetsReady() async {
    if (_ready && _sheets != null) return;
    try {
      final s = await GoogleSheetsService.create(_seb.spreadsheetId);
      setState(() {
        _sheets = s;
        _ready = true;
      });
    } catch (e) {
      _toast('Falha ao iniciar Google Sheets: $e');
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openForm() async {
    final ok = await launchUrl(Uri.parse(_seb.formUrl), mode: LaunchMode.externalApplication);
    if (!ok) _toast('Não consegui abrir o Google Sheets.');
  }

  // Fluxo: (1) dia -> (2) atividade -> (3) scanner
  Future<void> _escanear() async {
    await _ensureSheetsReady();
    if (!_ready || _sheets == null) return;

    // 1) Seleciona o dia
    final dia = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0F1C50),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final dias = _seb.activitiesByDay.keys.toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              const Text('Selecione o dia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              for (final d in dias)
                ListTile(
                  leading: const Icon(Icons.date_range),
                  title: Text(d),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, d),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || dia == null) return;

    // 2) Seleciona a atividade do dia
    final opts = _seb.activitiesByDay[dia] ?? const <ActivityOpt>[];
    final atividade = await showModalBottomSheet<ActivityOpt>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0F1C50),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text('Selecione a atividade — $dia',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final a in opts)
              ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(a.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, a),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || atividade == null) return;

    // 3) Scanner
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScannerPage(
        sheets: _sheets!,
        sheetName: dia,
        presenceColIndex: atividade.colIndex,
        activityLabel: '${_seb.name} — ${atividade.label}',
        formUrl: _seb.formUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final logoH = w * 0.24;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Fundo animado
            AnimatedBuilder(
              animation: _bgAnim,
              builder: (_, __) {
                final t = _bgAnim.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(kNavy, kNavyDark, t)!,
                        Color.lerp(kNavyDark, const Color(0xFF0A1336), t)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                );
              },
            ),

            // Título
            const Positioned(
              top: 28, left: 16, right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PET CheckIn',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  _HeaderRule(),
                ],
              ),
            ),

            // Card central
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 36,
                              spreadRadius: -4,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_scanner, size: 64, color: Colors.white),
                            const SizedBox(height: 12),
                            const Text('Registrar presença',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(height: 16),

                            // Botão principal: ESCANEAR
                            ScaleTransition(
                              scale: _scale,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.qr_code_2),
                                label: const Text('Escanear'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: kNavy,
                                  elevation: 12,
                                  shadowColor: Colors.white24,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                onPressed: _escanear,
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Abre Sheets
                            ElevatedButton.icon(
                              onPressed: _openForm,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Abrir Google Sheets'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: kNavy,
                                elevation: 8,
                                shadowColor: Colors.white24,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Logos (rodapé)
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LogoBox(path: 'assets/LogoPET.png', height: logoH),
                  _LogoBox(path: 'assets/LogoXVISEB.png', height: logoH),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRule extends StatelessWidget {
  const _HeaderRule();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white70, Colors.white, Colors.white70],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }
}

// ===== Logos =====
class _LogoBox extends StatelessWidget {
  const _LogoBox({required this.path, required this.height});
  final String path;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: SizedBox(height: height, child: Image.asset(path, fit: BoxFit.contain)),
      ),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({
    super.key,
    required this.sheets,
    required this.sheetName,
    required this.presenceColIndex,
    required this.activityLabel,
    required this.formUrl,
  });

  final GoogleSheetsService sheets;
  final String sheetName;        // 'Segunda' | 'Terca' | 'Quarta'
  final int presenceColIndex;    // B=1, D=3, F=5, H=7...
  final String activityLabel;    // exibe no AppBar
  final String formUrl;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  String? _last;
  bool _busy = false;

  late final AnimationController _borderCtl;
  late final Animation<double> _borderAnim;

  @override
  void initState() {
    super.initState();
    _borderCtl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _borderAnim = CurvedAnimation(parent: _borderCtl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    _borderCtl.dispose();
    super.dispose();
  }

  SnackBar _snack(IconData icon, String text, Color color) {
    return SnackBar(
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 900),
      content: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Flexible(child: Text(text)),
        ],
      ),
    );
  }

  Future<void> _handle(String code) async {
    if (_busy || code.isEmpty || code == _last) return;
    _busy = true;
    _last = code;
    try {
      final result = await widget.sheets.marcarPresencaEmColuna(
        code,
        sheetName: widget.sheetName,
        presenceColIndex: widget.presenceColIndex,
      );

      if (!mounted) return;
      switch (result.status) {
        case MarkStatus.marked:
          HapticFeedback.mediumImpact();
          final ts = result.timestamp;
          ScaffoldMessenger.of(context).showSnackBar(
            _snack(
              Icons.check_circle,
              ts != null
                  ? 'Presença marcada às $ts (${widget.activityLabel})'
                  : 'Presença marcada! (${widget.activityLabel})',
              Colors.green.shade700,
            ),
          );
          break;
        case MarkStatus.alreadyPresent:
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            _snack(Icons.info, 'Já estava marcado.', Colors.blueGrey.shade700),
          );
          break;
        case MarkStatus.notFound:
          HapticFeedback.vibrate();
          ScaffoldMessenger.of(context).showSnackBar(
            _snack(Icons.error, 'Código não encontrado nesta lista.', Colors.red.shade700),
          );
          break;
      }
      await Future.delayed(const Duration(milliseconds: 900));
      await _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        _snack(Icons.warning_amber, 'Erro: $e', Colors.orange.shade700),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: kNavy,
        title: Text('Escanear — ${widget.sheetName}'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), tooltip: 'Lanterna', onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_android), tooltip: 'Trocar câmera', onPressed: () => _controller.switchCamera()),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Abrir Google Sheets',
            onPressed: () => launchUrl(Uri.parse(widget.formUrl), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final v = capture.barcodes.first.rawValue;
              if (v != null) _handle(v);
            },
          ),
          // Moldura “neon”
          IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _borderAnim,
                builder: (_, __) {
                  return Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5 + 0.5 * _borderAnim.value),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.10 + 0.10 * _borderAnim.value),
                          blurRadius: 32,
                          spreadRadius: 2,
                        ),
                      ],
                      gradient: RadialGradient(
                        colors: [Colors.white.withOpacity(0.06 * _borderAnim.value), Colors.transparent],
                        radius: 0.85,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
