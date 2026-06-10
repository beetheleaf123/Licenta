import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'mqtt_service_v2.dart';

// ============================================================
//  MODEL: NotificationAlert
// ============================================================
class NotificationAlert {
  final int? id;
  final String name;
  final String sensor;
  final String operator;
  final double threshold;
  final String priority;
  final bool isActive;
  final double hysteresis;
  final double? lowerLimit;
  final double? upperLimit;

  const NotificationAlert({
    this.id,
    required this.name,
    required this.sensor,
    required this.operator,
    required this.threshold,
    this.priority = 'warning',
    this.isActive = true,
    this.hysteresis = 0.5,
    this.lowerLimit,
    this.upperLimit,
  });

  factory NotificationAlert.fromJson(Map<String, dynamic> j) {
    return NotificationAlert(
      id: j['id'] as int?,
      name: j['name'] as String? ?? '',
      sensor: j['sensor'] as String? ?? 'temperature',
      operator: j['operator'] as String? ?? '>',
      threshold: (j['threshold'] as num?)?.toDouble() ?? 0.0,
      priority: j['priority'] as String? ?? 'warning',
      isActive: (j['is_active'] as int? ?? 1) == 1,
      hysteresis: (j['hysteresis'] as num?)?.toDouble() ?? 0.5,
      lowerLimit: (j['lower_limit'] as num?)?.toDouble(),
      upperLimit: (j['upper_limit'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'sensor': sensor,
        'operator': operator,
        'threshold': threshold,
        'priority': priority,
        'is_active': isActive ? 1 : 0,
        'hysteresis': hysteresis,
        'lower_limit': lowerLimit,
        'upper_limit': upperLimit,
      };

  NotificationAlert copyWith({
    int? id,
    String? name,
    String? sensor,
    String? operator,
    double? threshold,
    String? priority,
    bool? isActive,
    double? hysteresis,
    double? lowerLimit,
    double? upperLimit,
    bool clearLowerLimit = false,
    bool clearUpperLimit = false,
  }) {
    return NotificationAlert(
      id: id ?? this.id,
      name: name ?? this.name,
      sensor: sensor ?? this.sensor,
      operator: operator ?? this.operator,
      threshold: threshold ?? this.threshold,
      priority: priority ?? this.priority,
      isActive: isActive ?? this.isActive,
      hysteresis: hysteresis ?? this.hysteresis,
      lowerLimit: clearLowerLimit ? null : (lowerLimit ?? this.lowerLimit),
      upperLimit: clearUpperLimit ? null : (upperLimit ?? this.upperLimit),
    );
  }
}

// ============================================================
//  ECRAN PRINCIPAL: NotificationsScreen
// ============================================================
class NotificationsScreen extends StatefulWidget {
  final MqttServiceV2 mqttService;
  final List<dynamic> automationRules; // Lista din AutomationsPage

  const NotificationsScreen({
    super.key,
    required this.mqttService,
    required this.automationRules,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<NotificationAlert> _alerts = [];
  bool _isLoading = true;
  StreamSubscription? _mqttSub;

  // Culori pentru priorități
  static const _priorityColors = {
    'info': Color(0xFF3B82F6),
    'warning': Color(0xFFF59E0B),
    'alert': Color(0xFFEF4444),
  };
  static const _priorityLabels = {
    'info': 'Informație',
    'warning': 'Avertisment',
    'alert': 'Critic',
  };
  static const _priorityIcons = {
    'info': Icons.info_outline_rounded,
    'warning': Icons.warning_amber_rounded,
    'alert': Icons.emergency_rounded,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    widget.mqttService.subscribe('smarthome/alerts/list');
    _mqttSub = widget.mqttService.messageStream.listen((data) {
      if (data['topic'] == 'smarthome/alerts/list') {
        try {
          final decoded = jsonDecode(data['payload']);
          if (decoded is List) {
            setState(() {
              _alerts = decoded
                  .map((e) => NotificationAlert.fromJson(e as Map<String, dynamic>))
                  .toList();
              _isLoading = false;
            });
          }
        } catch (e) {
          debugPrint('[NotificationsScreen] Eroare parsare alerte: $e');
        }
      }
    });

    // Solicităm lista de alerte
    Timer(const Duration(milliseconds: 400), () {
      widget.mqttService.publish('smarthome/alerts/get', '');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mqttSub?.cancel();
    super.dispose();
  }

  void _sendTestNotification() {
    widget.mqttService.publish('smarthome/notifications/test', '1');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text('Notificare test trimisă!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleAlert(NotificationAlert alert, bool active) {
    final updated = alert.copyWith(isActive: active);
    widget.mqttService.publish('smarthome/alerts/save', jsonEncode(updated.toJson()));
  }

  void _deleteAlert(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Șterge alertă', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Ești sigur că vrei să ștergi această alertă de prag?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulează')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () {
              widget.mqttService.publish('smarthome/alerts/delete', id.toString());
              Navigator.pop(ctx);
            },
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
  }

  void _openAlertForm({NotificationAlert? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AlertFormBottomSheet(
        existing: existing,
        onSave: (alert) {
          widget.mqttService.publish('smarthome/alerts/save', jsonEncode(alert.toJson()));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('NOTIFICĂRI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _sendTestNotification,
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: const Text('Test', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.indigo[800],
                backgroundColor: Colors.indigo.withOpacity(0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          indicatorColor: Colors.indigo[900],
          labelColor: Colors.indigo[900],
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.settings_suggest_rounded, size: 18), text: 'Automatizări'),
            Tab(icon: Icon(Icons.monitor_heart_rounded, size: 18), text: 'Alerte Praguri'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          return _tabController.index == 1
              ? FloatingActionButton.extended(
                  onPressed: () => _openAlertForm(),
                  backgroundColor: Colors.indigo[900],
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('ALERTĂ NOUĂ', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : const SizedBox.shrink();
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAutomationsTab(),
          _buildAlertsTab(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  TAB 1: Notificări per automatizare
  // ─────────────────────────────────────────────────────────
  Widget _buildAutomationsTab() {
    if (widget.automationRules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'Nicio automatizare',
        subtitle: 'Creează mai întâi reguli din ecranul de Automatizări.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: widget.automationRules.length,
      itemBuilder: (ctx, i) {
        final rule = widget.automationRules[i] as Map<String, dynamic>;
        final notifyEnabled = (rule['notify_enabled'] as int? ?? 1) == 1;
        final isActive = (rule['is_active'] as int? ?? 1) == 1;
        final sensor = rule['sensor'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: (isActive ? Colors.indigo : Colors.grey).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getSensorIcon(sensor),
                color: isActive ? Colors.indigo[700] : Colors.grey,
                size: 22,
              ),
            ),
            title: Text(
              rule['name']?.toString() ?? 'Regulă',
              style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14,
                color: isActive ? const Color(0xFF2D3142) : Colors.grey,
                decoration: isActive ? null : TextDecoration.lineThrough,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    notifyEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                    size: 14,
                    color: notifyEnabled ? Colors.green[700] : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    notifyEnabled ? 'Notificare activă' : 'Notificare dezactivată',
                    style: TextStyle(
                      fontSize: 12,
                      color: notifyEnabled ? Colors.green[700] : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Switch(
              value: notifyEnabled,
              activeColor: Colors.green[700],
              onChanged: isActive
                  ? (val) {
                      final updated = Map<String, dynamic>.from(rule);
                      updated['notify_enabled'] = val ? 1 : 0;
                      widget.mqttService.publish('smarthome/rules/save', jsonEncode(updated));
                      setState(() {
                        (widget.automationRules[i] as Map<String, dynamic>)['notify_enabled'] = val ? 1 : 0;
                      });
                    }
                  : null,
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  //  TAB 2: Alerte de prag cu histerezis
  // ─────────────────────────────────────────────────────────
  Widget _buildAlertsTab() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (_, __) => Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _alerts.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Nicio alertă de prag',
                      subtitle: 'Adaugă alerte pentru a fi notificat când valorile depășesc pragurile.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        widget.mqttService.publish('smarthome/alerts/get', '');
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                        itemCount: _alerts.length,
                        itemBuilder: (ctx, i) => _buildAlertCard(_alerts[i]),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(NotificationAlert alert) {
    final color = _priorityColors[alert.priority] ?? Colors.orange;
    final sensorLabel = _sensorLabel(alert.sensor);
    final bool hasExplicitLimits = alert.lowerLimit != null || alert.upperLimit != null;

    // Construim descrierea condiției
    final String conditionText = hasExplicitLimits
        ? 'Declanșare: ${_opSymbol(alert.operator)} ${alert.upperLimit ?? alert.lowerLimit} | Resetare: ${alert.lowerLimit ?? alert.upperLimit}'
        : '${alert.operator} ${alert.threshold.toStringAsFixed(1)}${_sensorUnit(alert.sensor)} ± ${alert.hysteresis.toStringAsFixed(1)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(_priorityIcons[alert.priority], color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2D3142))),
                      Text(
                        '${_priorityLabels[alert.priority]} · $sensorLabel',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: alert.isActive,
                  activeColor: color,
                  onChanged: (val) => _toggleAlert(alert, val),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.functions_rounded, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(conditionText,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                  ),
                  if (hasExplicitLimits)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('ASIMETRIC',
                          style: TextStyle(fontSize: 9, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _openAlertForm(existing: alert),
                  icon: const Icon(Icons.edit_rounded, size: 15),
                  label: const Text('Editează', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo[700],
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteAlert(alert.id!),
                  icon: const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('Șterge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  // Helpers
  IconData _getSensorIcon(String sensor) {
    switch (sensor) {
      case 'temperature': return Icons.thermostat_rounded;
      case 'humidity': return Icons.water_drop_rounded;
      case 'luminosity': return Icons.wb_sunny_rounded;
      case 'motion': return Icons.directions_walk_rounded;
      default: return Icons.sensors_rounded;
    }
  }

  String _sensorLabel(String s) {
    switch (s) {
      case 'temperature': return 'Temperatură';
      case 'humidity': return 'Umiditate';
      case 'luminosity': return 'Luminozitate';
      default: return s;
    }
  }

  String _sensorUnit(String s) {
    switch (s) {
      case 'temperature': return '°C';
      case 'humidity': return '%';
      case 'luminosity': return ' lx';
      default: return '';
    }
  }

  String _opSymbol(String op) {
    switch (op) {
      case '>': return '>';
      case '<': return '<';
      case '>=': return '≥';
      case '<=': return '≤';
      default: return op;
    }
  }
}

// ============================================================
//  BOTTOM SHEET: Formular creare/editare alertă
// ============================================================
class AlertFormBottomSheet extends StatefulWidget {
  final NotificationAlert? existing;
  final Function(NotificationAlert) onSave;

  const AlertFormBottomSheet({super.key, this.existing, required this.onSave});

  @override
  State<AlertFormBottomSheet> createState() => _AlertFormBottomSheetState();
}

class _AlertFormBottomSheetState extends State<AlertFormBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _thresholdCtrl;
  late TextEditingController _hysteresisCtrl;
  late TextEditingController _lowerCtrl;
  late TextEditingController _upperCtrl;

  String _sensor = 'temperature';
  String _operator = '>';
  String _priority = 'warning';
  bool _advancedMode = false;

  final _sensors = ['temperature', 'humidity', 'luminosity'];
  final _sensorLabels = {'temperature': 'Temperatură (°C)', 'humidity': 'Umiditate (%)', 'luminosity': 'Luminozitate (lx)'};
  final _operators = ['>', '<', '>=', '<='];
  final _priorityColors = {'info': Color(0xFF3B82F6), 'warning': Color(0xFFF59E0B), 'alert': Color(0xFFEF4444)};
  final _priorityLabels = {'info': 'Info', 'warning': 'Avertisment', 'alert': 'Critic'};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _thresholdCtrl = TextEditingController(text: e?.threshold.toStringAsFixed(1) ?? '');
    _hysteresisCtrl = TextEditingController(text: e?.hysteresis.toStringAsFixed(1) ?? '0.5');
    _lowerCtrl = TextEditingController(text: e?.lowerLimit?.toStringAsFixed(1) ?? '');
    _upperCtrl = TextEditingController(text: e?.upperLimit?.toStringAsFixed(1) ?? '');
    if (e != null) {
      _sensor = e.sensor;
      _operator = e.operator;
      _priority = e.priority;
      _advancedMode = e.lowerLimit != null || e.upperLimit != null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _thresholdCtrl.dispose();
    _hysteresisCtrl.dispose();
    _lowerCtrl.dispose();
    _upperCtrl.dispose();
    super.dispose();
  }

  String _defaultHysteresis() {
    switch (_sensor) {
      case 'temperature': return '0.5';
      case 'humidity': return '2.0';
      case 'luminosity': return '10.0';
      default: return '0.5';
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final alert = NotificationAlert(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      sensor: _sensor,
      operator: _operator,
      threshold: double.tryParse(_thresholdCtrl.text) ?? 0.0,
      priority: _priority,
      hysteresis: double.tryParse(_hysteresisCtrl.text) ?? 0.5,
      lowerLimit: _advancedMode && _lowerCtrl.text.isNotEmpty ? double.tryParse(_lowerCtrl.text) : null,
      upperLimit: _advancedMode && _upperCtrl.text.isNotEmpty ? double.tryParse(_upperCtrl.text) : null,
    );
    widget.onSave(alert);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 20),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(
                widget.existing == null ? 'Alertă Nouă' : 'Editează Alertă',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
              ),
              const SizedBox(height: 20),

              // Nume
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco('Nume alertă', Icons.label_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Introduceți un nume' : null,
              ),
              const SizedBox(height: 16),

              // Sensor
              _buildLabel('Senzor'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _sensors.map((s) => ChoiceChip(
                  label: Text(_sensorLabels[s]!,
                      style: TextStyle(fontWeight: FontWeight.bold, color: _sensor == s ? Colors.white : Colors.grey[700])),
                  selected: _sensor == s,
                  selectedColor: Colors.indigo[800],
                  backgroundColor: Colors.grey[100],
                  onSelected: (_) => setState(() {
                    _sensor = s;
                    if (!_advancedMode) _hysteresisCtrl.text = _defaultHysteresis();
                  }),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // Operator + Threshold
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: DropdownButtonFormField<String>(
                      value: _operator,
                      decoration: _inputDeco('Op.', Icons.compare_arrows_rounded),
                      items: _operators.map((op) => DropdownMenuItem(value: op, child: Text(op, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                      onChanged: (v) => setState(() => _operator = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _thresholdCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: _inputDeco('Prag (${_sensor == 'temperature' ? '°C' : _sensor == 'humidity' ? '%' : 'lx'})', Icons.tune_rounded),
                      validator: (v) => double.tryParse(v ?? '') == null ? 'Valoare invalidă' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Prioritate
              _buildLabel('Prioritate'),
              const SizedBox(height: 8),
              Row(
                children: ['info', 'warning', 'alert'].map((p) => Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _priority = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _priority == p ? _priorityColors[p]!.withOpacity(0.12) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _priority == p ? _priorityColors[p]! : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _priority == 'info' && p == 'info' ? Icons.info_outline_rounded
                                : p == 'warning' ? Icons.warning_amber_rounded
                                : Icons.emergency_rounded,
                            color: _priorityColors[p]!,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(_priorityLabels[p]!,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _priorityColors[p]!)),
                        ],
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // Toggle Mod avansat
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded, size: 18, color: Colors.indigo),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Configurare avansată', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                          Text('Setează manual punctele de trigger și reset (histerezis asimetric)',
                              style: TextStyle(fontSize: 11, color: Colors.indigo)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _advancedMode,
                      activeColor: Colors.indigo[800],
                      onChanged: (v) => setState(() => _advancedMode = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Mod simplu: câmp hysteresis
              if (!_advancedMode) ...[
                TextFormField(
                  controller: _hysteresisCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDeco('Ignoră oscilații de ± (histerezis)', Icons.compare_arrows_rounded),
                  validator: (v) => double.tryParse(v ?? '') == null ? 'Valoare invalidă' : null,
                ),
                const SizedBox(height: 6),
                // Preview
                AnimatedBuilder(
                  animation: Listenable.merge([_thresholdCtrl, _hysteresisCtrl]),
                  builder: (_, __) {
                    final t = double.tryParse(_thresholdCtrl.text);
                    final h = double.tryParse(_hysteresisCtrl.text);
                    if (t == null || h == null) return const SizedBox();
                    final resetVal = _operator.startsWith('>') ? t - h : t + h;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '▶ Alertă când valoarea $_operator ${t.toStringAsFixed(1)} | Resetare la $resetVal',
                        style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ],

              // Mod avansat: câmpuri lower/upper
              if (_advancedMode) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _upperCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: _inputDeco('Trigger ≥ (limita superioară)', Icons.arrow_upward_rounded),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lowerCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: _inputDeco('Reset ≤ (limita inferioară)', Icons.arrow_downward_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                    'Histerezis asimetric: alertă la trigger, resetare la limita opusă.',
                    style: TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[900],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  widget.existing == null ? 'SALVEAZĂ ALERTĂ' : 'ACTUALIZEAZĂ ALERTĂ',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.indigo[400]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.indigo[800]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  Widget _buildLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blueGrey, letterSpacing: 1),
  );
}
