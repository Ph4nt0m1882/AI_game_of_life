import 'dart:io' as io;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

class ClientSettings {
  static String? _localWorkspacePath;
  static String? _geminiApiKey;
  static String _webGeminiApiKey = '';

  /// Récupère le chemin du dossier de travail local.
  static Future<String> getWorkspacePath() async {
    if (kIsWeb) {
      return 'web_workspace';
    }
    if (_localWorkspacePath != null) {
      return _localWorkspacePath!;
    }
    try {
      final file = io.File('client_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        _localWorkspacePath = data['workspace_path'] as String?;
      }
    } catch (e) {
      // Ignorer
    }
    if (_localWorkspacePath == null || _localWorkspacePath!.isEmpty) {
      // Valeur par défaut dans le répertoire de l'application
      _localWorkspacePath = io.Directory('custom_components').absolute.path;
    }
    // S'assurer que le répertoire existe
    final dir = io.Directory(_localWorkspacePath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _localWorkspacePath!;
  }

  /// Enregistre le chemin du dossier de travail local.
  static Future<void> setWorkspacePath(String path) async {
    if (kIsWeb) return;
    _localWorkspacePath = path;
    try {
      final file = io.File('client_settings.json');
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = Map<String, dynamic>.from(json.decode(content));
      }
      data['workspace_path'] = path;
      await file.writeAsString(json.encode(data));
    } catch (e) {
      // Ignorer
    }
  }

  /// Récupère la clé API Gemini.
  static Future<String> getGeminiApiKey() async {
    if (kIsWeb) {
      return _webGeminiApiKey;
    }
    if (_geminiApiKey != null) {
      return _geminiApiKey!;
    }
    try {
      final file = io.File('client_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        _geminiApiKey = data['gemini_api_key'] as String?;
      }
    } catch (e) {
      // Ignorer
    }
    return _geminiApiKey ?? '';
  }

  static String? _serverAddress;

  /// Récupère l'adresse du serveur.
  static Future<String> getServerAddress() async {
    if (kIsWeb) {
      return 'http://127.0.0.1:5000';
    }
    if (_serverAddress != null) {
      return _serverAddress!;
    }
    try {
      final file = io.File('client_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        _serverAddress = data['server_address'] as String?;
      }
    } catch (e) {
      // Ignorer
    }
    if (_serverAddress == null || _serverAddress!.isEmpty) {
      _serverAddress = 'http://127.0.0.1:5000';
    }
    return _serverAddress!;
  }

  /// Enregistre l'adresse du serveur.
  static Future<void> setServerAddress(String address) async {
    if (kIsWeb) return;
    _serverAddress = address;
    try {
      final file = io.File('client_settings.json');
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = Map<String, dynamic>.from(json.decode(content));
      }
      data['server_address'] = address;
      await file.writeAsString(json.encode(data));
    } catch (e) {
      // Ignorer
    }
  }

  /// Enregistre la clé API Gemini.
  static Future<void> setGeminiApiKey(String apiKey) async {
    if (kIsWeb) {
      _webGeminiApiKey = apiKey;
      return;
    }
    _geminiApiKey = apiKey;
    try {
      final file = io.File('client_settings.json');
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = Map<String, dynamic>.from(json.decode(content));
      }
      data['gemini_api_key'] = apiKey;
      await file.writeAsString(json.encode(data));
    } catch (e) {
      // Ignorer
    }
  }
}
