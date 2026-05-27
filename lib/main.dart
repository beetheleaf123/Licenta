import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

// Entry point-ul aplicatiei. Am activat Material 3 pentru componente moderne.
void main() => runApp(const SmartHomeApp());

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      primarySwatch: Colors.indigo, 
      useMaterial3: true,
      fontFamily: 'Roboto', // Font standard, curat
    ),
    home: const DashboardScreen(),
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- STATE VARIABLES ---
  String temperatura = "--";
  String umiditate = "--";
  String luxValue = "--"; // NOU: Valoare senzor lumina
  String statusConexiune = "Initializing...";
  
  String bulbStatus = "OFF";
  String plugStatus = "OFF"; 
  double putereW = 0.0;
  double voltajV = 0.0;
  double curentA = 0.0;

  List<FlSpot> puncteGrafic = [];
  bool seIncarcaGraficul = true;

  late MqttServerClient client;
  final String serverIP = '192.168.1.137';

  @override
  void initState() {
    super.initState();
    setupMqtt();
    fetchHistory();
  }

  // --- BUSINESS LOGIC ---

  // Functie pentru controlul becului WiZ via MQTT
  void controlBulb(bool value) {
    String command = value ? 'on' : 'off';
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    client.publishMessage('smarthome/bulb/command', MqttQos.atLeastOnce, builder.payload!);
    // Optimistic UI update - feedback vizual instantaneu
    setState(() => bulbStatus = value ? 'ON' : 'OFF');
  }

  // Functie pentru controlul prizei S60
  void togglePlug(bool value) {
    String command = value ? "ON" : "OFF";
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    client.publishMessage('smarthome/plug/command', MqttQos.atLeastOnce, builder.payload!);
    // Optimistic UI update - actualizam starea inainte de confirmarea serverului pentru fluiditate
    setState(() => plugStatus = command);
  }

  // Initializarea clientului MQTT si configurarea subscriptiilor
  Future<void> setupMqtt() async {
    client = MqttServerClient(serverIP, 'flutter_client_v2');
    client.port = 1883;
    client.keepAlivePeriod = 20;
    // Handshake configuration
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client_v2')
        .authenticateAs('admin', 'beetheleaf123')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      await client.connect();
      setState(() => statusConexiune = "System Online ✅");
      
      // Subscriem la toate topicele relevante intr-o singura faza
      client.subscribe('tele/sonoff/SENSOR', MqttQos.atMostOnce); 
      client.subscribe('smarthome/wemos/sensor', MqttQos.atMostOnce); // NOU: Topic Senzor Lumina
      client.subscribe('smarthome/plug/state', MqttQos.atMostOnce); 
      client.subscribe('smarthome/bulb/state', MqttQos.atMostOnce); 

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String topic = c[0].topic;
        final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        setState(() {
          if (topic == 'tele/sonoff/SENSOR') {
            // ... logica existenta Sonoff ...
            var data = jsonDecode(message);
            double tempVal = double.parse(data['BME280']['Temperature'].toString());
            temperatura = tempVal.toString();
            umiditate = data['BME280']['Humidity'].toString();

            puncteGrafic.add(FlSpot(puncteGrafic.length.toDouble(), tempVal));
            if (puncteGrafic.length > 50) {
              puncteGrafic.removeAt(0);
              puncteGrafic = puncteGrafic.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.y)).toList();
            }
          } 
          else if (topic == 'smarthome/wemos/sensor') {
            // NOU: Procesare date Lux de la Wemos
            var data = jsonDecode(message);
            luxValue = data['lux'].toString();
          }
          else if (topic == 'smarthome/plug/state') {
            var data = jsonDecode(message);
            putereW = data['power'];
            voltajV = data['voltage'];
            curentA = data['current'];
            if (data['switch'] != null) {
               plugStatus = data['switch'].toString().toUpperCase();
            }
          } 
          else if (topic == 'smarthome/bulb/state') {
            bulbStatus = message.toUpperCase(); 
          }
        });
      });
    } catch (e) {
      setState(() => statusConexiune = "Connection Error ❌");
    }
  }

  // Fetch istoric din baza de date via REST API (Flask pe RPi)
  Future<void> fetchHistory() async {
    try {
      final response = await http.get(Uri.parse('http://$serverIP:5000/istoric')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        List<FlSpot> spots = data.asMap().entries.map((e) {
          double v = double.parse(e.value['temperatura'].toString());
          return FlSpot(e.key.toDouble(), v);
        }).toList();
        setState(() {
          puncteGrafic = spots;
          seIncarcaGraficul = false;
        });
      }
    } catch (e) {
      setState(() => seIncarcaGraficul = false);
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("SMART HUB", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: statusConexiune.contains("✅") ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              radius: 18,
              child: Icon(Icons.wifi, color: statusConexiune.contains("✅") ? Colors.green : Colors.red, size: 18),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusConexiune, style: TextStyle(color: Colors.blueGrey[600], fontSize: 12, fontWeight: FontWeight.w500)),
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
            
            // NOU: Afisare Luminozitate (Lux) pe Dashboard
            ModernInfoCard(
              "Luminosity", 
              "$luxValue lx", 
              Icons.wb_sunny_rounded, 
              Colors.amber,
              fullWidth: true
            ),

            const SizedBox(height: 30),
            
            const SectionTitle("LIGHTING CONTROL"),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
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
                title: const Text("Philips WiZ Bulb", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text("Status: $bulbStatus", style: TextStyle(color: bulbStatus == "ON" ? Colors.green : Colors.grey)),
                trailing: Switch(
                  value: bulbStatus == "ON",
                  onChanged: controlBulb,
                  activeColor: Colors.orange,
                ),
              ),
            ),

            const SizedBox(height: 30),

            const SectionTitle("SMART PLUG S60"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(28),
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
                        onChanged: togglePlug,
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      EnergyStatItem("Power", "${putereW}W", Icons.bolt_rounded, Colors.purple),
                      EnergyStatItem("Voltage", "${voltajV}V", Icons.electrical_services_rounded, Colors.blueGrey),
                      EnergyStatItem("Current", "${curentA}A", Icons.speed_rounded, Colors.teal),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
            
            // Buton Actiune Principala - Analiza Istoric
            GestureDetector(
              onTap: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => IstoricDetaliatScreen(dataPoints: puncteGrafic))
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
                    Text(
                      "VIEW DETAILED ANALYTICS", 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // NOILE BUTOANE DE NAVIGARE (CERINTA UTILIZATOR)
            Row(
              children: [
                Expanded(
                  child: _buildNavigationButton(
                    context,
                    "Senzori", 
                    Icons.sensors_rounded, 
                    Colors.orange, 
                    () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SensorsPage()))
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildNavigationButton(
                    context,
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
    );
  }

  // Widget auxiliar pentru butoanele de navigare
  Widget _buildNavigationButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
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
}

// --- REUSABLE COMPONENTS ---

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15, left: 4),
    child: Text(
      title, 
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blueGrey[300], letterSpacing: 1.5)
    ),
  );
}

class ModernInfoCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  final bool fullWidth; // NOU: Permite afisarea pe toata latimea
  const ModernInfoCard(this.label, this.value, this.icon, this.color, {super.key, this.fullWidth = false});
  @override
  Widget build(BuildContext context) => Container(
    width: fullWidth ? double.infinity : null, // Setam latimea in functie de flag
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
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

// --- DETAILED ANALYTICS SCREEN ---

class IstoricDetaliatScreen extends StatelessWidget {
  final List<FlSpot> dataPoints;
  const IstoricDetaliatScreen({super.key, required this.dataPoints});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), 
      appBar: AppBar(
        title: const Text(
          "ANALYTICS ENGINE", 
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: Color(0xFF1A237E))
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A237E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: dataPoints.isEmpty 
        ? const Center(child: Text("Waiting for data stream..."))
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModernHeader(),
                const SizedBox(height: 25),
                _buildSummaryCards(),
                const SizedBox(height: 30),
                const Text(
                  "TEMPORAL EVOLUTION", 
                  style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5)
                ),
                const SizedBox(height: 15),
                _buildMainChart(),
                const SizedBox(height: 30),
                const Text(
                  "EVENT LOG", 
                  style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5)
                ),
                const SizedBox(height: 15),
                _buildEventList(),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF3949AB)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("System Status", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text("OPTIMIZED", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          Icon(Icons.auto_graph_rounded, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  Widget _buildMainChart() {
    return Container(
      height: 280,
      padding: const EdgeInsets.only(right: 20, top: 20, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: const Color(0xFF1A237E),
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => LineTooltipItem(
                "${spot.y.toStringAsFixed(1)}°C",
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              )).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(value.toInt().toString(), style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
                getTitlesWidget: (value, meta) => Text("${value.toInt()}°", style: TextStyle(color: Colors.grey[400], fontSize: 10)),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: dataPoints,
              isCurved: true,
              curveSmoothness: 0.35,
              color: const Color(0xFF1A237E),
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true, 
                gradient: LinearGradient(
                  colors: [const Color(0xFF1A237E).withOpacity(0.2), const Color(0xFF1A237E).withOpacity(0.0)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    if (dataPoints.isEmpty) return const SizedBox();
    double avg = dataPoints.map((e) => e.y).reduce((a, b) => a + b) / dataPoints.length;
    double max = dataPoints.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    
    return Row(
      children: [
        _statBox("AVG TEMP", "${avg.toStringAsFixed(1)}°C", const Color(0xFF3F51B5), Icons.waves_rounded),
        const SizedBox(width: 15),
        _statBox("PEAK TEMP", "${max.toStringAsFixed(1)}°C", const Color(0xFFE91E63), Icons.trending_up_rounded),
      ],
    );
  }

  Widget _statBox(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w800, letterSpacing: 1)),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(), 
        padding: const EdgeInsets.all(12),
        itemCount: dataPoints.length > 10 ? 10 : dataPoints.length,
        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F4F8)),
        itemBuilder: (context, index) {
          final point = dataPoints[dataPoints.length - 1 - index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF1F4F8), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.history_rounded, color: Color(0xFF1A237E), size: 18),
            ),
            title: Text("${point.y.toStringAsFixed(1)} °C", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
            subtitle: Text("Checkpoint ${point.x.toInt()}", style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
          );
        },
      ),
    );
  }
}

// --- PAGINA SENZORI (CERINTA UTILIZATOR) ---
class SensorsPage extends StatelessWidget {
  const SensorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text("SENZORI ȘI LUMINI"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle("DISPOZITIVE DE ILUMINAT"),
          _buildSensorItem("Philips WiZ Bulb", "Online", Icons.lightbulb_outline, Colors.orange),
          const SizedBox(height: 20),
          const SectionTitle("SENZORI ACTIVI"),
          _buildSensorItem("BME280 (Climate)", "Active", Icons.thermostat, Colors.blue),
          _buildSensorItem("Senzor Lumini (Lux)", "Active", Icons.wb_sunny, Colors.amber),
        ],
      ),
    );
  }

  Widget _buildSensorItem(String name, String status, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(status, style: const TextStyle(color: Colors.green)),
        trailing: const Icon(Icons.check_circle, color: Colors.green, size: 16),
      ),
    );
  }
}

// --- PAGINA AUTOMATIZARI (CERINTA UTILIZATOR) ---
class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key});
  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  String? dev; String? sens; double val = 50.0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text("AUTOMATIZĂRI"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            DropdownButton<String>(
              isExpanded: true, hint: const Text("Selectează Dispozitiv"),
              value: dev, items: ["Priză S60", "Bec WiZ", "Sonoff"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => dev = v),
            ),
            const SizedBox(height: 20),
            DropdownButton<String>(
              isExpanded: true, hint: const Text("Selectează Senzor"),
              value: sens, items: ["Senzor Lumini"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => sens = v),
            ),
            const SizedBox(height: 30),
            Text("Prag: ${val.toInt()}"),
            Slider(value: val, min: 0, max: 100, onChanged: (v) => setState(() => val = v)),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.indigo),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Salvat!"))),
              child: const Text("SALVEAZĂ", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }
}
