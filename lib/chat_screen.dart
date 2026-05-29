import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'chat_service.dart';
import 'mqtt_service_v2.dart';

/// Pagina de Chatbot AI - Smart Home Assistant
class ChatScreen extends StatefulWidget {
  final MqttServiceV2 mqttService;

  const ChatScreen({Key? key, required this.mqttService}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _chatService;
  late final TextEditingController _messageController;
  late final ScrollController _scrollController;
  
  List<ChatMessage> _messages = [];
  StreamSubscription? _chatSubscription;
  final String _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _scrollController = ScrollController();
    
    // Inițializăm serviciul de chat cu ID-ul unic al acestei sesiuni
    _chatService = ChatService(mqttService: widget.mqttService, sessionId: _sessionId);
    
    // Ascultăm mesajele noi din stream și scrollăm automat în jos
    _chatSubscription = _chatService.messagesStream.listen((messagesList) {
      if (mounted) {
        setState(() {
          _messages = messagesList;
        });
        _scrollToBottom();
      }
    });

    // Mesaj inițial de întâmpinare din partea bot-ului
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _messages = [
          ChatMessage(
            sender: MessageSender.bot,
            text: "Salut! Eu sunt Luffy, asistentul tău Smart Home. Te pot ajuta să afli datele senzorilor live, să controlezi becul/priza/releul sau să-ți generez grafice cu istoricul temperaturii și umidității. Cu ce începem?",
            timestamp: DateTime.now(),
          )
        ];
      });
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _chatService.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      _chatService.sendMessage(text);
      _messageController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'luffy.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.smart_toy_rounded, color: Colors.teal, size: 24),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Luffy",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Gemini 2.5 Flash Conectat",
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey[200], height: 1.0),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Listă mesaje
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
            ),

            // Quick Actions la baza paginii
            _buildQuickActionsRow(),

            // Bara de input mesaje
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  /// Construiește bulele de mesaje
  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.sender == MessageSender.user;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'luffy.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.indigo[50],
                    child: Icon(Icons.smart_toy_rounded, color: Colors.indigo[600], size: 18),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: isUser
                    ? null
                    : LinearGradient(
                        colors: [Colors.indigo[900]!, Colors.indigo[800]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: isUser ? Colors.white : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isTyping)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                      child: _TypingIndicator(),
                    )
                  else ...[
                    Text(
                      message.text,
                      style: TextStyle(
                        color: isUser ? const Color(0xFF1E293B) : Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    if (message.chartData != null) ...[
                      const SizedBox(height: 12),
                      _buildInlineChart(message.chartData!),
                    ],
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _formatMessageTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 9,
                        color: isUser ? Colors.grey[400] : Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.teal[50] ?? Colors.teal,
              child: Icon(Icons.person_rounded, color: Colors.teal[700], size: 18),
            ),
          ],
        ],
      ),
    );
  }

  /// Formatează timpul mesajului (HH:mm)
  String _formatMessageTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  /// Randează graficul inline fl_chart în bula botului
  Widget _buildInlineChart(Map<String, dynamic> chartData) {
    final sensor = chartData['sensor'] as String? ?? 'temperature';
    final rawPoints = chartData['data'] as List<dynamic>? ?? [];
    
    if (rawPoints.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const Text("Grafic gol (fără date istorice)", style: TextStyle(color: Colors.white70, fontSize: 12)),
      );
    }

    // Parsăm punctele pentru fl_chart
    List<FlSpot> spots = [];
    for (var p in rawPoints) {
      if (p['x'] != null && p['y'] != null) {
        final xVal = (p['x'] as num).toDouble();
        final yVal = (p['y'] as num).toDouble();
        spots.add(FlSpot(xVal, yVal));
      }
    }

    if (spots.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const Text("Eroare la parsarea punctelor graficului", style: TextStyle(color: Colors.white70, fontSize: 12)),
      );
    }

    // Determinare limite axa X
    double minX = spots.map((e) => e.x).reduce((a, b) => a < b ? a : b);
    double maxX = spots.map((e) => e.x).reduce((a, b) => a > b ? a : b);
    double xInterval = ((maxX - minX) / 4).ceilToDouble();
    if (xInterval < 1) xInterval = 1;

    // Determinare limite axa Y cu algoritmul de Histerezis (minDelta)
    double minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    double delta = maxY - minY;
    
    // Pragurile din specificații: 4.0 grade pentru temperatură, 10% pentru umiditate
    double minDelta = (sensor == 'humidity') ? 10.0 : 4.0;
    String unit = (sensor == 'humidity') ? '%' : '°C';
    Color chartColor = (sensor == 'humidity') ? const Color(0xFF0288D1) : const Color(0xFFFF5722);

    if (delta < minDelta) {
      // Calculăm media datelor pentru a centra axa Y simetric în jurul ei
      double sum = spots.map((e) => e.y).reduce((a, b) => a + b);
      double vMed = sum / spots.length;
      minY = vMed - (minDelta / 2);
      maxY = vMed + (minDelta / 2);
    } else {
      // Adăugăm padding standard de 15% pentru vizualizare mai clară
      double padding = delta * 0.15;
      minY = minY - padding;
      maxY = maxY + padding;
    }

    // Funcția locală de formatare a timpului pe axa X
    String formatTimestamp(double value) {
      final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      // Dacă intervalul este de peste 24 ore, afișăm data în loc de oră
      if (maxX - minX > 24 * 60 * 60 * 1000) {
        final day = dt.day.toString().padLeft(2, '0');
        final month = dt.month.toString().padLeft(2, '0');
        return "$day/$month";
      }
      return "$hour:$minute";
    }

    return Container(
      height: 180,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 15, right: 15, left: 2, bottom: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.indigo[900]!,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((barSpot) {
                  return LineTooltipItem(
                    "${barSpot.y.toStringAsFixed(1)}$unit",
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: chartColor,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    chartColor.withOpacity(0.2),
                    chartColor.withOpacity(0.0),
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
                reservedSize: 20,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 4,
                    child: Text(
                      formatTimestamp(value),
                      style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 8),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 4,
                    child: Text(
                      "${value.toStringAsFixed(1)}$unit",
                      style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 8),
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
                dashArray: const [4, 4],
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

  /// Construiește butoanele de quick actions
  Widget _buildQuickActionsRow() {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _buildQuickActionButton("Cum e temperatura?", Icons.thermostat_rounded),
          _buildQuickActionButton("Grafic ultimele 3 ore", Icons.analytics_rounded),
          _buildQuickActionButton("Aprinde becul", Icons.lightbulb_outline_rounded),
          _buildQuickActionButton("Stinge becul", Icons.lightbulb_rounded),
          _buildQuickActionButton("Stare priză & putere", Icons.power_rounded),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(String text, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: ActionChip(
        avatar: Icon(icon, color: Colors.indigo[700], size: 14),
        label: Text(
          text,
          style: TextStyle(color: Colors.indigo[800], fontWeight: FontWeight.w600, fontSize: 12),
        ),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.indigo[50]!, width: 1),
        ),
        elevation: 1,
        onPressed: () {
          _chatService.sendMessage(text);
          _scrollToBottom();
        },
      ),
    );
  }

  /// Input bar-ul cu camp text si buton de send
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _messageController,
                onSubmitted: (_) => _sendMessage(),
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                decoration: const InputDecoration(
                  hintText: "Scrie un mesaj...",
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.teal[500],
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

/// Typing Indicator animat cu micro-animatii native de pulsare
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({Key? key}) : super(key: key);

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final animValue = ((_controller.value - delay) % 1.0);
            final scale = 1.0 + (0.4 * (1.0 - (animValue - 0.5).abs() * 2));
            final opacity = 0.4 + (0.6 * (1.0 - (animValue - 0.5).abs() * 2));
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(opacity.clamp(0.1, 1.0)),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.identity()..scale(scale.clamp(0.8, 1.5)),
            );
          },
        );
      }),
    );
  }
}
