import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:5000';

  /// Récupère la liste de toutes les simulations
  static Future<List<dynamic>> fetchSimulations() async {
    final response = await http.get(Uri.parse('$baseUrl/api/simulations'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Impossible de récupérer la liste des simulations');
  }

  /// Crée une nouvelle simulation
  static Future<String> createSimulation() async {
    final response = await http.post(Uri.parse('$baseUrl/api/simulations'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['sim_id'] as String;
    }
    throw Exception('Impossible de créer une nouvelle simulation');
  }

  /// Récupère l'état actuel d'une simulation
  static Future<Map<String, dynamic>> fetchGameState(String simId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/simulations/$simId/state'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Impossible de récupérer l\'état de la simulation');
  }

  /// Démarre la simulation
  static Future<bool> startSimulation(String simId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/simulations/$simId/start'));
    return response.statusCode == 200;
  }

  /// Arrête la simulation
  static Future<bool> stopSimulation(String simId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/simulations/$simId/stop'));
    return response.statusCode == 200;
  }

  /// Récupère la liste de tous les composants
  static Future<List<dynamic>> fetchComponents() async {
    final response = await http.get(Uri.parse('$baseUrl/api/components'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Impossible de récupérer la liste des composants');
  }

  /// Place une entité sur la grille
  static Future<http.Response> addComponent(String simId, String typeId, int x, int y) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/simulations/$simId/components'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "type_id": typeId,
        "x": x,
        "y": y,
      }),
    );
    return response;
  }

  /// Retire l'entité de la grille à des coordonnées spécifiques (via DELETE)
  static Future<bool> removeComponent(String simId, int x, int y) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/simulations/$simId/components?x=$x&y=$y'),
    );
    return response.statusCode == 200;
  }

  /// Envoie un composant créé via le Component Maker
  static Future<http.Response> buildComponent({
    required String name,
    required String description,
    required int vitesse,
    required String logicPy,
    required String interactionsJson,
    required String forme,
    required String coin,
    required String orientation,
    required String couleur,
    required Uint8List iconBytes,
    required String iconFilename,
  }) async {
    final uri = Uri.parse('$baseUrl/api/components/build');
    final request = http.MultipartRequest('POST', uri);

    request.fields['name'] = name;
    request.fields['description'] = description;
    request.fields['atb_vitesse'] = vitesse.toString();
    request.fields['logic_py'] = logicPy;
    request.fields['interactions'] = interactionsJson;
    request.fields['forme'] = forme;
    request.fields['coin'] = coin;
    request.fields['orientation'] = orientation;
    request.fields['couleur'] = couleur;

    request.files.add(
      http.MultipartFile.fromBytes(
        'icon',
        iconBytes,
        filename: iconFilename,
      ),
    );

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  /// Envoie/importe un fichier .sssub manuellement
  static Future<http.Response> uploadComponent(Uint8List fileBytes, String filename) async {
    final uri = Uri.parse('$baseUrl/api/components/upload');
    final request = http.MultipartRequest('POST', uri);

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ),
    );

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  /// Récupère le dossier de travail configuré
  static Future<String> getSettings() async {
    final response = await http.get(Uri.parse('$baseUrl/api/settings'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['data_dir'] as String;
    }
    throw Exception('Impossible de charger les paramètres');
  }

  /// Met à jour le dossier de travail configuré
  static Future<String> updateSettings(String dataDir) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/settings'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"data_dir": dataDir}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['data_dir'] as String;
    } else {
      final errorMsg = json.decode(response.body)['detail'] ?? 'Erreur';
      throw Exception(errorMsg);
    }
  }
}
