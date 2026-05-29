import 'dart:async';
import 'dart:convert';
import 'mqtt_service_v2.dart';

/// Definește expeditorul unui mesaj în conversație.
enum MessageSender { user, bot }

/// Modelul de date pentru un mesaj în interfața de chat.
class ChatMessage {
  final MessageSender sender;
  final String text;
  final DateTime timestamp;
  final Map<String, dynamic>? chartData;
  final bool isTyping;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
    this.chartData,
    this.isTyping = false,
  });

  /// Creează un mesaj fictiv care indică faptul că asistentul scrie.
  factory ChatMessage.typing() {
    return ChatMessage(
      sender: MessageSender.bot,
      text: "",
      timestamp: DateTime.now(),
      isTyping: true,
    );
  }
}

/// Serviciul responsabil cu managementul stării conversației și
/// adaptarea topicurilor MQTT pentru interfața Flutter.
class ChatService {
  final MqttServiceV2 mqttService;
  final String sessionId;
  
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  Stream<List<ChatMessage>> get messagesStream => _messagesController.stream;
  
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  
  bool _isTyping = false;
  bool get isTyping => _isTyping;
  
  StreamSubscription? _mqttSubscription;

  ChatService({required this.mqttService, required this.sessionId}) {
    _init();
  }

  void _init() {
    // Ne abonăm la topicurile specifice chatbot-ului AI
    mqttService.subscribe('smarthome/chat/bot_response');
    mqttService.subscribe('smarthome/chat/status');
    
    // Ascultăm mesajele MQTT din rețea și le filtrăm
    _mqttSubscription = mqttService.messageStream.listen((msg) {
      final topic = msg['topic'];
      final payload = msg['payload'];
      
      if (topic == 'smarthome/chat/status') {
        _handleStatus(payload);
      } else if (topic == 'smarthome/chat/bot_response') {
        _handleBotResponse(payload);
      }
    });
  }

  void _handleStatus(String payload) {
    try {
      final data = json.decode(payload);
      if (data['session_id'] == sessionId) {
        final status = data['status'];
        if (status == 'typing') {
          if (!_isTyping) {
            _isTyping = true;
            _notifyListeners();
          }
        } else if (status == 'idle') {
          if (_isTyping) {
            _isTyping = false;
            _notifyListeners();
          }
        }
      }
    } catch (e) {
      print('❌ ChatService: Eroare parsare status: $e');
    }
  }

  void _handleBotResponse(String payload) {
    try {
      final data = json.decode(payload);
      if (data['session_id'] == sessionId) {
        final text = data['text'] ?? '';
        final chartData = data['chart_data'] as Map<String, dynamic>?;
        
        // Răspunsul bot-ului indică terminarea stării de typing
        _isTyping = false;
        
        final botMessage = ChatMessage(
          sender: MessageSender.bot,
          text: text,
          timestamp: DateTime.now(),
          chartData: chartData,
        );
        
        _messages.add(botMessage);
        _notifyListeners();
      }
    } catch (e) {
      print('❌ ChatService: Eroare parsare raspuns bot: $e');
    }
  }

  /// Trimite mesajul utilizatorului pe topicul MQTT și îl adaugă în lista locală
  void sendMessage(String text) {
    if (text.trim().isEmpty) return;
    
    final userMessage = ChatMessage(
      sender: MessageSender.user,
      text: text,
      timestamp: DateTime.now(),
    );
    
    _messages.add(userMessage);
    _notifyListeners();
    
    // Payload trimis ca JSON securizat
    final payload = {
      'session_id': sessionId,
      'message': text,
    };
    mqttService.publish('smarthome/chat/user_message', json.encode(payload));
  }

  /// Trimite un update cu lista de mesaje prin stream
  void _notifyListeners() {
    final list = List<ChatMessage>.from(_messages);
    if (_isTyping) {
      list.add(ChatMessage.typing());
    }
    _messagesController.add(list);
  }

  /// Curățarea abonamentelor pentru prevenirea scurgerilor de memorie (Memory Leaks)
  void dispose() {
    _mqttSubscription?.cancel();
    _messagesController.close();
  }
}
