import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// main_v3.dart - Versiune minimalistÄƒ pentru testarea exclusivÄƒ a becului.
void main() => runApp(const MaterialApp(home: SimpleBulbTest()));

class SimpleBulbTest extends StatefulWidget {
  const SimpleBulbTest({super.key});
  @override
  State<SimpleBulbTest> createState() => _SimpleBulbTestState();
}

class _SimpleBulbTestState extends State<SimpleBulbTest> {
  late MqttServerClient client;
  String bulbStatus = "OFF";
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _setupMqtt();
  }

  Future<void> _setupMqtt() async {
    // IP-ul Brokerului (Raspberry Pi)
    client = MqttServerClient('192.168.1.137', 'flutter_test_bulb');
    client.port = 1883;
    client.keepAlivePeriod = 20;

    // Configurare autentificare MQTT
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_test_bulb')
        .authenticateAs('admin', 'beetheleaf123')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      await client.connect();
      setState(() => isConnected = true);
      
      // Subscripție pentru a primi starea realÄƒ
      client.subscribe('smarthome/bulb/state', MqttQos.atMostOnce);
      
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        setState(() => bulbStatus = message.toUpperCase());
      });
    } catch (e) {
      print("Eroare MQTT: $e");
    }
  }

  void _sendAction(bool value) {
    if (!isConnected) return;
    String payload = value ? 'on' : 'off';
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    client.publishMessage('smarthome/bulb/command', MqttQos.atLeastOnce, builder.payload!);
    
    // Feedback vizual imediat
    setState(() => bulbStatus = value ? "ON" : "OFF");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("TEST BEC IZOLAT")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lightbulb,
              size: 100,
              color: bulbStatus == "ON" ? Colors.orange : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text("Status: $bulbStatus", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Switch(
              value: bulbStatus == "ON",
              onChanged: _sendAction,
            ),
            const SizedBox(height: 20),
            Text(isConnected ? "CONNECTED ✅" : "DISCONNECTED ❌", 
                 style: TextStyle(color: isConnected ? Colors.green : Colors.red)),
          ],
        ),
      ),
    );
  }
}
