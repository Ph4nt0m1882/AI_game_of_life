import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiClient {
  static String baseUrl = 'http://127.0.0.1:5000';

  /// Récupère la liste de toutes les simulations
  static Future<List<dynamic>> fetchSimulations() async {
    final response = await http.get(Uri.parse('$baseUrl/api/simulations'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Impossible de récupérer la liste des simulations');
  }

  /// Crée une nouvelle simulation avec une taille personnalisée
  static Future<String> createSimulation({int width = 80, int height = 80}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/simulations?width=$width&height=$height'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['sim_id'] as String;
    }
    throw Exception('Impossible de créer une nouvelle simulation');
  }

  /// Récupère l'état actuel d'une simulation (avec option d'exclure la grille)
  static Future<Map<String, dynamic>> fetchGameState(String simId, {bool excludeGrid = false}) async {
    final response = await http.get(Uri.parse('$baseUrl/api/simulations/$simId/state?exclude_grid=$excludeGrid'));
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
    Uint8List? iconBytes,
    String? iconFilename,
    Uint8List? iconMBytes,
    String? iconMFilename,
    Uint8List? iconFBytes,
    String? iconFFilename,
    String? compId,
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
    if (compId != null) {
      request.fields['comp_id'] = compId;
    }

    if (iconBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'icon',
          iconBytes,
          filename: iconFilename ?? 'icon.png',
        ),
      );
    }

    if (iconMBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'icon_m',
          iconMBytes,
          filename: iconMFilename ?? 'icon_M.png',
        ),
      );
    }

    if (iconFBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'icon_f',
          iconFBytes,
          filename: iconFFilename ?? 'icon_F.png',
        ),
      );
    }

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

  /// Modifie une cellule de la grille (0: eau, 1: terre)
  static Future<bool> paintMapCell(String simId, int x, int y, int value, {int brushSize = 1}) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/simulations/$simId/map'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"x": x, "y": y, "value": value, "brush_size": brushSize}),
    );
    return response.statusCode == 200;
  }

  /// Régénère la carte selon l'algorithme choisi
  static Future<http.Response> generateMap(String simId, String algorithm, {String pythonCode = ""}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/simulations/$simId/generate_map'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "algorithm": algorithm,
        "python_code": pythonCode,
      }),
    );
    return response;
  }

  /// Met à jour les règles de simulation (ex: noyade active)
  static Future<bool> updateSimulationSettings(String simId, {required bool noyadeActive, required double speedFactor, String? geminiApiKey}) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/simulations/$simId/settings'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "noyade_active": noyadeActive,
        "speed_factor": speedFactor,
        "gemini_api_key": geminiApiKey ?? "",
      }),
    );
    return response.statusCode == 200;
  }

  /// Met à jour une statistique d'un composant en mode debug
  static Future<bool> updateComponentStat(String simId, String compId, String key, dynamic value) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/simulations/$simId/components/stats'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "comp_id": compId,
        "key": key,
        "value": value,
      }),
    );
    return response.statusCode == 200;
  }
}
