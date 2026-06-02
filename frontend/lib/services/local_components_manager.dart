import 'dart:io' as io;
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'client_settings.dart';

class LocalComponent {
  final String id;
  final String name;
  final String description;
  final int vitesse;
  final String forme;
  final String coin;
  final String orientation;
  final String couleur;
  final Map<String, dynamic> interactions;
  final bool hasIconM;
  final bool hasIconF;
  
  final Uint8List iconBytes;
  final Uint8List? iconMBytes;
  final Uint8List? iconFBytes;
  
  final String logicPy;
  final String path;

  LocalComponent({
    required this.id,
    required this.name,
    required this.description,
    required this.vitesse,
    required this.forme,
    required this.coin,
    required this.orientation,
    required this.couleur,
    required this.interactions,
    required this.hasIconM,
    required this.hasIconF,
    required this.iconBytes,
    this.iconMBytes,
    this.iconFBytes,
    required this.logicPy,
    required this.path,
  });

  Map<String, dynamic> toMetadata() {
    return {
      "id": id,
      "name": name,
      "description": description,
      "atb_vitesse": vitesse,
      "is_builtin": false,
      "forme": forme,
      "coin": coin,
      "orientation": orientation,
      "couleur": couleur,
      "interactions": interactions,
      "has_icon_m": hasIconM,
      "has_icon_f": hasIconF,
    };
  }
}

class LocalComponentsManager {
  static final List<LocalComponent> _cachedComponents = [];
  static final Map<String, DateTime> _lastModifiedCache = {};

  static List<LocalComponent> get cachedComponents => _cachedComponents;

  /// Scanne le dossier de travail local, extrait et charge les métadonnées et icônes de tous les .sssub.
  static Future<List<LocalComponent>> scanLocalComponents() async {
    if (kIsWeb) {
      // Sur le Web, pas d'accès direct au disque. On utilise le cache en mémoire.
      return _cachedComponents;
    }
    
    final workspacePath = await ClientSettings.getWorkspacePath();
    final dir = io.Directory(workspacePath);
    if (!await dir.exists()) {
      _cachedComponents.clear();
      _lastModifiedCache.clear();
      return [];
    }

    try {
      final List<io.FileSystemEntity> entities = dir.listSync();
      final List<String> currentIds = [];

      for (final entity in entities) {
        if (entity is io.File && entity.path.endsWith('.sssub')) {
          try {
            final lastMod = await entity.lastModified();
            final filePath = entity.path;
            
            // Vérifier si le composant est déjà dans le cache avec la même date de modification
            final cachedIndex = _cachedComponents.indexWhere((c) => c.path == filePath);
            if (cachedIndex != -1 && _lastModifiedCache[filePath] == lastMod) {
              currentIds.add(_cachedComponents[cachedIndex].id);
              continue;
            }

            final component = await loadFromSssubFile(entity);
            if (component != null) {
              _lastModifiedCache[filePath] = lastMod;
              currentIds.add(component.id);
              if (cachedIndex != -1) {
                // Remplacer en place pour garder l'ordre mais mettre à jour les données
                _cachedComponents[cachedIndex] = component;
              } else {
                _cachedComponents.add(component);
              }
            }
          } catch (e) {
            debugPrint("Erreur de chargement du composant local ${entity.path} : $e");
          }
        }
      }

      // Supprimer du cache les composants qui ne sont plus sur le disque
      _cachedComponents.removeWhere((c) {
        final keep = currentIds.contains(c.id);
        if (!keep) {
          _lastModifiedCache.remove(c.path);
        }
        return !keep;
      });

    } catch (e) {
      debugPrint("Erreur lors du scan du dossier local : $e");
    }
    return _cachedComponents;
  }

  /// Permet d'ajouter manuellement un composant en mémoire (utile sur le Web).
  static void addWebComponent(LocalComponent component) {
    _cachedComponents.removeWhere((c) => c.id == component.id);
    _cachedComponents.add(component);
  }

  /// Charge un composant à partir d'un fichier .sssub.
  static Future<LocalComponent?> loadFromSssubFile(io.File file) async {
    final bytes = await file.readAsBytes();
    final filename = file.path.split(RegExp(r'[/\\]')).last;
    return loadFromSssubBytes(bytes, filename, file.path);
  }

  /// Décode les octets d'une archive .sssub et renvoie un LocalComponent.
  static Future<LocalComponent?> loadFromSssubBytes(Uint8List bytes, String filename, String filepath) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    
    Map<String, dynamic>? manifest;
    Uint8List? iconBytes;
    Uint8List? iconMBytes;
    Uint8List? iconFBytes;
    String? logicPy;

    for (final archiveFile in archive) {
      if (archiveFile.name == 'manifest.json') {
        final content = utf8.decode(archiveFile.content as List<int>);
        manifest = json.decode(content) as Map<String, dynamic>;
      } else if (archiveFile.name == 'icon.png') {
        iconBytes = Uint8List.fromList(archiveFile.content as List<int>);
      } else if (archiveFile.name == 'icon_M.png') {
        iconMBytes = Uint8List.fromList(archiveFile.content as List<int>);
      } else if (archiveFile.name == 'icon_F.png') {
        iconFBytes = Uint8List.fromList(archiveFile.content as List<int>);
      } else if (archiveFile.name == 'logic.py') {
        logicPy = utf8.decode(archiveFile.content as List<int>, allowMalformed: true);
      }
    }

    if (manifest == null || iconBytes == null || logicPy == null) {
      return null;
    }

    final id = manifest['id'] ?? filename.replaceAll('.sssub', '');
    
    return LocalComponent(
      id: id,
      name: manifest['name'] ?? id,
      description: manifest['description'] ?? '',
      vitesse: manifest['atb_vitesse'] ?? 10,
      forme: manifest['forme'] ?? 'carré',
      coin: manifest['coin'] ?? 'droit',
      orientation: manifest['orientation'] ?? 'standard',
      couleur: manifest['couleur'] ?? '#000000',
      interactions: Map<String, dynamic>.from(manifest['interactions'] ?? {}),
      hasIconM: iconMBytes != null,
      hasIconF: iconFBytes != null,
      iconBytes: iconBytes,
      iconMBytes: iconMBytes,
      iconFBytes: iconFBytes,
      logicPy: logicPy,
      path: filepath,
    );
  }
}
