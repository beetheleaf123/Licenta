import 'dart:async';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Enum pentru starea conexiunii MQTT.
/// Permite UI-ului sa reactioneze elegant la schimbarile de retea.
enum MqttStatus { initial, connecting, connected, disconnected, error }

/// MqttServiceV2 - O versiune decuplata si robusta a clientului MQTT.
/// Foloseste Streams pentru a trimite date catre UI fara a depinde de acesta.
class MqttServiceV2 {
  final String server;
  final String clientIdentifier;
  late MqttServerClient _client;
  
  // Controller pentru datele primite (mesaje pe topicuri)
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Controller pentru statusul conexiunii (Online/Offline/Error)
  final _statusController = StreamController<MqttStatus>.broadcast();
  Stream<MqttStatus> get statusStream => _statusController.stream;

  MqttServiceV2({required this.server, required this.clientIdentifier}) {
    _initializeClient();
  }

  void _initializeClient() {
    _client = MqttServerClient(server, clientIdentifier);
    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    
    // Configuram callback-urile de sistem
    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;
    _client.autoReconnect = true; // Functie nativa a librariei pentru stabilitate

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .authenticateAs('admin', 'beetheleaf123')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client.connectionMessage = connMess;
  }

  /// Metoda asincrona de conectare cu gestionare de exceptii (Error Handling)
  Future<void> connect() async {
    try {
      _statusController.add(MqttStatus.connecting);
      await _client.connect();
    } on NoConnectionException catch (e) {
      print('[MQTT_SERVICE] Eroare fara conexiune: $e');
      _statusController.add(MqttStatus.error);
      _client.disconnect();
    } on SocketException catch (e) {
      print('[MQTT_SERVICE] Eroare de socket (IP gresit sau server picat): $e');
      _statusController.add(MqttStatus.error);
      _client.disconnect();
    } catch (e) {
      print('[MQTT_SERVICE] Eroare neasteptata: $e');
      _statusController.add(MqttStatus.error);
    }
  }

  void _onConnected() {
    _statusController.add(MqttStatus.connected);
    print('[MQTT_SERVICE] Conectat cu succes la $server');
    
    // Incepem sa ascultam stream-ul nativ de update-uri si il "curatam" pentru UI
    _client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      
      // Trimitem datele procesate prin stream-ul nostru custom
      _messageController.add({
        'topic': c[0].topic,
        'payload': payload
      });
    });
  }

  void _onDisconnected() {
    _statusController.add(MqttStatus.disconnected);
    print('[MQTT_SERVICE] Deconectat de la broker.');
  }

  /// Abonare la un topic - include verificare de stare pentru a preveni crash-uri
  void subscribe(String topic) {
    if (_client.connectionStatus?.state == MqttConnectionState.connected) {
      _client.subscribe(topic, MqttQos.atMostOnce);
    } else {
      print('[MQTT_SERVICE] Nu pot subscrie la $topic: Clientul nu este conectat.');
    }
  }

  /// Publicare mesaj - Logica de business pentru comenzi (Bec, Priza)
  void publish(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  /// Eliberarea resurselor - Mandatory pentru a evita memory leaks in Flutter
  void dispose() {
    _messageController.close();
    _statusController.close();
    _client.disconnect();
  }
}
