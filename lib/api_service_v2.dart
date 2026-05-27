import 'dart:convert';
import 'package:http/http.dart' as http;

/// ApiServiceV2 - Gestioneaza toate cererile HTTP catre serverul Flask.
/// Centralizeaza adresa IP si logica de timeout.
class ApiServiceV2 {
  final String serverIP;
  final int port;

  ApiServiceV2({required this.serverIP, this.port = 5000});

  String get _baseUrl => 'http://$serverIP:$port';

  /// Metoda generica pentru fetch istoric. 
  /// Include Error Handling pentru cazurile in care serverul Flask nu raspunde.
  Future<List<dynamic>> fetchHistory() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/istoric'))
          .timeout(const Duration(seconds: 5)); // Prevenim blocarea UI-ului la infinit

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Aruncam exceptii specifice pentru a putea fi tratate in UI
        throw Exception('Serverul a returnat cod de eroare: ${response.statusCode}');
      }
    } catch (e) {
      print('[API_SERVICE] Eroare la fetchHistory: $e');
      rethrow; // Repropagam eroarea catre cel care apeleaza metoda
    }
  }
}
