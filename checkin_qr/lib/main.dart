import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  // 👉 ID da planilha (1 arquivo com abas: Segunda/Terca/Quarta)
  final String spreadsheetId = '1htQOjCdE-Ij979bHXVLl4P5h6ExpeCxsjWDtA8pEhr4';

  late GoogleSheetsService _sheets;
  bool _ready = false;

  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _initSheets();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scale = Tween(begin: 0.98, end: 1.02).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
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

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _selecionarDiaEEscanear() async {
    if (!_ready) {
      _toast('Conectando ao Google Sheets...');
      return;
    }
    HapticFeedback.lightImpact();

    final dia = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0F1C50),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget tile(String label, IconData icon) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.white10,
                child: Icon(icon, color: Colors.white),
              ),
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

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScannerPage(sheets: _sheets, sheetName: dia),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final logoH = w * 0.24; // ⬅️ altura igual para as duas logos (ajuste fino aqui)

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Fundo com gradiente sutil
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kNavy, kNavyDark],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            // Título topo (com respiro extra)
            Positioned(
              top: 28, // afastado da borda
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'XVI SEB - Sistema de CheckIn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 6),
                  SizedBox(
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Card central com glassmorphism + botão pulsante
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
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
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
                            ScaleTransition(
                              scale: _scale,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: kNavy,
                                  elevation: 10,
                                  shadowColor: Colors.white24,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                onPressed: _ready ? _selecionarDiaEEscanear : null,
                                child: Text(_ready ? 'Escanear' : 'Conectando...'),
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

            // Logos iguais (mesma ALTURA), sem borda/fundo
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
    );
  }
}

// ===== Logos sem borda/fundo e com MESMA ALTURA =====
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
        child: SizedBox(
          height: height,
          child: Image.asset(
            path,
            fit: BoxFit.contain, // preserva proporção de cada arte
          ),
        ),
      ),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.sheets, required this.sheetName});
  final GoogleSheetsService sheets;
  final String sheetName; // 'Segunda' | 'Terca' | 'Quarta'
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
    _borderAnim = Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _borderCtl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _borderCtl.dispose();
    super.dispose();
  }

  // ⬇️ ATUALIZADO para usar MarkResult/MarkStatus (data/hora + bloqueio duplicata)
  Future<void> _handle(String code) async {
    if (_busy || code.isEmpty || code == _last) return;
    _busy = true;
    _last = code;
    try {
      final result = await widget.sheets.marcarPresenca(code, sheetName: widget.sheetName);

      if (!mounted) return;
      String msg;
      switch (result.status) {
        case MarkStatus.marked:
          msg = '$code marcado como Presente em ${widget.sheetName}'
                '${result.timestamp != null ? ' às ${result.timestamp}' : ''} ✅';
          break;
        case MarkStatus.alreadyPresent:
          msg = '$code já estava marcado em ${widget.sheetName}'
                '${result.timestamp != null ? ' (em ${result.timestamp})' : ''}.';
          break;
        case MarkStatus.notFound:
          msg = 'Não encontrei "$code" em ${widget.sheetName}.';
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      await _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      _busy = false; // permite tentar de novo
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
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_android), onPressed: () => _controller.switchCamera()),
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
          // Overlay com borda animada
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
                        color: Colors.white.withOpacity(_borderAnim.value),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.15),
                          blurRadius: 24,
                          spreadRadius: 1,
                        ),
                      ],
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