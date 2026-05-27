import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

// IMPORTURILE CATRE SERVICIILE NOI (V2)
import 'mqtt_service_v2.dart';
import 'api_service_v2.dart';

/// main_v2.dart - Versiunea sandbox pentru testarea arhitecturii refactorizate.
/// Aceasta versiune foloseste MqttServiceV2 si ApiServiceV2 pentru stabilitate maxima.
void main() => runApp(const SmartHomeAppV2());

class SmartHomeAppV2 extends StatelessWidget {
  const SmartHomeAppV2({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      primarySwatch: Colors.indigo, 
      useMaterial3: true,
      fontFamily: 'Roboto',
    ),
    home: const DashboardScreenV2(),
  );
}

class DashboardScreenV2 extends StatefulWidget {
  const DashboardScreenV2({super.key});
  @override
  State<DashboardScreenV2> createState() => _DashboardScreenV2State();
}

class _DashboardScreenV2State extends State<DashboardScreenV2> {
  // --- SERVICES ---
  late final MqttServiceV2 _mqttService;
  late final ApiServiceV2 _apiService;

  // --- STATE VARIABLES ---
  String temperatura = "--";
  String umiditate = "--";
  String luxValue = "--"; // NOU: Valoare senzor lumina
  double lightThreshold = 50.0; // NOU: Prag automatizare
  String statusText = "Initializing...";
  MqttStatus connectionStatus = MqttStatus.initial;
  
  String bulbStatus = "OFF";
  String plugStatus = "OFF"; 
  String thrStatus = "OFF"; // NOU: Status switch THR
  double putereW = 0.0;
  double voltajV = 0.0;
  double curentA = 0.0;

  // --- TIMESTAMPS PENTRU MONITORIZARE REALA ---
  DateTime? lastBmeUpdate;
  DateTime? lastLuxUpdate;
  DateTime? lastPlugUpdate;
  DateTime? lastBulbUpdate;
  DateTime? lastThrUpdate; // NOU: Timestamp THR
  Timer? _statusTimer;

  List<FlSpot> puncteGrafic = [];
  bool seIncarcaGraficul = true;

  final String serverIP = '5.13.195.71';

  @override
  void initState() {
    super.initState();
    _mqttService = MqttServiceV2(server: serverIP, clientIdentifier: 'flutter_v2_sandbox');
    _apiService = ApiServiceV2(serverIP: serverIP);
    _listenToStreams();
    _mqttService.connect();
    _loadHistory();

    // Timer pentru refresh periodic al UI-ului (pentru a detecta timeout-ul senzorilor)
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) setState(() {}); 
    });
  }

  void _listenToStreams() {
    _mqttService.statusStream.listen((status) {
      setState(() {
        connectionStatus = status;
        switch (status) {
          case MqttStatus.connecting: statusText = "Connecting to RPi..."; break;
          case MqttStatus.connected: 
            statusText = "System Online ✅"; 
            _subscribeToTopics();
            break;
          case MqttStatus.disconnected: statusText = "Disconnected ⚠️"; break;
          case MqttStatus.error: statusText = "Connection Error ❌"; break;
          default: statusText = "Idle";
        }
      });
    });

    _mqttService.messageStream.listen((data) {
      final String topic = data['topic'];
      final String payload = data['payload'];
      _processIncomingMessage(topic, payload);
    });
  }

  void _subscribeToTopics() {
    _mqttService.subscribe('tele/sonoff/SENSOR');
    _mqttService.subscribe('smarthome/wemos/sensor'); // NOU: Senzor Lux
    _mqttService.subscribe('smarthome/plug/state');
    _mqttService.subscribe('smarthome/bulb/state');
    _mqttService.subscribe('smarthome/thr/state'); // NOU: State THR
  }

  void _processIncomingMessage(String topic, String message) {
    setState(() {
      try {
        if (topic == 'tele/sonoff/SENSOR') {
          var data = jsonDecode(message);
          double tempVal = double.parse(data['BME280']['Temperature'].toString());
          temperatura = tempVal.toStringAsFixed(1);
          umiditate = data['BME280']['Humidity'].toString();
          if (data['Switch'] != null) thrStatus = data['Switch'].toString().toUpperCase();
          _updateLiveChart(tempVal);
          lastBmeUpdate = DateTime.now(); // Update timestamp
          lastThrUpdate = DateTime.now(); // Update switch timestamp
        } 
        else if (topic == 'smarthome/wemos/sensor') {
          var data = jsonDecode(message);
          luxValue = data['lux'].toString();
          lastLuxUpdate = DateTime.now(); // Update timestamp
        }
        else if (topic == 'smarthome/plug/state') {
          var data = jsonDecode(message);
          putereW = (data['power'] as num).toDouble();
          voltajV = (data['voltage'] as num).toDouble();
          curentA = (data['current'] as num).toDouble();
          if (data['switch'] != null) plugStatus = data['switch'].toString().toUpperCase();
          lastPlugUpdate = DateTime.now(); // Update timestamp
        } 
        else if (topic == 'smarthome/bulb/state') {
          bulbStatus = message.toUpperCase();
          lastBulbUpdate = DateTime.now(); // Update timestamp
        }
        else if (topic == 'smarthome/thr/state') {
          thrStatus = message.toUpperCase();
          lastThrUpdate = DateTime.now();
        }
      } catch (e) {
        print('[UI_ERROR] Parsare JSON esuata: $e');
      }
    });
  }

  void _updateLiveChart(double val) {
    puncteGrafic.add(FlSpot(puncteGrafic.length.toDouble(), val));
    if (puncteGrafic.length > 50) {
      puncteGrafic.removeAt(0);
      puncteGrafic = puncteGrafic.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.y)).toList();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final data = await _apiService.fetchHistory();
      setState(() {
        puncteGrafic = data.asMap().entries.map((e) {
          double v = double.parse(e.value['temperatura'].toString());
          return FlSpot(e.key.toDouble(), v);
        }).toList();
        seIncarcaGraficul = false;
      });
    } catch (e) {
      setState(() => seIncarcaGraficul = false);
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _mqttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("SMART HUB V2", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: _getStatusColor().withOpacity(0.1),
              radius: 18,
              child: Icon(Icons.wifi, color: _getStatusColor(), size: 18),
            ),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(statusText, style: TextStyle(color: _getStatusColor(), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),
              
              const SectionTitle("ENVIRONMENT"),
              Row(
                children: [
                  Expanded(child: ModernInfoCard("Temperature", "$temperatura°C", Icons.thermostat_rounded, const Color(0xFFFF9800))),
                  const SizedBox(width: 15),
                  Expanded(child: ModernInfoCard("Humidity", "$umiditate%", Icons.water_drop_rounded, const Color(0xFF2196F3))),
                ],
              ),

              const SizedBox(height: 15),

              // AFISARE LUX PE DASHBOARD (CONFORM CERINTEI)
              ModernInfoCard(
                "Luminosity", 
                "$luxValue lx", 
                Icons.wb_sunny_rounded, 
                Colors.amber,
                fullWidth: true,
              ),

              const SizedBox(height: 25),

              const SectionTitle("WEMOS SENSORS"),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.wb_sunny_rounded, color: Colors.amber, size: 24),
                            ),
                            const SizedBox(width: 15),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Luminosity", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                                Text("BH1750 Sensor", style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                              ],
                            ),
                          ],
                        ),
                        Text("$luxValue lx", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                      ],
                    ),
                    const Divider(height: 30),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Auto-Light Threshold", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            Text("${lightThreshold.toInt()} lx", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Slider(
                          value: lightThreshold,
                          min: 0,
                          max: 500,
                          divisions: 50,
                          label: "${lightThreshold.toInt()} lx",
                          onChanged: (val) {
                            setState(() => lightThreshold = val);
                          },
                          onChangeEnd: (val) {
                            _mqttService.publish("smarthome/settings/update", val.toInt().toString());
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              const SectionTitle("LIGHTING CONTROL"),
              _buildBulbCard(),
              const SizedBox(height: 15),
              _buildThrCard(), // NOU: Card pentru Sonoff THR
              const SizedBox(height: 30),
              const SectionTitle("SMART PLUG S60"),
              _buildPlugCard(),
              const SizedBox(height: 40),
              _buildAnalyticsButton(),
              const SizedBox(height: 20),
              
              // NOILE BUTOANE DE NAVIGARE (CERINTA UTILIZATOR)
              Row(
                children: [
                  Expanded(
                    child: _buildNavigationButton(
                      "Senzori", 
                      Icons.lightbulb_circle_rounded, 
                      Colors.orange, 
                      () => Navigator.push(
                        context, 
                        MaterialPageRoute(
                          builder: (context) => SensorsPage(
                            lastBulb: lastBulbUpdate,
                            lastLux: lastLuxUpdate,
                            lastBme: lastBmeUpdate,
                          )
                        )
                      )
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildNavigationButton(
                      "Automatizări", 
                      Icons.settings_suggest_rounded, 
                      Colors.indigo, 
                      () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AutomationsPage()))
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (connectionStatus == MqttStatus.connected) return Colors.green;
    if (connectionStatus == MqttStatus.error) return Colors.red;
    return Colors.orange;
  }

  // Widget auxiliar pentru butoanele de navigare de la finalul paginii
  Widget _buildNavigationButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildBulbCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bulbStatus == "ON" ? Colors.yellow.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.lightbulb_outline_rounded, color: bulbStatus == "ON" ? Colors.orange : Colors.grey, size: 28),
        ),
        title: const Text("Philips WiZ Bulb", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Status: $bulbStatus"),
        trailing: Switch(
          value: bulbStatus == "ON",
          onChanged: (v) {
            String command = v ? 'on' : 'off';
            _mqttService.publish('smarthome/bulb/command', command);
            // Optimistic UI update: actualizam starea local pentru feedback instantaneu
            setState(() => bulbStatus = v ? "ON" : "OFF");
          },
          activeColor: Colors.orange,
        ),
      ),
    );
  }

  Widget _buildThrCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: thrStatus == "ON" ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.settings_input_component_rounded, color: thrStatus == "ON" ? Colors.blue : Colors.grey, size: 28),
        ),
        title: const Text("Sonoff THR320 Switch", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Status: $thrStatus"),
        trailing: Switch(
          value: thrStatus == "ON",
          onChanged: (v) {
            String command = v ? 'ON' : 'OFF';
            _mqttService.publish('smarthome/thr/command', command);
            setState(() => thrStatus = v ? "ON" : "OFF");
          },
          activeColor: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildPlugCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.power_rounded, color: plugStatus == "ON" ? Colors.green : Colors.grey, size: 24),
                  const SizedBox(width: 12),
                  const Text("Main Power", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              Switch(
                value: plugStatus == "ON",
                activeColor: Colors.green,
                onChanged: (val) {
                  _mqttService.publish('smarthome/plug/command', val ? 'ON' : 'OFF');
                  setState(() => plugStatus = val ? 'ON' : 'OFF');
                },
              ),
            ],
          ),
          const Divider(height: 40, color: Color(0xFFF0F0F0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              EnergyStatItem("Power", "${putereW.toStringAsFixed(1)}W", Icons.bolt_rounded, Colors.purple),
              EnergyStatItem("Voltage", "${voltajV.toInt()}V", Icons.electrical_services_rounded, Colors.blueGrey),
              EnergyStatItem("Current", "${curentA.toStringAsFixed(2)}A", Icons.speed_rounded, Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => IstoricDetaliatScreenV2(dataPoints: puncteGrafic))
      ),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF3F51B5)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_rounded, color: Colors.white),
            SizedBox(width: 12),
            Text("VIEW DETAILED ANALYTICS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15, left: 4),
    child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blueGrey[300], letterSpacing: 1.5)),
  );
}

class ModernInfoCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  final bool fullWidth; // NOU
  const ModernInfoCard(this.label, this.value, this.icon, this.color, {super.key, this.fullWidth = false});
  @override
  Widget build(BuildContext context) => Container(
    width: fullWidth ? double.infinity : null,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 16),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
      ],
    ),
  );
}

class EnergyStatItem extends StatelessWidget {
  final String label, val; final IconData icon; final Color color;
  const EnergyStatItem(this.label, this.val, this.icon, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 8),
      Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2D3142))),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.w700)),
    ],
  );
}

class IstoricDetaliatScreenV2 extends StatelessWidget {
  final List<FlSpot> dataPoints;
  const IstoricDetaliatScreenV2({super.key, required this.dataPoints});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), 
      appBar: AppBar(
        title: const Text("ANALYTICS ENGINE V2", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: Color(0xFF1A237E))),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A237E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: dataPoints.isEmpty 
        ? const Center(child: Text("Waiting for sensor data..."))
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 25),
                _buildSummary(),
                const SizedBox(height: 30),
                _buildChart(),
                const SizedBox(height: 30),
                _buildLog(),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF3949AB)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Architecture Status", style: TextStyle(color: Colors.white70, fontSize: 12)),
            SizedBox(height: 4),
            Text("V2 ENGINE: ACTIVE", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          Icon(Icons.layers_rounded, color: Colors.white, size: 35),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    double avg = dataPoints.isEmpty ? 0 : dataPoints.map((e) => e.y).reduce((a, b) => a + b) / dataPoints.length;
    return Row(children: [
      Expanded(child: _statCard("AVERAGE", "${avg.toStringAsFixed(1)}°C", Colors.blue)),
      const SizedBox(width: 15),
      Expanded(child: _statCard("DATAPOINTS", "${dataPoints.length}", Colors.indigo)),
    ]);
  }

  Widget _statCard(String label, String val, Color col) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w800)),
        Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: col)),
      ]),
    );
  }

  Widget _buildChart() {
    return Container(
      height: 250, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: LineChart(LineChartData(
        lineBarsData: [LineChartBarData(
          spots: dataPoints, isCurved: true, color: const Color(0xFF1A237E), barWidth: 4, dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: const Color(0xFF1A237E).withOpacity(0.1)),
        )],
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      )),
    );
  }

  Widget _buildLog() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: dataPoints.length > 5 ? 5 : dataPoints.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final p = dataPoints[dataPoints.length - 1 - index];
          return ListTile(
            title: Text("${p.y.toStringAsFixed(1)} °C", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Checkpoint ${p.x.toInt()}"),
            leading: const Icon(Icons.history_rounded, size: 20),
          );
        },
      ),
    );
  }
}

// --- PAGINA SENZORI (CERINTA UTILIZATOR) ---
// Afiseaza doar dispozitivele de iluminat si senzorii de lumina inregistrati.
class SensorsPage extends StatelessWidget {
  final DateTime? lastBulb;
  final DateTime? lastLux;
  final DateTime? lastBme;

  const SensorsPage({
    super.key, 
    this.lastBulb, 
    this.lastLux, 
    this.lastBme
  });

  String _calculateStatus(DateTime? lastUpdate) {
    if (lastUpdate == null) return "Unknown";
    final diff = DateTime.now().difference(lastUpdate);
    if (diff.inSeconds < 60) return "Active";
    return "Offline (${diff.inMinutes}m ago)";
  }

  bool _isOnline(DateTime? lastUpdate) {
    if (lastUpdate == null) return false;
    return DateTime.now().difference(lastUpdate).inSeconds < 60;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("SENZORI ȘI LUMINI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle("DISPOZITIVE DE ILUMINAT"),
          _buildSensorItem(
            "Philips WiZ Bulb", 
            _calculateStatus(lastBulb), 
            Icons.lightbulb_outline_rounded, 
            Colors.orange,
            _isOnline(lastBulb)
          ),
          const SizedBox(height: 20),
          const SectionTitle("SENZORI ÎNREGISTRAȚI"),
          _buildSensorItem(
            "BH1750 (Luminosity)", 
            _calculateStatus(lastLux), 
            Icons.wb_sunny_rounded, 
            Colors.amber,
            _isOnline(lastLux)
          ),
          _buildSensorItem(
            "BME280 (Climate)", 
            _calculateStatus(lastBme), 
            Icons.thermostat_rounded, 
            Colors.blue,
            _isOnline(lastBme)
          ),
        ],
      ),
    );
  }

  Widget _buildSensorItem(String name, String status, IconData icon, Color color, bool isOnline) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          status, 
          style: TextStyle(
            color: isOnline ? Colors.green : Colors.red, 
            fontSize: 12,
            fontWeight: FontWeight.bold
          )
        ),
        trailing: Icon(
          isOnline ? Icons.check_circle : Icons.error_outline, 
          color: isOnline ? Colors.green : Colors.red, 
          size: 18
        ),
      ),
    );
  }
}

// --- PAGINA AUTOMATIZARI (CERINTA UTILIZATOR) ---
// Permite selectarea unui obiect si a unui senzor pentru a crea o logica de control.
class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key});

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  String? selectedDevice;
  String? selectedSensor;
  double threshold = 100.0;

  final List<String> devices = ["Priză S60", "Bec Philips WiZ", "Switch Sonoff"];
  final List<String> sensors = ["Senzor Lumini (Lux)"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("AUTOMATIZĂRI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Configurează o regulă nouă", 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A237E))
            ),
            const SizedBox(height: 10),
            const Text("Alege un dispozitiv care să fie controlat automat în funcție de valorile unui senzor."),
            
            const SizedBox(height: 40),
            
            _buildDropdownLabel("1. Selectează Dispozitivul"),
            _buildDropdown(devices, selectedDevice, (val) => setState(() => selectedDevice = val)),
            
            const SizedBox(height: 30),
            
            _buildDropdownLabel("2. Selectează Senzorul Sursă"),
            _buildDropdown(sensors, selectedSensor, (val) => setState(() => selectedSensor = val)),
            
            const SizedBox(height: 30),
            
            _buildDropdownLabel("3. Prag Declanșare: ${threshold.toInt()} lx"),
            Slider(
              value: threshold,
              min: 0,
              max: 1000,
              divisions: 20,
              activeColor: Colors.indigo,
              onChanged: (v) => setState(() => threshold = v),
            ),
            
            const SizedBox(height: 50),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: (selectedDevice != null && selectedSensor != null) 
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Automatizare salvată cu succes!"))
                      );
                    } 
                  : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                ),
                child: const Text("SALVEAZĂ AUTOMATIZAREA", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildDropdown(List<String> items, String? currentVal, Function(String?) onChange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentVal,
          isExpanded: true,
          hint: const Text("Alege o opțiune"),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChange,
        ),
      ),
    );
  }
}
