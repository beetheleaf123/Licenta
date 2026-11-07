import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'mqtt_service_v2.dart';

// ============================================================
//  MODEL: IrCommand
// ============================================================
class IrCommand {
  final String name;
  final String displayName;
  final String createdAt;
  final int dataSize;

  const IrCommand({
    required this.name,
    required this.displayName,
    required this.createdAt,
    required this.dataSize,
  });

  factory IrCommand.fromJson(Map<String, dynamic> j) => IrCommand(
        name: j['name'] as String? ?? '',
        displayName: j['display_name'] as String? ?? j['name'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        dataSize: j['data_size'] as int? ?? 0,
      );

  int get estimatedTimings => (dataSize / 7).round();
}

// ============================================================
//  ECRAN PRINCIPAL: IrLearningScreen
// ============================================================
class IrLearningScreen extends StatefulWidget {
  final MqttServiceV2 mqttService;
  final String serverIP;

  const IrLearningScreen({
    super.key,
    required this.mqttService,
    required this.serverIP,
  });

  @override
  State<IrLearningScreen> createState() => _IrLearningScreenState();
}

class _IrLearningScreenState extends State<IrLearningScreen> {
  List<IrCommand> _commands = [];
  bool _isLoading = true;
  StreamSubscription? _mqttSub;

  static const _accent = Color(0xFFE53935);
  static const _bg = Color(0xFFF5F7FB);

  @override
  void initState() {
    super.initState();
    widget.mqttService.subscribe('smarthome/ir/learn/status');
    widget.mqttService.subscribe('smarthome/ir/learn/result');

    _mqttSub = widget.mqttService.messageStream.listen((data) {
      // Reîncarcă lista după orice captură nouă
      if (data['topic'] == 'smarthome/ir/learn/result') {
        _fetchCommands();
      }
    });

    _fetchCommands();
  }

  @override
  void dispose() {
    _mqttSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchCommands() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final resp = await http
          .get(Uri.parse('http://${widget.serverIP}:5000/ir_commands'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body['status'] == 'ok' && body['commands'] is List) {
          if (!mounted) return;
          setState(() {
            _commands = (body['commands'] as List)
                .map((e) => IrCommand.fromJson(e as Map<String, dynamic>))
                .toList();
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[IrLearning] Fetch error: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _deleteCommand(String name) async {
    try {
      await http
          .delete(Uri.parse('http://${widget.serverIP}:5000/ir_commands/$name'))
          .timeout(const Duration(seconds: 5));
      _fetchCommands();
    } catch (e) {
      debugPrint('[IrLearning] Delete error: $e');
    }
  }

  void _testCommand(String name) {
    widget.mqttService.publish('smarthome/ir/send', name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Comandă emisă: $name',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmDelete(IrCommand cmd) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Șterge comandă',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Ești sigur că vrei să ștergi "${cmd.displayName}"?\n\nAceastă acțiune este ireversibilă.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anulează')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white),
            onPressed: () {
              _deleteCommand(cmd.name);
              Navigator.pop(ctx);
            },
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
  }

  void _openLearningWizard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IrLearningWizard(
        mqttService: widget.mqttService,
        onCommandSaved: _fetchCommands,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('LEARNING MODE',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _fetchCommands,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reîncarcă',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                backgroundColor: _accent.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openLearningWizard,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('COMANDĂ NOUĂ',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchCommands,
        color: _accent,
        child: _isLoading
            ? _buildShimmer()
            : _commands.isEmpty
                ? _buildEmpty()
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      ..._commands.map(_buildCommandCard),
                    ],
                  ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  HEADER card cu gradient
  // ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE53935), Color(0xFFC62828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.settings_remote_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_commands.length} ${_commands.length == 1 ? 'comandă salvată' : 'comenzi salvate'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Apasă + pentru a învăța o comandă nouă',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Card per comandă salvată
  // ─────────────────────────────────────────────────────────
  Widget _buildCommandCard(IrCommand cmd) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: const Border(left: BorderSide(color: _accent, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row header: icon + name
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sensors_rounded,
                    color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cmd.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF2D3142)),
                    ),
                    Text(
                      'ID: ${cmd.name}  ·  ~${cmd.estimatedTimings} timings',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Timestamp
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.12)),
              ),
              child: Row(children: [
                Icon(Icons.access_time_rounded,
                    size: 13, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  _formatDate(cmd.createdAt),
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            // Acțiuni
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _testCommand(cmd.name),
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 15),
                  label: const Text('Testează',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _confirmDelete(cmd),
                  icon:
                      const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('Șterge',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Empty state
  // ─────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_remote_outlined,
                  size: 80, color: Colors.grey[300]),
              const SizedBox(height: 20),
              const Text(
                'Nicio comandă IR salvată',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3142)),
              ),
              const SizedBox(height: 10),
              Text(
                'Apasă butonul + pentru a învăța prima comandă IR de la telecomanda ta.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[500], height: 1.5),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _openLearningWizard,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adaugă Prima Comandă',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Shimmer loading
  // ─────────────────────────────────────────────────────────
  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 4,
      itemBuilder: (_, i) => Container(
        height: 140,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: _accent),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Helper: formatare dată
  // ─────────────────────────────────────────────────────────
  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw.replaceAll(' ', 'T'));
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Chiar acum';
      if (diff.inHours < 1) return 'Acum ${diff.inMinutes} minute';
      if (diff.inDays < 1) {
        return 'Azi la ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (diff.inDays == 1) return 'Ieri';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

// ============================================================
//  BOTTOM SHEET: Wizard de captură IR (2 pași)
// ============================================================
class IrLearningWizard extends StatefulWidget {
  final MqttServiceV2 mqttService;
  final VoidCallback onCommandSaved;

  const IrLearningWizard({
    super.key,
    required this.mqttService,
    required this.onCommandSaved,
  });

  @override
  State<IrLearningWizard> createState() => _IrLearningWizardState();
}

enum _WizardStep { naming, listening, success, error }

class _IrLearningWizardState extends State<IrLearningWizard>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  _WizardStep _step = _WizardStep.naming;
  StreamSubscription? _mqttSub;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _accent = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mqttSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  //  Pasul 2: publicăm MQTT și ascultăm rezultatul
  // ─────────────────────────────────────────────────────────
  void _startListening() {
    if (!_formKey.currentState!.validate()) return;

    // Normalizăm numele ca identificator: "AC Pornit" -> "AC_PORNIT"
    final commandName = _nameController.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Z0-9_]'), '');

    if (commandName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numele conține caractere invalide.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _step = _WizardStep.listening);

    widget.mqttService.subscribe('smarthome/ir/learn/status');
    widget.mqttService.subscribe('smarthome/ir/learn/result');
    widget.mqttService.publish('smarthome/ir/learn/start', commandName);

    _mqttSub = widget.mqttService.messageStream.listen((data) {
      if (data['topic'] == 'smarthome/ir/learn/status') {
        final status = data['payload'] as String? ?? '';
        if (status == 'captured') {
          _mqttSub?.cancel();
          if (!mounted) return;
          setState(() => _step = _WizardStep.success);
          widget.onCommandSaved();
          // Auto-close după 2 secunde
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        } else if (status == 'error') {
          _mqttSub?.cancel();
          if (!mounted) return;
          setState(() => _step = _WizardStep.error);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize: 0.50,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.fromLTRB(
              24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 20),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildCurrentStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _WizardStep.naming:
        return _buildNaming();
      case _WizardStep.listening:
        return _buildListening();
      case _WizardStep.success:
        return _buildSuccess();
      case _WizardStep.error:
        return _buildError();
    }
  }

  // ─────────────────────────────────────────────────────────
  //  PAS 1: Denumire
  // ─────────────────────────────────────────────────────────
  Widget _buildNaming() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('naming'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWizardHeader('Comandă IR Nouă', 'Pas 1 din 2 — Denumire'),
          const SizedBox(height: 24),
          _buildProgressBar(step: 1),
          const SizedBox(height: 28),

          const Text('Nume Comandă',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF2D3142))),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'ex: AC Pornit Racire, TV Power...',
              prefixIcon: const Icon(Icons.label_rounded, color: _accent),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _accent, width: 2)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Introduceți un nume' : null,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),

          // Info box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Asigurați-vă că receptorul IR (Wemos) este în raza telecomenzii în momentul capturării.',
                  style: TextStyle(fontSize: 12, color: Colors.brown, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startListening,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continuă — Capturează Semnal',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PAS 2: Ascultare
  // ─────────────────────────────────────────────────────────
  Widget _buildListening() {
    return Column(
      key: const ValueKey('listening'),
      children: [
        _buildWizardHeader('Ascult...', 'Pas 2 din 2 — Capturare'),
        const SizedBox(height: 24),
        _buildProgressBar(step: 2),
        const SizedBox(height: 40),

        // Animated IR icon
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withOpacity(0.08),
              border: Border.all(color: _accent.withOpacity(0.25), width: 2.5),
            ),
            child: const Icon(Icons.settings_remote_rounded,
                color: _accent, size: 52),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Apasă butonul de pe telecomandă',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3142)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Îndreaptă telecomanda spre receptorul IR și apasă butonul dorit o singură dată.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5),
        ),
        const SizedBox(height: 28),
        const CircularProgressIndicator(color: _accent, strokeWidth: 3),
        const SizedBox(height: 28),
        TextButton(
          onPressed: () {
            _mqttSub?.cancel();
            Navigator.pop(context);
          },
          child: const Text('Anulează',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Succes
  // ─────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      children: [
        const SizedBox(height: 20),
        Icon(Icons.check_circle_rounded, color: Colors.green[600], size: 90),
        const SizedBox(height: 20),
        const Text(
          'Comandă Salvată!',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3142)),
        ),
        const SizedBox(height: 10),
        Text(
          '"${_nameController.text.trim()}" a fost salvată cu succes\nși este disponibilă în automatizări.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5),
        ),
        const SizedBox(height: 30),
        Text('Închidem automat...',
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Eroare
  // ─────────────────────────────────────────────────────────
  Widget _buildError() {
    return Column(
      key: const ValueKey('error'),
      children: [
        const SizedBox(height: 20),
        Icon(Icons.error_outline_rounded, color: Colors.red[600], size: 90),
        const SizedBox(height: 20),
        const Text(
          'Eroare la Captură',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3142)),
        ),
        const SizedBox(height: 10),
        Text(
          'Nu s-a putut salva comanda IR.\nVerificați că receptorul este conectat și funcțional.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _step = _WizardStep.naming),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Încearcă din Nou',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Helpers UI
  // ─────────────────────────────────────────────────────────
  Widget _buildWizardHeader(String title, String subtitle) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            const Icon(Icons.settings_remote_rounded, color: _accent, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3142))),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    ]);
  }

  Widget _buildProgressBar({required int step}) {
    return Row(children: [
      _stepDot(1, step >= 1),
      Expanded(
          child: Container(
              height: 2,
              color: step >= 2 ? _accent : Colors.grey[200])),
      _stepDot(2, step >= 2),
    ]);
  }

  Widget _stepDot(int n, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? _accent : Colors.grey[200],
        boxShadow: active
            ? [BoxShadow(color: _accent.withOpacity(0.3), blurRadius: 8)]
            : [],
      ),
      child: Center(
        child: Text(
          n.toString(),
          style: TextStyle(
              color: active ? Colors.white : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
      ),
    );
  }
}
