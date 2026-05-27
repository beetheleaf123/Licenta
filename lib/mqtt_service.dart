import 'package:mqtt_client/mqtt_client.dart'; // <--- Importul care lipsea!
import 'package:mqtt_client/mqtt_server_client.dart';
// Folosit pentru jsonDecode mai târziu

class MqttHandler {
  late MqttServerClient client;

  Future<void> connect() async {
    // 1. Inițializarea clientului (Pune IP-ul tău real aici)
    client = MqttServerClient('192.168.1.137', 'flutter_client_id');
    client.port = 1883; 
    
    // ACTIVEAZĂ LOGURILE! Asta îți va salva zile întregi de debug.
    client.logging(on: true); 
    client.keepAlivePeriod = 20;

    // 2. Setarea "Pachetului de prezentare"
    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_client_id')
        .authenticateAs('admin', 'beetheleaf123')
        .startClean() // Îi spune serverului să înceapă o sesiune curată
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    // 3. Încercarea de conectare
    try {
      print('Se conectează la Raspberry Pi...');
      await client.connect();
    } catch (e) {
      print('Eroare fatală la conectare: $e');
      client.disconnect();
      return; // Oprim execuția aici dacă a picat
    }

    // 4. Verificarea statusului
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('✅ Conectat cu succes la Broker!');
    } else {
      print('❌ Conexiune eșuată. Status: ${client.connectionStatus!.state}');
      client.disconnect();
      return;
    }

    // 5. Abonarea la canal (Subscribe)
    const topic = 'tele/sonoff/SENSOR'; 
    print('Mă abonez la topicul: $topic');
    client.subscribe(topic, MqttQos.atMostOnce);

    // 6. Ascultarea datelor în timp real
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      
      // Transformăm biții primiți într-un text citibil (String)
      final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      print('📩 Mesaj nou primit de la Sonoff: $message');
      
      // Opțional: Dacă mesajul este de tip JSON, îl poți decoda așa:
      // var dateDecodate = jsonDecode(message);
      // print("Temperatura este: ${dateDecodate['BME280']['Temperature']}");
    });
  }
}