import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const SmartHomeApp());
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Home Licență',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Variabilele care vor fi afișate pe ecran
  String temperatura = "--";
  String umiditate = "--";
  String stareReleu = "--";
  String statusConexiune = "Deconectat";

  late MqttServerClient client;

  @override
  void initState() {
    super.initState();
    setupMqtt(); // Conectăm aplicația când se deschide ecranul
  }

  Future<void> setupMqtt() async {
    // ⚠️ ATENȚIE: Pune aici IP-ul Raspberry Pi-ului tău (ex: '192.168.1.xxx')
    client = MqttServerClient('192.168.1.137', 'flutter_phone_123');
    client.port = 1883;
    client.logging(on: false); 
    client.keepAlivePeriod = 20;

    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_phone_123')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    try {
      setState(() => statusConexiune = "Se conectează...");
      await client.connect();
    } catch (e) {
      setState(() => statusConexiune = "Eroare conexiune!");
      client.disconnect();
      return;
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      setState(() => statusConexiune = "Conectat ✅");
      
      // Ne abonăm la topicul unde scuipă Python-ul date
      const topic = 'tele/sonoff/SENSOR';
      client.subscribe(topic, MqttQos.atMostOnce);

      // Aici e MAGIA: ascultăm în continuu
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        print("Am primit: $message");

        // Transformăm textul primit în format JSON și actualizăm ecranul
        try {
          var dateDecodate = jsonDecode(message);
          
          // setState forțează ecranul să se redeseneze cu noile valori
          setState(() {
            temperatura = dateDecodate['BME280']['Temperature'].toString();
            umiditate = dateDecodate['BME280']['Humidity'].toString();
            stareReleu = dateDecodate['Switch'].toString();
          });
        } catch (e) {
          print("Eroare la parsarea JSON-ului: $e");
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Smart Home Dashboard'),
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Status Server: $statusConexiune",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: statusConexiune.contains("✅") ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            
            // Card pentru Temperatură
            CardWidget(
              titlu: "Temperatură",
              valoare: "$temperatura °C",
              iconita: Icons.thermostat,
              culoare: Colors.orange,
            ),
            const SizedBox(height: 15),

            // Card pentru Umiditate
            CardWidget(
              titlu: "Umiditate",
              valoare: "$umiditate %",
              iconita: Icons.water_drop,
              culoare: Colors.blue,
            ),
            const SizedBox(height: 15),

            // Card pentru Releu (Bec/Priză)
            CardWidget(
              titlu: "Stare Releu",
              valoare: stareReleu == "on" ? "PORNIT" : (stareReleu == "off" ? "OPRIT" : stareReleu),
              iconita: Icons.power_settings_new,
              culoare: stareReleu == "on" ? Colors.green : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

// Un widget personalizat ca să nu repetăm codul de 3 ori pentru cele 3 carduri
class CardWidget extends StatelessWidget {
  final String titlu;
  final String valoare;
  final IconData iconita;
  final Color culoare;

  const CardWidget({
    super.key,
    required this.titlu,
    required this.valoare,
    required this.iconita,
    required this.culoare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Icon(iconita, size: 40, color: culoare),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titlu, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                Text(valoare, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}