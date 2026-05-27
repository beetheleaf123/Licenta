import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;

// IMPORTURILE CATRE SERVICIILE NOI (V2)
import 'mqtt_service_v2.dart';
import 'api_service_v2.dart';

/// main_v2CLAUDE.dart - Versiunea cu tab "Receptor IR" adaugat.
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
  List<FlSpot> puncteUmiditate = [];
  bool seIncarcaGraficul = true;

  // --- NOU: LISTA CODURI IR ---
  final List<IrCodeEntry> _irCodes = [];

  // --- NOU: LISTA EVENIMENTE MISCARE ---
  final List<MotionEvent> _motionEvents = [];
  int _motionCounter = 0;

  final String serverIP = '192.168.1.137';

  // --- STATE VARIABILE METEO ---
  String _locationCity = "";
  double _locationLat = 0.0;
  double _locationLon = 0.0;
  Map<String, dynamic>? _currentWeather;
  List<dynamic> _forecastDays = [];
  bool _isWeatherLoading = false;

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
    _mqttService.subscribe('smarthome/wemos/lumina'); // Senzor Lux (topic din Arduino)
    _mqttService.subscribe('smarthome/plug/state');
    _mqttService.subscribe('smarthome/bulb/state');
    _mqttService.subscribe('smarthome/thr/state'); // NOU: State THR
    _mqttService.subscribe('smarthome/wemos/ir'); // NOU: Receptor IR
    _mqttService.subscribe('smarthome/wemos/miscare'); // NOU: Senzor miscare radar
    _mqttService.subscribe('smarthome/settings/location'); // NOU: Locație sincronizată RPi
  }

  void _processIncomingMessage(String topic, String message) {
    setState(() {
      try {
        if (topic == 'tele/sonoff/SENSOR') {
          var data = jsonDecode(message);
          double tempVal = double.parse(data['BME280']['Temperature'].toString());
          double humVal = double.parse(data['BME280']['Humidity'].toString());
          temperatura = tempVal.toStringAsFixed(1);
          umiditate = humVal.toStringAsFixed(1);
          if (data['Switch'] != null) thrStatus = data['Switch'].toString().toUpperCase();
          _updateLiveChart(tempVal, humVal);
          lastBmeUpdate = DateTime.now(); // Update timestamp
          lastThrUpdate = DateTime.now(); // Update switch timestamp
        } 
        else if (topic == 'smarthome/wemos/lumina') {
          // Arduino trimite valoarea ca string simplu (ex: "342"), nu JSON
          luxValue = message.trim();
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
        // NOU: Procesare coduri IR
        else if (topic == 'smarthome/wemos/ir') {
          _irCodes.insert(0, IrCodeEntry(code: message.trim(), timestamp: DateTime.now()));
          // Pastram maxim 100 de intrari pentru a nu consuma prea multa memorie
          if (_irCodes.length > 100) {
            _irCodes.removeLast();
          }
        }
        // NOU: Procesare senzor miscare (radar)
        else if (topic == 'smarthome/wemos/miscare') {
          _motionCounter = int.tryParse(message.trim()) ?? _motionCounter + 1;
          _motionEvents.insert(0, MotionEvent(
            counter: _motionCounter, 
            timestamp: DateTime.now(),
          ));
          if (_motionEvents.length > 100) {
            _motionEvents.removeLast();
          }
        }
        else if (topic == 'smarthome/settings/location') {
          try {
            var data = jsonDecode(message);
            final String city = data['city'] ?? "";
            final double lat = (data['latitude'] as num).toDouble();
            final double lon = (data['longitude'] as num).toDouble();
            if (city.isNotEmpty && lat != 0.0 && lon != 0.0) {
              _locationCity = city;
              _locationLat = lat;
              _locationLon = lon;
              _fetchWeatherForecast(lat, lon, city);
            }
          } catch (e) {
            print('[UI_ERROR] Eroare parsare locatie din MQTT: $e');
          }
        }
      } catch (e) {
        print('[UI_ERROR] Parsare JSON esuata: $e');
      }
    });
  }

  void _updateLiveChart(double t, double h) {
    puncteGrafic.add(FlSpot(puncteGrafic.length.toDouble(), t));
    puncteUmiditate.add(FlSpot(puncteUmiditate.length.toDouble(), h));
    if (puncteGrafic.length > 50) {
      puncteGrafic.removeAt(0);
      puncteGrafic = puncteGrafic.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.y)).toList();
    }
    if (puncteUmiditate.length > 50) {
      puncteUmiditate.removeAt(0);
      puncteUmiditate = puncteUmiditate.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.y)).toList();
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
        puncteUmiditate = data.asMap().entries.map((e) {
          double v = double.parse(e.value['umiditate'].toString());
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

              const SizedBox(height: 30),
              _buildWeatherCard(),
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
              
              // BUTOANE DE NAVIGARE (3 BUTOANE ACUM - CU IR)
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
                      () => Navigator.push(
                        context, 
                        MaterialPageRoute(
                          builder: (context) => AutomationsPage(
                            lightThreshold: lightThreshold,
                            mqttService: _mqttService,
                            onThresholdChanged: (val) => setState(() => lightThreshold = val),
                          )
                        )
                      )
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              // BUTON DEBUGGING (conține IR + Mișcare) - Centrat pe ecran (folosind flex layout sigur)
              Row(
                children: [
                  const Spacer(),
                  Expanded(
                    flex: 2,
                    child: _buildNavigationButton(
                      "Debugging", 
                      Icons.bug_report_rounded, 
                      const Color(0xFF607D8B), 
                      () => Navigator.push(
                        context, 
                        MaterialPageRoute(
                          builder: (context) => DebuggingPage(
                            irCodes: _irCodes,
                            motionEvents: _motionEvents,
                            mqttService: _mqttService,
                          )
                        )
                      )
                    ),
                  ),
                  const Spacer(),
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
        MaterialPageRoute(builder: (context) => IstoricDetaliatScreenV2(
          tempPoints: puncteGrafic,
          humidityPoints: puncteUmiditate,
        ))
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

  Map<String, dynamic> _getWmoDetails(int code) {
    switch (code) {
      case 0:
        return {'desc': 'Senin', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amber};
      case 1:
      case 2:
      case 3:
        return {'desc': 'Parțial Noros', 'icon': Icons.cloud_queue_rounded, 'color': Colors.blueGrey};
      case 45:
      case 48:
        return {'desc': 'Ceață', 'icon': Icons.blur_on_rounded, 'color': Colors.grey};
      case 51:
      case 53:
      case 55:
        return {'desc': 'Boabă de ploaie', 'icon': Icons.grain_rounded, 'color': Colors.lightBlue};
      case 61:
      case 63:
      case 65:
        return {'desc': 'Ploaie', 'icon': Icons.umbrella_rounded, 'color': Colors.blue};
      case 71:
      case 73:
      case 75:
        return {'desc': 'Ninsori', 'icon': Icons.ac_unit_rounded, 'color': Colors.lightBlueAccent};
      case 80:
      case 81:
      case 82:
        return {'desc': 'Averse de ploaie', 'icon': Icons.beach_access_rounded, 'color': Colors.blue};
      case 95:
      case 96:
      case 99:
        return {'desc': 'Furtună', 'icon': Icons.thunderstorm_rounded, 'color': Colors.deepPurple};
      default:
        return {'desc': 'Necunoscut', 'icon': Icons.wb_cloudy_rounded, 'color': Colors.grey};
    }
  }

  String _getDayName(String dateStr) {
    try {
      DateTime dt = DateTime.parse(dateStr);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return "Azi";
      }
      List<String> days = ["Luni", "Marți", "Miercuri", "Joi", "Vineri", "Sâmbătă", "Duminică"];
      return days[dt.weekday - 1];
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _fetchWeatherForecast(double lat, double lon, String city) async {
    if (!mounted) return;
    setState(() {
      _isWeatherLoading = true;
    });

    try {
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max&timezone=auto';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final daily = data['daily'] ?? {};
        setState(() {
          _currentWeather = data['current_weather'];
          _forecastDays = [];
          if (daily['time'] != null) {
            final times = daily['time'] as List;
            for (int i = 0; i < times.length; i++) {
              _forecastDays.add({
                'date': times[i],
                'weathercode': daily['weathercode']?[i] ?? 0,
                'temp_max': daily['temperature_2m_max']?[i] ?? 0.0,
                'temp_min': daily['temperature_2m_min']?[i] ?? 0.0,
                'sunrise': daily['sunrise']?[i] ?? "",
                'sunset': daily['sunset']?[i] ?? "",
                'rain_chance': daily['precipitation_probability_max']?[i] ?? 0,
              });
            }
          }
          _locationCity = city;
          _locationLat = lat;
          _locationLon = lon;
          _isWeatherLoading = false;
        });
      } else {
        setState(() => _isWeatherLoading = false);
      }
    } catch (e) {
      print('[UI_ERROR] Eroare descarcare prognoza meteo: $e');
      if (mounted) {
        setState(() => _isWeatherLoading = false);
      }
    }
  }

  Future<void> _updateLocation(String city, double lat, double lon) async {
    await _fetchWeatherForecast(lat, lon, city);
    
    String sunriseStr = "";
    String sunsetStr = "";
    if (_forecastDays.isNotEmpty) {
      final today = _forecastDays.first;
      if (today['sunrise'] != null && today['sunrise'].toString().contains('T')) {
        sunriseStr = today['sunrise'].toString().split('T').last;
      } else {
        sunriseStr = today['sunrise']?.toString() ?? "";
      }
      if (today['sunset'] != null && today['sunset'].toString().contains('T')) {
        sunsetStr = today['sunset'].toString().split('T').last;
      } else {
        sunsetStr = today['sunset']?.toString() ?? "";
      }
    }
    
    final payload = jsonEncode({
      'city': city,
      'latitude': lat,
      'longitude': lon,
      'sunrise': sunriseStr,
      'sunset': sunsetStr,
    });
    _mqttService.publish('smarthome/settings/location', payload);
  }

  Widget _buildWeatherCard() {
    if (_locationCity.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.wb_sunny_outlined, size: 48, color: Colors.indigo),
            const SizedBox(height: 12),
            const Text(
              "Nicio locație configurată",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              "Configurează un oraș pentru a vedea prognoza meteo locală și coordonatele astronomice.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showCitySearchDialog,
              icon: const Icon(Icons.search),
              label: const Text("Selectează Oraș"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_isWeatherLoading && _currentWeather == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentTemp = _currentWeather != null ? _currentWeather!['temperature']?.toString() ?? '--' : '--';
    final wmoCode = _currentWeather != null ? (_currentWeather!['weathercode'] as num?)?.toInt() ?? 0 : 0;
    final wmo = _getWmoDetails(wmoCode);
    final wmoDesc = wmo['desc'] as String;
    final wmoIcon = wmo['icon'] as IconData;
    final wmoColor = wmo['color'] as Color;

    String sunriseTime = "--:--";
    String sunsetTime = "--:--";
    int rainChance = 0;
    if (_forecastDays.isNotEmpty) {
      final today = _forecastDays.first;
      rainChance = (today['rain_chance'] as num?)?.toInt() ?? 0;
      if (today['sunrise'] != null && today['sunrise'].toString().contains('T')) {
        sunriseTime = today['sunrise'].toString().split('T').last;
      }
      if (today['sunset'] != null && today['sunset'].toString().contains('T')) {
        sunsetTime = today['sunset'].toString().split('T').last;
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3C72).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    _locationCity,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit_location_alt_rounded, color: Colors.white70),
                onPressed: _showCitySearchDialog,
                tooltip: "Schimbă Orașul",
              ),
            ],
          ),
          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$currentTemp",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        "°C",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    wmoDesc,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(wmoIcon, color: wmoColor, size: 48),
              ),
            ],
          ),
          
          const Divider(height: 30, color: Colors.white24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeatherInfoItem(Icons.light_mode_rounded, "Răsărit", sunriseTime, Colors.orangeAccent),
              _buildWeatherInfoItem(Icons.nights_stay_rounded, "Apus", sunsetTime, Colors.deepPurpleAccent),
              _buildWeatherInfoItem(Icons.water_drop_rounded, "Precipit.", "$rainChance%", Colors.lightBlueAccent),
            ],
          ),

          const SizedBox(height: 20),
          const Text(
            "PROGNOZĂ 5 ZILE",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 115,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _forecastDays.length > 5 ? 5 : _forecastDays.length,
              itemBuilder: (context, index) {
                final day = _forecastDays[index];
                final dayName = _getDayName(day['date']);
                final code = (day['weathercode'] as num?)?.toInt() ?? 0;
                final details = _getWmoDetails(code);
                final dIcon = details['icon'] as IconData;
                final dColor = details['color'] as Color;
                final maxT = (day['temp_max'] as num?)?.toDouble() ?? 0.0;
                final minT = (day['temp_min'] as num?)?.toDouble() ?? 0.0;
                final rChance = (day['rain_chance'] as num?)?.toInt() ?? 0;

                return Container(
                  width: 78,
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dayName,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Icon(dIcon, color: dColor, size: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${maxT.toStringAsFixed(0)}°",
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            "${minT.toStringAsFixed(0)}°",
                            style: const TextStyle(color: Colors.white60, fontSize: 9),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.water_drop, color: Colors.lightBlueAccent, size: 9),
                          const SizedBox(width: 2),
                          Text(
                            "$rChance%",
                            style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherInfoItem(IconData icon, String title, String value, Color iconColor) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _showCitySearchDialog() {
    showDialog(
      context: context,
      builder: (context) => CitySearchDialog(
        onCitySelected: (city, lat, lon) {
          _updateLocation(city, lat, lon);
        },
      ),
    );
  }
}

// --- MODEL PENTRU CODURI IR ---
class IrCodeEntry {
  final String code;
  final DateTime timestamp;
  const IrCodeEntry({required this.code, required this.timestamp});
}

// --- MODEL PENTRU EVENIMENTE MISCARE ---
class MotionEvent {
  final int counter;
  final DateTime timestamp;
  const MotionEvent({required this.counter, required this.timestamp});
}

// --- PAGINA RECEPTOR IR (NOU) ---
class ReceptorIRPage extends StatefulWidget {
  final List<IrCodeEntry> irCodes;
  final MqttServiceV2 mqttService;

  const ReceptorIRPage({
    super.key, 
    required this.irCodes,
    required this.mqttService,
  });

  @override
  State<ReceptorIRPage> createState() => _ReceptorIRPageState();
}

class _ReceptorIRPageState extends State<ReceptorIRPage> {
  late StreamSubscription _irSubscription;
  final List<IrCodeEntry> _localCodes = [];

  @override
  void initState() {
    super.initState();
    // Copiem codurile existente primite inainte de deschiderea paginii
    _localCodes.addAll(widget.irCodes);

    // Ascultam in timp real mesajele noi de pe topicul IR
    _irSubscription = widget.mqttService.messageStream.listen((data) {
      if (data['topic'] == 'smarthome/wemos/ir') {
        setState(() {
          final entry = IrCodeEntry(
            code: data['payload'].toString().trim(), 
            timestamp: DateTime.now(),
          );
          _localCodes.insert(0, entry);
          // Sincronizam si lista din dashboard
          widget.irCodes.insert(0, entry);
          if (_localCodes.length > 100) _localCodes.removeLast();
          if (widget.irCodes.length > 100) widget.irCodes.removeLast();
        });
      }
    });
  }

  @override
  void dispose() {
    _irSubscription.cancel();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:"
           "${dt.minute.toString().padLeft(2, '0')}:"
           "${dt.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- HEADER CU STATUS ---
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE91E63), Color(0xFFAD1457)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E63).withOpacity(0.3), 
                blurRadius: 15, 
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Live IR Monitor", 
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "smarthome/wemos/ir", 
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${_localCodes.length} coduri primite",
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Buton stergere
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _localCodes.clear();
                              widget.irCodes.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text("Șterge", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings_remote_rounded, color: Colors.white, size: 32),
              ),
            ],
          ),
        ),

        // --- LISTA CODURI IR IN TIMP REAL ---
        Expanded(
          child: _localCodes.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sensors_off_rounded, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      "Niciun cod IR primit încă",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Apasă un buton pe telecomandă...",
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _localCodes.length,
                itemBuilder: (context, index) {
                  final entry = _localCodes[index];
                  final isFirst = index == 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: isFirst 
                        ? Border.all(color: const Color(0xFFE91E63).withOpacity(0.4), width: 1.5) 
                        : null,
                      boxShadow: [
                        BoxShadow(
                          color: isFirst 
                            ? const Color(0xFFE91E63).withOpacity(0.08) 
                            : Colors.black.withOpacity(0.02), 
                          blurRadius: 10, 
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isFirst 
                            ? const Color(0xFFE91E63).withOpacity(0.1) 
                            : Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.nfc_rounded, 
                          color: isFirst ? const Color(0xFFE91E63) : Colors.grey, 
                          size: 22,
                        ),
                      ),
                      title: Text(
                        entry.code,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isFirst ? const Color(0xFFE91E63) : const Color(0xFF2D3142),
                        ),
                      ),
                      subtitle: Text(
                        _formatTime(entry.timestamp),
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                      trailing: isFirst 
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE91E63).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              "NOU",
                              style: TextStyle(
                                color: Color(0xFFE91E63), 
                                fontSize: 10, 
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : Text(
                            "#${_localCodes.length - index}",
                            style: TextStyle(fontSize: 11, color: Colors.grey[300], fontWeight: FontWeight.bold),
                          ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }
}

// --- WIDGET-URI REUTILIZABILE ---

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
  final List<FlSpot> tempPoints;
  final List<FlSpot> humidityPoints;
  
  const IstoricDetaliatScreenV2({
    super.key, 
    required this.tempPoints,
    required this.humidityPoints,
  });

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
      body: tempPoints.isEmpty 
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
                const SectionTitle("TEMPERATURE PROFILE"),
                _buildChart(tempPoints, const Color(0xFF1A237E), "°C", 4.0), // minDelta 4°C
                const SizedBox(height: 30),
                const SectionTitle("HUMIDITY PROFILE"),
                _buildChart(humidityPoints, const Color(0xFF0288D1), "%", 10.0), // minDelta 10%
                const SizedBox(height: 30),
                const SectionTitle("EVENT HISTORY (LAST 5 CHECKPOINTS)"),
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
    double avgTemp = tempPoints.isEmpty ? 0 : tempPoints.map((e) => e.y).reduce((a, b) => a + b) / tempPoints.length;
    double avgHum = humidityPoints.isEmpty ? 0 : humidityPoints.map((e) => e.y).reduce((a, b) => a + b) / humidityPoints.length;
    return Row(children: [
      Expanded(child: _statCard("AVG TEMP", "${avgTemp.toStringAsFixed(1)}°C", const Color(0xFF1A237E))),
      const SizedBox(width: 12),
      Expanded(child: _statCard("AVG HUMIDITY", "${avgHum.toStringAsFixed(1)}%", const Color(0xFF0288D1))),
      const SizedBox(width: 12),
      Expanded(child: _statCard("DATAPOINTS", "${tempPoints.length}", Colors.grey[800]!)),
    ]);
  }

  Widget _statCard(String label, String val, Color col) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w800)),
        Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: col)),
      ]),
    );
  }

  Widget _buildChart(List<FlSpot> spots, Color baseColor, String unit, double minDelta) {
    if (spots.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Text("Waiting for data...", style: TextStyle(color: Colors.grey[400])),
      );
    }

    double minX = spots.map((e) => e.x).reduce((a, b) => a < b ? a : b);
    double maxX = spots.map((e) => e.x).reduce((a, b) => a > b ? a : b);
    double xInterval = ((maxX - minX) / 5).ceilToDouble();
    if (xInterval < 1) xInterval = 1;

    double minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    double delta = maxY - minY;
    
    if (delta < minDelta) {
      // Impunem o plajă minimă (minDelta) pentru a preveni fluctuațiile minuscule să pară dramatice
      double padding = (minDelta - delta) / 2;
      minY = minY - padding;
      maxY = maxY + padding;
    } else {
      // Padding standard de 15% pentru a preveni atingerea marginilor fizice ale graficului
      double padding = delta * 0.15;
      minY = minY - padding;
      maxY = maxY + padding;
    }

    return Container(
      height: 280,
      padding: const EdgeInsets.only(top: 25, right: 25, left: 10, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineTouchData: const LineTouchData(enabled: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              gradient: LinearGradient(
                colors: [baseColor.withOpacity(0.7), baseColor],
              ),
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    baseColor.withOpacity(0.2),
                    baseColor.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8,
                    child: Text(
                      "C${value.toInt()}",
                      style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8,
                    child: Text(
                      "${value.toStringAsFixed(1)}$unit",
                      style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[100]!,
                strokeWidth: 1,
                dashArray: const [5, 5],
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              left: BorderSide(color: Colors.grey[200]!, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLog() {
    int logCount = tempPoints.length > 5 ? 5 : tempPoints.length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
      ),
      child: ListView.separated(
        shrinkWrap: true, 
        physics: const NeverScrollableScrollPhysics(),
        itemCount: logCount,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
        itemBuilder: (context, index) {
          final tPoint = tempPoints[tempPoints.length - 1 - index];
          final hPoint = index < humidityPoints.length ? humidityPoints[humidityPoints.length - 1 - index] : null;
          String humText = hPoint != null ? " | Hum: ${hPoint.y.toStringAsFixed(1)}%" : "";
          
          return ListTile(
            title: Text(
              "Temp: ${tPoint.y.toStringAsFixed(1)}°C$humText", 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
            ),
            subtitle: Text("Checkpoint ${tPoint.x.toInt()}", style: const TextStyle(fontSize: 11)),
            leading: const Icon(Icons.history_rounded, size: 20, color: Colors.blueGrey),
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
// Acum include si slider-ul de Auto-Light Threshold (mutat din dashboard).
class AutomationsPage extends StatefulWidget {
  final double lightThreshold;
  final MqttServiceV2 mqttService;
  final ValueChanged<double> onThresholdChanged;

  const AutomationsPage({
    super.key,
    required this.lightThreshold,
    required this.mqttService,
    required this.onThresholdChanged,
  });

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  late double _luxThreshold;
  List<dynamic> _rules = [];
  bool _isLoading = true;
  StreamSubscription? _mqttSubscription;

  @override
  void initState() {
    super.initState();
    _luxThreshold = widget.lightThreshold;

    // Subscriere la topicul de reguli
    widget.mqttService.subscribe('smarthome/rules/list');

    // Ascultăm mesajele MQTT
    _mqttSubscription = widget.mqttService.messageStream.listen((data) {
      if (data['topic'] == 'smarthome/rules/list') {
        try {
          final decoded = jsonDecode(data['payload']);
          if (decoded is List) {
            setState(() {
              _rules = decoded;
              _isLoading = false;
            });
          }
        } catch (e) {
          print('[UI_ERROR] Eroare decodare reguli: $e');
        }
      }
    });

    // Trimitem o cerere pentru a obține regulile actuale
    Timer(const Duration(milliseconds: 500), () {
      widget.mqttService.publish('smarthome/rules/get', '');
    });
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    super.dispose();
  }

  void _toggleRuleActive(Map<String, dynamic> rule, bool active) {
    final updatedRule = Map<String, dynamic>.from(rule);
    updatedRule['is_active'] = active ? 1 : 0;
    widget.mqttService.publish('smarthome/rules/save', jsonEncode(updatedRule));
  }

  void _deleteRule(int ruleId) {
    widget.mqttService.publish('smarthome/rules/delete', ruleId.toString());
  }

  void _openAddRuleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddRuleBottomSheet(),
    ).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        widget.mqttService.publish('smarthome/rules/save', jsonEncode(result));
      }
    });
  }

  String _getSensorName(String code) {
    switch (code) {
      case 'temperature': return 'Temperatură';
      case 'humidity': return 'Umiditate';
      case 'luminosity': return 'Luminozitate';
      case 'motion': return 'Mișcare';
      default: return code;
    }
  }

  IconData _getSensorIcon(String code) {
    switch (code) {
      case 'temperature': return Icons.thermostat_rounded;
      case 'humidity': return Icons.water_drop_rounded;
      case 'luminosity': return Icons.wb_sunny_rounded;
      case 'motion': return Icons.directions_walk_rounded;
      default: return Icons.sensors_rounded;
    }
  }

  Color _getSensorColor(String code) {
    switch (code) {
      case 'temperature': return Colors.orange;
      case 'humidity': return Colors.blue;
      case 'luminosity': return Colors.amber;
      case 'motion': return Colors.teal;
      default: return Colors.grey;
    }
  }

  String _getDeviceName(String code) {
    switch (code) {
      case 'bulb': return 'Bec Philips WiZ';
      case 'plug': return 'Priză S60';
      case 'thr': return 'Switch Sonoff THR';
      default: return code;
    }
  }

  IconData _getDeviceIcon(String code) {
    switch (code) {
      case 'bulb': return Icons.lightbulb_outline_rounded;
      case 'plug': return Icons.power_rounded;
      case 'thr': return Icons.settings_input_component_rounded;
      default: return Icons.device_unknown_rounded;
    }
  }

  Color _getDeviceColor(String code) {
    switch (code) {
      case 'bulb': return Colors.orange;
      case 'plug': return Colors.green;
      case 'thr': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _formatRuleExplanation(Map<String, dynamic> rule) {
    final sensor = _getSensorName(rule['sensor']);
    final op = rule['operator'];
    final thresh = rule['threshold'];
    final device = _getDeviceName(rule['target_device']);
    final state = rule['target_state'] == 'ON' ? 'PORNIT' : 'OPRIT';

    if (rule['sensor'] == 'motion') {
      return 'Dacă se detectează mișcare 🏃, atunci comută $device pe $state.';
    } else {
      String unit = '';
      if (rule['sensor'] == 'temperature') unit = '°C';
      if (rule['sensor'] == 'humidity') unit = '%';
      if (rule['sensor'] == 'luminosity') unit = ' lx';

      String opText = op;
      if (op == '<') opText = 'scade sub';
      if (op == '>') opText = 'depășește';
      if (op == '==') opText = 'este egal cu';
      if (op == '<=') opText = 'este mai mic sau egal cu';
      if (op == '>=') opText = 'este mai mare sau egal cu';

      return 'Dacă $sensor $opText ${thresh.toStringAsFixed(1)}$unit, atunci comută $device pe $state.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("AUTOMATIZĂRI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddRuleSheet,
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text("REGULĂ NOUĂ", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          widget.mqttService.publish('smarthome/rules/get', '');
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- AUTOMATIZARE LUMINI (LEGACY) ---
              const Text(
                "Setări Globale",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blueGrey, letterSpacing: 1.5),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                Text("Auto-Light Threshold", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                                Text("Prag implicit pentru Wemos", style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        Text("${_luxThreshold.toInt()} lx", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Slider(
                      value: _luxThreshold,
                      min: 0,
                      max: 500,
                      divisions: 50,
                      label: "${_luxThreshold.toInt()} lx",
                      activeColor: Colors.indigo[900],
                      onChanged: (val) {
                        setState(() => _luxThreshold = val);
                        widget.onThresholdChanged(val);
                      },
                      onChangeEnd: (val) {
                        widget.mqttService.publish("smarthome/settings/update", val.toInt().toString());
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // --- REGULI CONDITIONALE ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Reguli Condiționale Active",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blueGrey, letterSpacing: 1.5),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
                    ),
                ],
              ),
              const SizedBox(height: 15),

              _isLoading
                  ? _buildShimmerLoading()
                  : _rules.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _rules.length,
                          itemBuilder: (context, index) {
                            final rule = _rules[index] as Map<String, dynamic>;
                            final isRuleActive = (rule['is_active'] ?? 1) == 1;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.015), blurRadius: 10, offset: const Offset(0, 5))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: _getSensorColor(rule['sensor']).withOpacity(0.8),
                                        width: 6,
                                      ),
                                    ),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _getSensorColor(rule['sensor']).withOpacity(0.1),
                                        child: Icon(_getSensorIcon(rule['sensor']), color: _getSensorColor(rule['sensor'])),
                                      ),
                                      title: Text(
                                        rule['name'].toString().isNotEmpty ? rule['name'] : 'Regulă Fără Nume',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: const Color(0xFF2D3142),
                                          decoration: isRuleActive ? TextDecoration.none : TextDecoration.lineThrough,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Senzor: ${_getSensorName(rule['sensor'])}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                      ),
                                      trailing: Switch(
                                        value: isRuleActive,
                                        activeColor: Colors.indigo[900],
                                        onChanged: (val) => _toggleRuleActive(rule, val),
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Divider(height: 10),
                                              const SizedBox(height: 10),
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(Icons.arrow_right_alt_rounded, color: Colors.indigo, size: 20),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      _formatRuleExplanation(rule),
                                                      style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 15),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        _getDeviceIcon(rule['target_device']),
                                                        size: 16,
                                                        color: _getDeviceColor(rule['target_device']),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        _getDeviceName(rule['target_device']),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey[600],
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  TextButton.icon(
                                                    onPressed: () => _deleteRule(rule['id']),
                                                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                                    label: const Text("Șterge", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: Colors.red[700],
                                                      padding: EdgeInsets.zero,
                                                      minimumSize: const Size(50, 30),
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.rule_folder_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text(
            "Nu ai nicio regulă definită",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D3142)),
          ),
          const SizedBox(height: 8),
          Text(
            "Creează reguli de tip Dacă / Atunci când folosind butonul de mai jos.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          height: 70,
          margin: const EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}

class AddRuleBottomSheet extends StatefulWidget {
  const AddRuleBottomSheet({super.key});

  @override
  State<AddRuleBottomSheet> createState() => _AddRuleBottomSheetState();
}

class _AddRuleBottomSheetState extends State<AddRuleBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  String _selectedSensor = 'temperature';
  String _selectedOperator = '>';
  double _threshold = 25.0;
  String _selectedDevice = 'bulb';
  String _selectedState = 'ON';

  // Opțiuni dropdown
  final List<Map<String, String>> _sensors = [
    {'value': 'temperature', 'label': 'Temperatură (°C)'},
    {'value': 'humidity', 'label': 'Umiditate (%)'},
    {'value': 'luminosity', 'label': 'Luminozitate (lux)'},
    {'value': 'motion', 'label': 'Senzor Mișcare (Radar)'},
  ];

  final List<Map<String, String>> _operators = [
    {'value': '>', 'label': 'Mai mare ca (>)'},
    {'value': '<', 'label': 'Mai mic ca (<)'},
    {'value': '==', 'label': 'Egal cu (==)'},
  ];

  final List<Map<String, String>> _devices = [
    {'value': 'bulb', 'label': 'Bec Philips WiZ'},
    {'value': 'plug', 'label': 'Priză Smart S60'},
    {'value': 'thr', 'label': 'Switch Sonoff THR'},
  ];

  final List<Map<String, String>> _states = [
    {'value': 'ON', 'label': 'Pornit (ON)'},
    {'value': 'OFF', 'label': 'Oprit (OFF)'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ajustăm slider-ul în funcție de senzorul selectat
    double sliderMin = 0.0;
    double sliderMax = 100.0;
    int sliderDivisions = 100;
    String sliderLabel = '';

    if (_selectedSensor == 'temperature') {
      sliderMin = 0.0;
      sliderMax = 50.0;
      sliderDivisions = 100;
      sliderLabel = '${_threshold.toStringAsFixed(1)} °C';
      if (_threshold > sliderMax) _threshold = sliderMax;
      if (_threshold < sliderMin) _threshold = sliderMin;
    } else if (_selectedSensor == 'humidity') {
      sliderMin = 0.0;
      sliderMax = 100.0;
      sliderDivisions = 100;
      sliderLabel = '${_threshold.toInt()}%';
      if (_threshold > sliderMax) _threshold = sliderMax;
      if (_threshold < sliderMin) _threshold = sliderMin;
    } else if (_selectedSensor == 'luminosity') {
      sliderMin = 0.0;
      sliderMax = 1000.0;
      sliderDivisions = 100;
      sliderLabel = '${_threshold.toInt()} lx';
      if (_threshold > sliderMax) _threshold = sliderMax;
      if (_threshold < sliderMin) _threshold = sliderMin;
    }

    final isMotion = _selectedSensor == 'motion';

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FB),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Indicator de tragere sus
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.add_task_rounded, color: Colors.indigo[900], size: 24),
                  const SizedBox(width: 10),
                  const Text(
                    "Creează Regulă Nouă",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Câmp text Nume Regulă
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Nume Regulă (opțional)",
                  hintText: "ex: Oprește căldura dacă e cald",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
              ),
              const SizedBox(height: 20),

              // Dropdown Senzor Sursă
              DropdownButtonFormField<String>(
                value: _selectedSensor,
                decoration: InputDecoration(
                  labelText: "1. Senzor Sursă",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.sensors_rounded),
                ),
                items: _sensors
                    .map((s) => DropdownMenuItem(value: s['value'], child: Text(s['label']!)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSensor = val;
                      if (val == 'motion') {
                        _selectedOperator = 'motion_detected';
                        _threshold = 0.0;
                      } else {
                        _selectedOperator = '>';
                        _threshold = val == 'temperature' ? 25.0 : val == 'humidity' ? 50.0 : 100.0;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 20),

              if (!isMotion) ...[
                // Dropdown Operator Condiție (doar dacă nu este mișcare)
                DropdownButtonFormField<String>(
                  value: _selectedOperator,
                  decoration: InputDecoration(
                    labelText: "2. Condiție / Operator",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.compare_arrows_rounded),
                  ),
                  items: _operators
                      .map((op) => DropdownMenuItem(value: op['value'], child: Text(op['label']!)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedOperator = val);
                    }
                  },
                ),
                const SizedBox(height: 20),

                // Slider pentru Prag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Valoare Prag",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          Text(
                            sliderLabel,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                        ],
                      ),
                      Slider(
                        value: _threshold,
                        min: sliderMin,
                        max: sliderMax,
                        divisions: sliderDivisions,
                        label: sliderLabel,
                        activeColor: Colors.indigo,
                        onChanged: (v) => setState(() => _threshold = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Dropdown Dispozitiv Țintă
              DropdownButtonFormField<String>(
                value: _selectedDevice,
                decoration: InputDecoration(
                  labelText: isMotion ? "2. Controlează Dispozitivul" : "3. Controlează Dispozitivul",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.devices_other_rounded),
                ),
                items: _devices
                    .map((d) => DropdownMenuItem(value: d['value'], child: Text(d['label']!)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDevice = val);
                  }
                },
              ),
              const SizedBox(height: 20),

              // Dropdown Stare Dispozitiv
              DropdownButtonFormField<String>(
                value: _selectedState,
                decoration: InputDecoration(
                  labelText: isMotion ? "3. Stare Dorită" : "4. Stare Dorită",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.power_settings_new_rounded),
                ),
                items: _states
                    .map((st) => DropdownMenuItem(value: st['value'], child: Text(st['label']!)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedState = val);
                  }
                },
              ),
              const SizedBox(height: 35),

              // Buton de Salvare
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      String finalName = _nameController.text.trim();
                      if (finalName.isEmpty) {
                        finalName = "Regulă ${_selectedSensor == 'motion' ? 'Mișcare' : _selectedSensor == 'temperature' ? 'Climă' : _selectedSensor == 'humidity' ? 'Umiditate' : 'Lumină'}";
                      }
                      
                      final rule = {
                        "name": finalName,
                        "sensor": _selectedSensor,
                        "operator": _selectedOperator,
                        "threshold": _threshold,
                        "target_device": _selectedDevice,
                        "target_state": _selectedState,
                        "is_active": 1
                      };
                      Navigator.pop(context, rule);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[900],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: const Text("SALVEAZĂ REGULA", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// --- PAGINA DEBUGGING (NOU - conține Receptor IR + Senzor Mișcare) ---
class DebuggingPage extends StatelessWidget {
  final List<IrCodeEntry> irCodes;
  final List<MotionEvent> motionEvents;
  final MqttServiceV2 mqttService;

  const DebuggingPage({
    super.key,
    required this.irCodes,
    required this.motionEvents,
    required this.mqttService,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text("DEBUGGING", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: TabBar(
            labelColor: const Color(0xFF607D8B),
            unselectedLabelColor: Colors.grey[400],
            indicatorColor: const Color(0xFF607D8B),
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.settings_remote_rounded), text: "Senzor IR"),
              Tab(icon: Icon(Icons.radar_rounded), text: "Mișcare"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ReceptorIRPage(irCodes: irCodes, mqttService: mqttService),
            MotionSensorPage(motionEvents: motionEvents, mqttService: mqttService),
          ],
        ),
      ),
    );
  }
}

// --- PAGINA SENZOR MISCARE (NOU) ---
class MotionSensorPage extends StatefulWidget {
  final List<MotionEvent> motionEvents;
  final MqttServiceV2 mqttService;

  const MotionSensorPage({
    super.key,
    required this.motionEvents,
    required this.mqttService,
  });

  @override
  State<MotionSensorPage> createState() => _MotionSensorPageState();
}

class _MotionSensorPageState extends State<MotionSensorPage> with SingleTickerProviderStateMixin {
  late StreamSubscription _motionSubscription;
  final List<MotionEvent> _localEvents = [];
  late AnimationController _pulseController;
  bool _justDetected = false;

  @override
  void initState() {
    super.initState();
    _localEvents.addAll(widget.motionEvents);

    // Animatie puls pentru detectare
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Ascultam in timp real
    _motionSubscription = widget.mqttService.messageStream.listen((data) {
      if (data['topic'] == 'smarthome/wemos/miscare') {
        final counter = int.tryParse(data['payload'].toString().trim()) ?? _localEvents.length + 1;
        final event = MotionEvent(counter: counter, timestamp: DateTime.now());
        setState(() {
          _localEvents.insert(0, event);
          widget.motionEvents.insert(0, event);
          if (_localEvents.length > 100) _localEvents.removeLast();
          if (widget.motionEvents.length > 100) widget.motionEvents.removeLast();
          _justDetected = true;
        });
        // Trigger animatie puls
        _pulseController.forward(from: 0.0);
        // Resetam indicatorul dupa 3 secunde
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _justDetected = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _motionSubscription.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:"
           "${dt.minute.toString().padLeft(2, '0')}:"
           "${dt.second.toString().padLeft(2, '0')}";
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return "Acum";
    if (diff.inSeconds < 60) return "acum ${diff.inSeconds}s";
    if (diff.inMinutes < 60) return "acum ${diff.inMinutes}m";
    return "acum ${diff.inHours}h";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- HEADER CU INDICATOR LIVE ---
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _justDetected 
                ? [const Color(0xFFFF5722), const Color(0xFFD84315)]
                : [const Color(0xFF00BCD4), const Color(0xFF00838F)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (_justDetected ? const Color(0xFFFF5722) : const Color(0xFF00BCD4)).withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _justDetected ? "⚡ MIȘCARE DETECTATĂ!" : "Radar Microunde",
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: _justDetected ? 16 : 12, 
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "smarthome/wemos/miscare",
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${_localEvents.length} detectări",
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_localEvents.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Ultima: ${_timeAgo(_localEvents.first.timestamp)}",
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Buton stergere
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _localEvents.clear();
                              widget.motionEvents.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text("Șterge", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Indicator animat
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.15),
                      border: Border.all(
                        color: Colors.white.withOpacity(
                          _justDetected ? (0.3 + 0.7 * (1 - _pulseController.value)) : 0.2
                        ),
                        width: _justDetected ? 3 : 1.5,
                      ),
                    ),
                    child: Icon(
                      _justDetected ? Icons.sensors_rounded : Icons.radar_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // --- LISTA EVENIMENTE ---
        Expanded(
          child: _localEvents.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.radar_rounded, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      "Nicio mișcare detectată",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Radarul monitorizează zona...",
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _localEvents.length,
                itemBuilder: (context, index) {
                  final event = _localEvents[index];
                  final isFirst = index == 0;
                  final isRecent = DateTime.now().difference(event.timestamp).inSeconds < 5;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: (isFirst && isRecent)
                        ? Border.all(color: const Color(0xFFFF5722).withOpacity(0.5), width: 1.5)
                        : null,
                      boxShadow: [
                        BoxShadow(
                          color: (isFirst && isRecent)
                            ? const Color(0xFFFF5722).withOpacity(0.08)
                            : Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (isFirst && isRecent)
                            ? const Color(0xFFFF5722).withOpacity(0.1)
                            : const Color(0xFF00BCD4).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.directions_walk_rounded,
                          color: (isFirst && isRecent) ? const Color(0xFFFF5722) : const Color(0xFF00BCD4),
                          size: 22,
                        ),
                      ),
                      title: Text(
                        "Mișcare #${event.counter}",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: (isFirst && isRecent) ? const Color(0xFFFF5722) : const Color(0xFF2D3142),
                        ),
                      ),
                      subtitle: Text(
                        _formatTime(event.timestamp),
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                      trailing: (isFirst && isRecent)
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5722).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              "LIVE",
                              style: TextStyle(
                                color: Color(0xFFFF5722),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : Text(
                            _timeAgo(event.timestamp),
                            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                          ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }
}

class CitySearchDialog extends StatefulWidget {
  final Function(String city, double lat, double lon) onCitySelected;
  const CitySearchDialog({super.key, required this.onCitySelected});

  @override
  State<CitySearchDialog> createState() => _CitySearchDialogState();
}

class _CitySearchDialogState extends State<CitySearchDialog> {
  final _searchController = TextEditingController();
  List<dynamic> _suggestions = [];
  bool _isLoading = false;
  String _errorMessage = "";

  Future<void> _searchCity(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _suggestions = [];
    });

    try {
      final url = 'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(query)}&count=5&language=ro&format=json';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'];
        setState(() {
          _suggestions = results ?? [];
          if (_suggestions.isEmpty) {
            _errorMessage = "Niciun oraș găsit.";
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Eroare server geocodare.";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Eroare rețea/căutare.";
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      backgroundColor: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(22),
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Caută Oraș",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2D3142)),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Introdu numele orașului...",
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.blue),
                  onPressed: () => _searchCity(_searchController.text),
                ),
                filled: true,
                fillColor: const Color(0xFFF5F7FB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _searchCity,
            ),
            const SizedBox(height: 15),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(),
                ),
              ),
              
            if (_errorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(_errorMessage, style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold)),
                ),
              ),
              
            if (!_isLoading && _suggestions.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final item = _suggestions[index];
                    final String name = item['name'] ?? "";
                    final String admin1 = item['admin1'] ?? "";
                    final String country = item['country'] ?? "";
                    final double lat = (item['latitude'] as num).toDouble();
                    final double lon = (item['longitude'] as num).toDouble();
                    
                    final String subtitle = "${admin1.isNotEmpty ? '$admin1, ' : ''}$country";

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE3F2FD),
                        child: Icon(Icons.location_city_rounded, color: Colors.blue),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        "${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}",
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                      onTap: () {
                        widget.onCitySelected(name, lat, lon);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
