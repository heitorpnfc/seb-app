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

// URL do Google Sheets (seu link atual)
const String kFormUrl = 'https://docs.google.com/spreadsheets/d/1htQOjCdE-Ij979bHXVLl4P5h6ExpeCxsjWDtA8pEhr4/edit?usp=sharing';

class CheckInApp extends StatelessWidget {
  const CheckInApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kNavy, brightness: Brightness.dark);
    return MaterialApp(
      title: 'XVI SEB - Sistema de CheckIn',
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // 👉 ID da planilha
  final String spreadsheetId = '1htQOjCdE-Ij979bHXVLl4P5h6ExpeCxsjWDtA8pEhr4';

  late GoogleSheetsService _sheets;
  bool _ready = false;

  // animações
  late final AnimationController _pulse; // botão scan
  late final Animation<double> _scale;
  late final AnimationController _bgCtl; // gradiente fundo
  late final Animation<double> _bgAnim;

  @override
  void initState() {
    super.initState();
    _initSheets();

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

  Future<void> _initSheets() async {
    try {
      _sheets = await GoogleSheetsService.create(spreadsheetId);
      setState(() => _ready = true);
    } catch (e) {
      _toast('Falha ao iniciar Google Sheets: $e');
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openForm() async {
    final uri = Uri.parse(kFormUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('Não consegui abrir o Google Sheets.');
  }

  // ===== Atividades por dia (colunas: B=1, C=2, D=3, E=4) =====
  Map<String, List<ActivityOpt>> get _activitiesByDay => {
        'Segunda': const [
          ActivityOpt('Palestra de Abertura', 1),
          ActivityOpt('Palestra de SEB Normal', 2),
          ActivityOpt('Workshop A/B', 3),
          ActivityOpt('Workshop C/D', 4),
        ],
        'Terca': const [
          ActivityOpt('Palestra SEB - Específico', 1),
        ],
        'Quarta': const [
          ActivityOpt('Mesa Redonda', 1),
          ActivityOpt('Palestra SEB Normal 2', 2),
          ActivityOpt('Cerimônia de Encerramento', 3),
        ],
      };

  Future<void> _selecionarDiaEEscanear() async {
    if (!_ready) {
      _toast('Conectando ao Google Sheets...');
      return;
    }
    HapticFeedback.lightImpact();

    // 1) Seleciona o dia
    final dia = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0F1C50),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Widget tile(String label, IconData icon) => ListTile(
              leading: CircleAvatar(backgroundColor: Colors.white10, child: Icon(icon, color: Colors.white)),
              title: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, label),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              const Text('Selecione o dia', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              tile('Segunda', Icons.calendar_today),
              tile('Terca', Icons.calendar_view_day),
              tile('Quarta', Icons.event_available),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || dia == null) return;

    // 2) Seleciona a atividade do dia
    final opts = _activitiesByDay[dia] ?? [];
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
            Text('Selecione a atividade — $dia', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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

    // 3) Vai para o scanner
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScannerPage(
        sheets: _sheets,
        sheetName: dia,
        presenceColIndex: atividade.colIndex,
        activityLabel: atividade.label,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final logoH = w * 0.24; // mesma altura para as duas logos

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

            // Título topo
            Positioned(
              top: 28,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'XVI SEB - Sistema de CheckIn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white70, Colors.white, Colors.white70],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card central + botões
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
                            BoxShadow(
                              color: Colors.white.withOpacity(0.06),
                              blurRadius: 24,
                              spreadRadius: 2,
                              offset: const Offset(-8, -8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_scanner, size: 64, color: Colors.white),
                            const SizedBox(height: 12),
                            const Text(
                              'Registrar presença',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            const SizedBox(height: 16),

                            // Botão Escanear
                            ScaleTransition(
                              scale: _scale,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: kNavy,
                                  elevation: 12,
                                  shadowColor: Colors.white24,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ).merge(ButtonStyle(
                                  overlayColor: WidgetStatePropertyAll(Colors.white.withOpacity(0.08)),
                                  animationDuration: const Duration(milliseconds: 120),
                                )),
                                onPressed: _ready ? _selecionarDiaEEscanear : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.qr_code_scanner, size: 22),
                                    SizedBox(width: 10),
                                    Text('Escanear'),
                                  ],
                                ),
                              ),
                            ),

                            // Botão Google Sheets logo abaixo
                            const SizedBox(height: 20),
                            Semantics(
                              label: 'Abrir Google Sheets',
                              button: true,
                              child: _LiftOnPress(
                                onTap: _openForm,
                                child: ElevatedButton.icon(
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

            // Logos no rodapé
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LogoBox(
                    path: 'assets/LogoPET.png',
                    height: logoH,
                    onTap: () => _toast('PET Engenharia Biomédica'),
                  ),
                  _LogoBox(
                    path: 'assets/LogoXVISEB.png',
                    height: logoH,
                    onTap: () => _toast('XVI SEB'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // sem FAB — botão de abrir Sheets fica logo abaixo de "Escanear"
    );
  }
}

// ===== Botão que “afunda” 2px ao pressionar =====
class _LiftOnPress extends StatefulWidget {
  const _LiftOnPress({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_LiftOnPress> createState() => _LiftOnPressState();
}

class _LiftOnPressState extends State<_LiftOnPress> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
        child: widget.child,
      ),
    );
  }
}

// ===== Modelo da atividade (rótulo + coluna) =====
class ActivityOpt {
  final String label;
  final int colIndex; // B=1, C=2, D=3, E=4
  const ActivityOpt(this.label, this.colIndex);
}

// ===== Logos =====
class _LogoBox extends StatelessWidget {
  const _LogoBox({required this.path, required this.height, this.onTap});
  final String path;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: SizedBox(
            height: height,
            child: Image.asset(path, fit: BoxFit.contain),
          ),
        ),
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
  });

  final GoogleSheetsService sheets;
  final String sheetName;        // 'Segunda' | 'Terca' | 'Quarta'
  final int presenceColIndex;    // B=1, C=2, D=3, E=4
  final String activityLabel;

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

      // feedback visual + háptico por status
      late final SnackBar bar;
      switch (result.status) {
        case MarkStatus.marked:
          HapticFeedback.mediumImpact();
          bar = _snack(const Icon(Icons.check_circle, color: Colors.white), 'Presença marcada com sucesso!');
          break;
        case MarkStatus.alreadyPresent:
          HapticFeedback.lightImpact();
          bar = _snack(const Icon(Icons.info, color: Colors.white), 'Este código já estava marcado.');
          break;
        case MarkStatus.notFound:
          HapticFeedback.vibrate();
          bar = _snack(const Icon(Icons.error, color: Colors.white), 'Código não encontrado nesta lista.');
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(bar);

      // pequena pausa para o operador ver a mensagem, depois fecha
      await Future.delayed(const Duration(milliseconds: 900));
      await _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        _snack(const Icon(Icons.warning_amber, color: Colors.white), 'Erro: $e', color: Colors.orange.shade700),
      );
      // cooldown rápido
      await Future.delayed(const Duration(milliseconds: 800));
      _busy = false;
    }
  }

  SnackBar _snack(Widget icon, String text, {Color? color}) {
    final bg = color ??
        (text.contains('sucesso')
            ? Colors.green.shade700
            : text.contains('já estava')
                ? Colors.blueGrey.shade700
                : Colors.red.shade700);
    return SnackBar(
      content: Row(children: [
        icon,
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ]),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: kNavy,
        title: Text('Escanear — ${widget.sheetName}: ${widget.activityLabel}'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), tooltip: 'Lanterna', onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_android), tooltip: 'Trocar câmera', onPressed: () => _controller.switchCamera()),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Abrir Google Sheets',
            onPressed: () => launchUrl(Uri.parse(kFormUrl), mode: LaunchMode.externalApplication),
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
          // Moldura "neon"
          IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _borderAnim,
                builder: (context, _) {
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
                        colors: [
                          Colors.white.withOpacity(0.06 * _borderAnim.value),
                          Colors.transparent
                        ],
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