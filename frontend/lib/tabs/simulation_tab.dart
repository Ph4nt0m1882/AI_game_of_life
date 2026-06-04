import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../services/client_settings.dart';
import '../services/local_components_manager.dart';
import 'package:flutter/services.dart';
import '../widgets/island_painter.dart';

class SimulationTab extends StatefulWidget {
  const SimulationTab({super.key});

  @override
  State<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  List<dynamic> _simulations = [];
  List<dynamic> _components = [];
  final Set<String> _uploadedCustomComponentIds = {};
  String? _selectedSimId;
  String? _selectedComponentId;
  String _activeTool = 'place'; // 'place', 'remove', 'paint_land', 'paint_water'
  int _brushSize = 1; // Taille du pinceau (1 = 1x1, 2 = rayon 1, etc.)
  bool _noyadeActive = true;
  double _speedFactor = 1.0;
  Timer? _pollingTimer;
  Timer? _listTimer;
  Map<String, dynamic>? _gameState;
  bool _isRunning = false;
  String _geminiApiKey = '';
  
  // États pour le volet de statistiques
  bool _showStatsPanel = false;
  String? _selectedStatsComponentId;
  Map<String, dynamic>? _cachedComponentStats;
  bool _selectedComponentAlive = true;
  bool _debugMode = false;
  bool _connectionError = false;
  final TextEditingController _serverController = TextEditingController();

  final Map<String, ui.Image> _iconCache = {};
  ui.Image? _bubbleImage;

  Future<void> _loadIconToCache(String typeName, String url) async {
    if (_iconCache.containsKey(typeName)) return;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _iconCache[typeName] = frame.image;
          });
        }
      }
    } catch (e) {
      // Ignorer
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGeminiApiKey();
    _loadBubbleImage();
    _loadServerAddress();
    
    // Polling régulier de l'état du monde (avec exclusion dynamique de la grille pour le gain de performance)
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_selectedSimId != null && !_connectionError) {
        _fetchGameState(excludeGrid: _gameState != null);
      }
    });

    // Polling des mondes et des composants disponibles
    _listTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_connectionError) {
        _fetchSimulations();
        _fetchComponents();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _listTimer?.cancel();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _loadGeminiApiKey() async {
    try {
      final apiKey = await ClientSettings.getGeminiApiKey();
      if (mounted) {
        setState(() {
          _geminiApiKey = apiKey;
        });
      }
      if (_selectedSimId != null && apiKey.isNotEmpty) {
        await ApiClient.updateSimulationSettings(
          _selectedSimId!,
          noyadeActive: _noyadeActive,
          speedFactor: _speedFactor,
          geminiApiKey: apiKey,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadServerAddress() async {
    try {
      final savedAddress = await ClientSettings.getServerAddress();
      ApiClient.baseUrl = savedAddress;
      _serverController.text = _getCleanHost(savedAddress);
      _fetchSimulations();
      _fetchComponents();
    } catch (_) {}
  }

  String _getCleanHost(String url) {
    String hostOnly = url.replaceAll('http://', '').replaceAll('https://', '');
    if (hostOnly.contains(':')) {
      hostOnly = hostOnly.split(':').first;
    }
    bool isDomain = RegExp(r'[a-zA-Z]').hasMatch(hostOnly) && hostOnly.toLowerCase() != 'localhost';
    if (isDomain) {
      if (url.endsWith(':5000')) {
        return url.substring(0, url.length - 5);
      }
      return url;
    }
    String host = url.replaceAll('http://', '').replaceAll('https://', '');
    if (host.contains(':5000')) {
      host = host.replaceAll(':5000', '');
    }
    return host;
  }

  String _formatAndValidateUrl(String input) {
    String text = input.trim();
    if (text.isEmpty) return ApiClient.baseUrl;

    String scheme = '';
    if (text.startsWith('http://')) {
      scheme = 'http://';
      text = text.substring(7);
    } else if (text.startsWith('https://')) {
      scheme = 'https://';
      text = text.substring(8);
    } else {
      String checkHost = text;
      if (checkHost.contains(':')) {
        checkHost = checkHost.split(':').first;
      }
      bool isDomain = RegExp(r'[a-zA-Z]').hasMatch(checkHost) && checkHost.toLowerCase() != 'localhost';
      if (isDomain) {
        scheme = 'https://';
      } else {
        scheme = 'http://';
      }
    }

    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }

    // Strip :5000 if it is a domain
    if (text.endsWith(':5000')) {
      String hostPart = text.substring(0, text.length - 5);
      bool isDomain = RegExp(r'[a-zA-Z]').hasMatch(hostPart) && hostPart.toLowerCase() != 'localhost';
      if (isDomain) {
        text = hostPart;
      }
    }

    if (text.contains(':')) {
      return '$scheme$text';
    }

    bool isDomain = RegExp(r'[a-zA-Z]').hasMatch(text) && text.toLowerCase() != 'localhost';
    if (isDomain) {
      return '$scheme$text';
    } else {
      return '$scheme$text:5000';
    }
  }

  Future<void> _updateServerAddress(String newUrl) async {
    setState(() {
      ApiClient.baseUrl = newUrl;
      _connectionError = false;
      _gameState = null;
      _serverController.text = _getCleanHost(newUrl);
    });
    await ClientSettings.setServerAddress(newUrl);
    _fetchSimulations();
    _fetchComponents();
  }

  Future<void> _showServerAddressConfigDialog() async {
    final controller = TextEditingController(text: _getCleanHost(ApiClient.baseUrl));

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.settings_ethernet, color: Color(0xFF00F0FF)),
              SizedBox(width: 8),
              Text(
                'Adresse du Serveur',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Trebuchet MS',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Saisissez l\'adresse IP ou le nom d\'hôte du serveur Python (le port 5000 sera configuré automatiquement).',
                  style: TextStyle(color: Color(0xFFC8C8D2), fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Adresse IP / Hôte',
                    labelStyle: TextStyle(color: Color(0xFF00F0FF)),
                    hintText: 'ex: 192.168.1.50 ou 127.0.0.1',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF00F0FF)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Adresse actuelle : ${ApiClient.baseUrl}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F0FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final ip = controller.text.trim();
                if (ip.isNotEmpty) {
                  final formatted = _formatAndValidateUrl(ip);
                  _updateServerAddress(formatted);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Valider', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadBubbleImage() async {
    try {
      final data = await rootBundle.load('assets/bubble.png');
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _bubbleImage = frame.image;
        });
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _fetchSimulations() async {
    try {
      final fetchedSims = await ApiClient.fetchSimulations();
      if (mounted) {
        setState(() {
          _connectionError = false;
          _simulations = fetchedSims;
          
          final exists = _simulations.any((s) => s['id'] == _selectedSimId);
          if (!exists) {
            _selectedSimId = null;
            _uploadedCustomComponentIds.clear();
          }
          
          if (_selectedSimId == null && _simulations.isNotEmpty) {
            _selectedSimId = _simulations.first['id'];
            _isRunning = _simulations.first['is_running'];
          }

          if (_selectedSimId != null) {
            final activeSim = _simulations.firstWhere((s) => s['id'] == _selectedSimId, orElse: () => null);
            if (activeSim != null) {
              _speedFactor = (activeSim['speed_factor'] ?? 1.0).toDouble();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionError = true;
          _simulations = [];
          _selectedSimId = null;
        });
      }
    }
  }

  LocalComponent? _getLocalComponent(String id) {
    try {
      return LocalComponentsManager.cachedComponents.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> _importLocalSssub() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sssub'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        try {
          bytes = await io.File(file.path!).readAsBytes();
        } catch (e) {
          // Ignorer
        }
      }
      if (bytes == null) return;

      try {
        final localComp = await LocalComponentsManager.loadFromSssubBytes(bytes, file.name, file.path ?? file.name);
        if (localComp == null) {
          throw Exception("Impossible de décoder le composant .sssub.");
        }

        if (kIsWeb) {
          LocalComponentsManager.addWebComponent(localComp);
        } else {
          final workspacePath = await ClientSettings.getWorkspacePath();
          final targetFile = io.File('$workspacePath/${localComp.id}.sssub');
          await targetFile.writeAsBytes(bytes);
        }

        await _fetchComponents();
        
        setState(() {
          _selectedComponentId = localComp.id;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Composant "${localComp.name}" importé avec succès !'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur d\'importation : $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _fetchComponents() async {
    try {
      final localComps = await LocalComponentsManager.scanLocalComponents();
      final List<dynamic> localMeta = localComps.map((c) => c.toMetadata()).toList();

      List<dynamic> serverComps = [];
      try {
        serverComps = await ApiClient.fetchComponents();
      } catch (e) {
        // Ignorer
      }

      final Map<String, dynamic> merged = {};
      for (var c in serverComps) {
        if (c['is_builtin'] == true) {
          merged[c['id']] = c;
        }
      }
      for (var c in localMeta) {
        merged[c['id']] = c;
      }

      final mergedList = merged.values.toList();

      setState(() {
        _components = mergedList;
        if (_selectedComponentId == null || !_components.any((c) => c['id'] == _selectedComponentId)) {
          _selectedComponentId = _components.isNotEmpty ? _components.first['id'] : null;
        }
      });
      
      for (var c in serverComps) {
        if (c['is_builtin'] == true && c['id'] != null && c['icon_url'] != null) {
          _loadIconToCache(c['name'], '${ApiClient.baseUrl}${c['icon_url']}');
        }
      }
    } catch (e) {
      // Ignorer
    }
  }

  bool _isFetchingState = false;

  Future<void> _fetchGameState({bool excludeGrid = false}) async {
    if (_selectedSimId == null || _isFetchingState) return;
    _isFetchingState = true;
    try {
      final state = await ApiClient.fetchGameState(_selectedSimId!, excludeGrid: excludeGrid);
      if (mounted) {
        setState(() {
          if (excludeGrid && _gameState != null && _gameState!['grille'] != null) {
            state['grille'] = _gameState!['grille'];
          }
          _gameState = state;
          _noyadeActive = state['noyade_active'] ?? true;
          
          if (_selectedStatsComponentId != null) {
            final List<dynamic> comps = state['composants'] ?? [];
            final selected = comps.firstWhere(
              (c) => c['id'] == _selectedStatsComponentId,
              orElse: () => null,
            );
            if (selected != null) {
              _cachedComponentStats = selected;
              _selectedComponentAlive = selected['vivant'] ?? true;
            } else {
              _selectedComponentAlive = false;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionError = true;
          _selectedSimId = null;
          _gameState = null;
        });
      }
    } finally {
      _isFetchingState = false;
    }
  }

  Future<void> _createNewSim({int width = 80, int height = 80}) async {
    try {
      final simId = await ApiClient.createSimulation(width: width, height: height);
      setState(() {
        _selectedSimId = simId;
        _isRunning = false;
        _gameState = null;
      });
      _fetchSimulations();
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _showCreateWorldDialog() async {
    int width = 80;
    int height = 80;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.public, color: Color(0xFF00F0FF)),
                  SizedBox(width: 8),
                  Text(
                    'Créer un Monde',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Trebuchet MS',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Choisissez la taille de la grille (lignes et colonnes) pour votre simulation.',
                      style: TextStyle(color: Color(0xFFC8C8D2), fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Largeur :', style: TextStyle(color: Colors.white, fontSize: 13)),
                        Text(
                          '$width',
                          style: const TextStyle(
                            color: Color(0xFF00F0FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: width.toDouble(),
                      min: 30,
                      max: 200,
                      divisions: 17, // Pas de 10
                      activeColor: const Color(0xFF00F0FF),
                      inactiveColor: Colors.grey[800],
                      onChanged: (val) {
                        setDialogState(() {
                          width = val.round();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Hauteur :', style: TextStyle(color: Colors.white, fontSize: 13)),
                        Text(
                          '$height',
                          style: const TextStyle(
                            color: Color(0xFF00F0FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: height.toDouble(),
                      min: 30,
                      max: 200,
                      divisions: 17, // Pas de 10
                      activeColor: const Color(0xFF00F0FF),
                      inactiveColor: Colors.grey[800],
                      onChanged: (val) {
                        setDialogState(() {
                          height = val.round();
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F0FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _createNewSim(width: width, height: height);
                  },
                  child: const Text('Créer', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleSim(bool start) async {
    if (_selectedSimId == null) return;
    try {
      if (start) {
        await ApiClient.updateSimulationSettings(
          _selectedSimId!,
          noyadeActive: _noyadeActive,
          speedFactor: _speedFactor,
          geminiApiKey: _geminiApiKey,
        );
      }
      final success = start 
          ? await ApiClient.startSimulation(_selectedSimId!)
          : await ApiClient.stopSimulation(_selectedSimId!);
      if (success) {
        setState(() {
          _isRunning = start;
        });
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _toggleNoyade(bool value) async {
    if (_selectedSimId == null) return;
    try {
      final success = await ApiClient.updateSimulationSettings(_selectedSimId!, noyadeActive: value, speedFactor: _speedFactor, geminiApiKey: _geminiApiKey);
      if (success) {
        setState(() {
          _noyadeActive = value;
          if (!_noyadeActive && (_activeTool == 'paint_land' || _activeTool == 'paint_water')) {
            _activeTool = 'place';
          }
        });
        _fetchGameState();
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _updateSpeedFactor(double value) async {
    if (_selectedSimId == null) return;
    try {
      final success = await ApiClient.updateSimulationSettings(_selectedSimId!, noyadeActive: _noyadeActive, speedFactor: value, geminiApiKey: _geminiApiKey);
      if (success) {
        setState(() {
          _speedFactor = value;
        });
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _paintCell(int x, int y, int value) async {
    if (_selectedSimId == null) return;
    try {
      final success = await ApiClient.paintMapCell(_selectedSimId!, x, y, value, brushSize: _brushSize);
      if (success) {
        setState(() {
          if (_gameState != null && _gameState!['grille'] != null) {
            if (_brushSize <= 1) {
              _gameState!['grille'][y][x] = value;
            } else {
              final int width = _gameState!['width'] ?? 80;
              final int height = _gameState!['height'] ?? 80;
              final int radius = _brushSize - 1;
              for (int dy = -radius; dy <= radius; dy++) {
                for (int dx = -radius; dx <= radius; dx++) {
                  if (dx * dx + dy * dy <= radius * radius) {
                    final int px = x + dx;
                    final int py = y + dy;
                    if (px >= 0 && px < width && py >= 0 && py < height) {
                      _gameState!['grille'][py][px] = value;
                    }
                  }
                }
              }
            }
          }
        });
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<bool> _ensureComponentUploaded(LocalComponent localComp) async {
    if (_uploadedCustomComponentIds.contains(localComp.id)) {
      return true;
    }
    
    final sssubFile = io.File(localComp.path);
    if (!await sssubFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le fichier .sssub local est introuvable.'), backgroundColor: Colors.red),
        );
      }
      return false;
    }

    // Afficher la boîte de dialogue de chargement
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return PopScope(
            canPop: false, // Empêcher l'utilisateur de fermer la boîte de dialogue avec le bouton Retour
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E).withValues(alpha: 0.95), // Sleek dark card background
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.tealAccent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Loading animation stack with a nice glowing effect
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                              strokeWidth: 4,
                            ),
                          ),
                          const Icon(
                            Icons.cloud_upload_rounded,
                            color: Colors.tealAccent,
                            size: 28,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Initialisation de l\'entité',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Téléversement de "${localComp.name}" vers le serveur...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
      // Donner une fraction de seconde à Flutter pour afficher le dialogue avant le travail lourd
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      final sssubBytes = await sssubFile.readAsBytes();
      final uploadResponse = await ApiClient.uploadComponent(
        sssubBytes,
        sssubFile.path.split(io.Platform.pathSeparator).last,
      );

      // Fermer la boîte de dialogue de chargement
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (uploadResponse.statusCode == 200) {
        _uploadedCustomComponentIds.add(localComp.id);
        return true;
      } else {
        final errorMsg = json.decode(uploadResponse.body)['detail'] ?? 'Erreur lors du téléversement du composant';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg), backgroundColor: Colors.orange),
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur réseau lors de l\'upload : $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  Future<void> _handleCellTap(int x, int y) async {
    if (_selectedSimId == null) return;
    
    if (_activeTool == 'pan') {
      if (_gameState != null && _gameState!['composants'] != null) {
        final List<dynamic> comps = _gameState!['composants'];
        final clicked = comps.firstWhere(
          (c) => c['x'] == x && c['y'] == y,
          orElse: () => null,
        );
        setState(() {
          if (clicked != null) {
            _selectedStatsComponentId = clicked['id'];
            _cachedComponentStats = clicked;
            _selectedComponentAlive = clicked['vivant'] ?? true;
            _showStatsPanel = true;
          } else {
            _selectedStatsComponentId = null;
            _cachedComponentStats = null;
            _selectedComponentAlive = true;
          }
        });
      }
    } else if (_activeTool == 'place') {
      if (_selectedComponentId == null) return;
      try {
        final localComp = _getLocalComponent(_selectedComponentId!);
        if (localComp != null) {
          final ok = await _ensureComponentUploaded(localComp);
          if (!ok) return;
        }

        var response = await ApiClient.addComponent(_selectedSimId!, _selectedComponentId!, x, y);
        if (response.statusCode != 200) {
          final errorMsg = json.decode(response.body)['detail'] ?? '';
          if (errorMsg.contains('inconnu') || errorMsg.contains('impossible à charger') || errorMsg.contains("n'existe pas")) {
            // Le serveur a perdu le composant (par ex. suite à un redémarrage). On le ré-upload à la volée.
            _uploadedCustomComponentIds.remove(_selectedComponentId);
            if (localComp != null) {
              final ok = await _ensureComponentUploaded(localComp);
              if (ok) {
                // Deuxième tentative d'ajout après ré-upload réussi
                response = await ApiClient.addComponent(_selectedSimId!, _selectedComponentId!, x, y);
              }
            }
          }
        }

        if (response.statusCode == 200) {
          _fetchGameState();
        } else {
          final errorMsg = json.decode(response.body)['detail'] ?? 'Erreur';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMsg), backgroundColor: Colors.orange),
            );
          }
        }
      } catch (e) {
        // Ignorer
      }
    } else if (_activeTool == 'remove') {
      try {
        final success = await ApiClient.removeComponent(_selectedSimId!, x, y);
        if (success) {
          _fetchGameState();
        }
      } catch (e) {
        // Ignorer
      }
    } else if (_activeTool == 'paint_land') {
      _paintCell(x, y, 1);
    } else if (_activeTool == 'paint_water') {
      _paintCell(x, y, 0);
    }
  }

  void _handleCellPaint(int x, int y) {
    if (_activeTool == 'paint_land') {
      _paintCell(x, y, 1);
    } else if (_activeTool == 'paint_water') {
      _paintCell(x, y, 0);
    }
  }

  void _showGenerateMapDialog() {
    if (_selectedSimId == null) return;
    String selectedAlgo = 'circular';
    final codeController = TextEditingController(text: '''# Script Python de génération
# Doit contenir la fonction generer_grille(width, height)
# retournant une matrice 2D de 0 (eau) et 1 (terre).

def generer_grille(width, height):
    grid = [[0] * width for _ in range(height)]
    
    # Exemple : Labyrinthe ou quadrillage
    for y in range(height):
        for x in range(width):
            if (x * y) % 6 == 0 or (x + y) % 9 == 0:
                grid[y][x] = 1
                
    return grid
''');
    String dialogError = '';
    bool isGenerating = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Générer une Nouvelle Carte'),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Algorithme de Génération',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedAlgo,
                            isExpanded: true,
                            isDense: true,
                            items: const [
                              DropdownMenuItem(value: 'circular', child: Text('Île circulaire simple')),
                              DropdownMenuItem(value: 'organique', child: Text('Île organique (Automate cellulaire)')),
                              DropdownMenuItem(value: 'custom', child: Text('Script Python personnalisé')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  selectedAlgo = val;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      if (selectedAlgo == 'custom') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Script Python',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 300,
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade800),
                          ),
                          child: TextField(
                            controller: codeController,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.greenAccent,
                            ),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.all(12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                      if (dialogError.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0x802D0A0A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            dialogError,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isGenerating ? null : () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: isGenerating
                      ? null
                      : () async {
                          setDialogState(() {
                            isGenerating = true;
                            dialogError = '';
                          });
                          try {
                            final response = await ApiClient.generateMap(
                              _selectedSimId!,
                              selectedAlgo,
                              pythonCode: selectedAlgo == 'custom' ? codeController.text : '',
                            );
                            if (response.statusCode == 200) {
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Carte générée avec succès !'), backgroundColor: Colors.green),
                                );
                              }
                              _fetchGameState();
                            } else {
                              final err = json.decode(response.body)['detail'] ?? 'Erreur';
                              setDialogState(() {
                                dialogError = err.toString();
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              dialogError = 'Erreur réseau : $e';
                            });
                          } finally {
                            setDialogState(() {
                              isGenerating = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  child: isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Générer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panneau de contrôle gauche
          SizedBox(
            width: 320,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Monde Simulation',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Monde Actif',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedSimId,
                                isExpanded: true,
                                isDense: true,
                                items: _simulations.map<DropdownMenuItem<String>>((dynamic sim) {
                                  return DropdownMenuItem<String>(
                                    value: sim['id'],
                                    child: Text('Monde: ${sim['id']}'),
                                  );
                                }).toList(),
                                onChanged: (String? val) {
                                  setState(() {
                                    _selectedSimId = val;
                                    _gameState = null;
                                    if (val != null) {
                                      final selected = _simulations.firstWhere((s) => s['id'] == val);
                                      _isRunning = selected['is_running'] ?? false;
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add),
                          tooltip: 'Créer un nouveau monde',
                          onPressed: _showCreateWorldDialog,
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.settings_ethernet),
                          tooltip: 'Adresse du serveur distant',
                          onPressed: _showServerAddressConfigDialog,
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            // Paramètres Mondiaux (Terrain / Eau)
                            const Text(
                              'Configuration du Monde',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            SwitchListTile(
                              title: const Text('Présence d\'eau (Mode Île)', style: TextStyle(fontSize: 13)),
                              subtitle: const Text('L\'eau est active et les cellules s\'y noient', style: TextStyle(fontSize: 11)),
                              value: _noyadeActive,
                              onChanged: _selectedSimId == null ? null : (val) => _toggleNoyade(val),
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: Colors.tealAccent,
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: (_selectedSimId == null || !_noyadeActive) ? null : _showGenerateMapDialog,
                              icon: const Icon(Icons.map, size: 16),
                              label: const Text('Générer Île / Carte', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                            const Divider(),
                            const SizedBox(height: 8),
                            // Contrôles de simulation
                            const Text(
                              'Contrôles Temporels',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _selectedSimId == null || _isRunning ? null : () => _toggleSim(true),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Play'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _selectedSimId == null || !_isRunning ? null : () => _toggleSim(false),
                                  icon: const Icon(Icons.pause),
                                  label: const Text('Pause'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade900),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _gameState != null ? 'Ticks : ${_gameState!['tick']}' : 'Ticks : -',
                                style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Vitesse de Simulation',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [0.25, 0.5, 0.75, 1.0, 2.0, 4.0, 8.0].map((factor) {
                                  final isSelected = _speedFactor == factor;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                    child: ChoiceChip(
                                      label: Text(
                                        '${factor}x',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected ? Colors.black : Colors.white,
                                        ),
                                      ),
                                      selected: isSelected,
                                      onSelected: _selectedSimId == null
                                          ? null
                                          : (bool selected) {
                                              if (selected) {
                                                _updateSpeedFactor(factor);
                                              }
                                            },
                                      selectedColor: Colors.tealAccent,
                                      backgroundColor: Colors.teal.shade900.withValues(alpha: 0.3),
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const Divider(),
                            const SizedBox(height: 8),
                            // Outils pinceaux / Placement
                            const Text(
                              'Outils d\'édition & Placement',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Outil Actif',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _activeTool,
                                  isExpanded: true,
                                  isDense: true,
                                  items: [
                                    const DropdownMenuItem(value: 'pan', child: Row(children: [Icon(Icons.open_with, size: 18), SizedBox(width: 8), Text('Naviguer / Déplacer')])),
                                    const DropdownMenuItem(value: 'place', child: Row(children: [Icon(Icons.add_location, size: 18), SizedBox(width: 8), Text('Placer entité')])),
                                    const DropdownMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete_sweep, size: 18), SizedBox(width: 8), Text('Retirer entité')])),
                                    DropdownMenuItem(
                                      value: 'paint_land',
                                      enabled: _noyadeActive,
                                      child: Row(
                                        children: [
                                          Icon(Icons.brush, size: 18, color: _noyadeActive ? Colors.green : Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Peindre Terre',
                                            style: TextStyle(color: _noyadeActive ? null : Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'paint_water',
                                      enabled: _noyadeActive,
                                      child: Row(
                                        children: [
                                          Icon(Icons.water, size: 18, color: _noyadeActive ? Colors.blue : Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Peindre Eau',
                                            style: TextStyle(color: _noyadeActive ? null : Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _activeTool = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            if (_activeTool == 'paint_land' || _activeTool == 'paint_water') ...[
                              const SizedBox(height: 12),
                              Card(
                                color: Colors.black26,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.grey.shade800),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Taille du pinceau',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            '${_brushSize}x$_brushSize',
                                            style: const TextStyle(fontSize: 12, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      Slider(
                                        value: _brushSize.toDouble(),
                                        min: 1.0,
                                        max: 5.0,
                                        divisions: 4,
                                        activeColor: Colors.tealAccent,
                                        inactiveColor: Colors.grey.shade800,
                                        label: '${_brushSize}x$_brushSize',
                                        onChanged: (val) {
                                          setState(() {
                                            _brushSize = val.round();
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (_activeTool == 'place') ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'Entité à Placer',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedComponentId,
                                          isExpanded: true,
                                          isDense: true,
                                          items: _components.map<DropdownMenuItem<String>>((dynamic c) {
                                            return DropdownMenuItem<String>(
                                              value: c['id'],
                                              child: Row(
                                                children: [
                                                  c['is_builtin'] == true
                                                      ? const Icon(Icons.apps, size: 20, color: Colors.teal)
                                                      : Builder(
                                                          builder: (context) {
                                                            final local = _getLocalComponent(c['id']);
                                                            if (local != null) {
                                                              return Image.memory(
                                                                local.iconBytes,
                                                                width: 20,
                                                                height: 20,
                                                              );
                                                            }
                                                            return const Icon(Icons.image, size: 20);
                                                          },
                                                        ),
                                                  const SizedBox(width: 8),
                                                  Text(c['name']),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (String? val) {
                                            if (val != null) {
                                              setState(() {
                                                _selectedComponentId = val;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Importer un fichier .sssub',
                                    child: IconButton(
                                      icon: const Icon(Icons.file_upload, color: Colors.tealAccent),
                                      onPressed: _importLocalSssub,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (_activeTool == 'place' && _components.isNotEmpty) ...[
                              Builder(
                                builder: (context) {
                                  final selectedComp = _components.firstWhere(
                                    (c) => c['id'] == _selectedComponentId,
                                    orElse: () => null,
                                  );
                                  if (selectedComp == null) return const SizedBox.shrink();
                                  return Card(
                                    color: const Color(0x33004D40),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.teal.shade800),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: Row(
                                        children: [
                                          selectedComp['is_builtin'] == true
                                              ? const Icon(Icons.apps, size: 36, color: Colors.tealAccent)
                                              : Builder(
                                                  builder: (context) {
                                                    final local = _getLocalComponent(selectedComp['id']);
                                                    if (local != null) {
                                                      return Image.memory(
                                                        local.iconBytes,
                                                        width: 36,
                                                        height: 36,
                                                      );
                                                    }
                                                    return const Icon(Icons.image, size: 36);
                                                  },
                                                ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  selectedComp['name'] ?? '',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                                Text(
                                                  selectedComp['description'] ?? '',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Vitesse ATB : ${selectedComp['atb_vitesse'] ?? 10}',
                                                  style: const TextStyle(fontSize: 9, color: Colors.tealAccent),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Astuce : Utilisez la molette ou pincez pour zoomer. Glissez pour vous déplacer dans le monde.',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Grille de simulation interactive
          Expanded(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/fond.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                    padding: const EdgeInsets.all(16.0),
                    child: _connectionError
                        ? Center(
                            child: Card(
                              color: const Color(0xFF1E1E24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: SizedBox(
                                  width: 380,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.wifi_off, color: Colors.red, size: 28),
                                          SizedBox(width: 8),
                                          Text(
                                            'Serveur Injoignable',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Trebuchet MS',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Impossible de se connecter au serveur Python sur\n${ApiClient.baseUrl}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Color(0xFFC8C8D2), fontSize: 13),
                                      ),
                                      const SizedBox(height: 24),
                                      TextField(
                                        controller: _serverController,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          labelText: 'Adresse IP du serveur distant',
                                          labelStyle: const TextStyle(color: Color(0xFF00F0FF)),
                                          hintText: 'ex: 192.168.1.50',
                                          hintStyle: TextStyle(color: Colors.grey[700]),
                                          enabledBorder: OutlineInputBorder(
                                            borderSide: const BorderSide(color: Colors.grey),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderSide: const BorderSide(color: Color(0xFF00F0FF)),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              _updateServerAddress('http://127.0.0.1:5000');
                                            },
                                            child: const Text('Rétablir Localhost', style: TextStyle(color: Colors.grey)),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF00F0FF),
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            onPressed: () {
                                              final ip = _serverController.text.trim();
                                              if (ip.isNotEmpty) {
                                                final formatted = _formatAndValidateUrl(ip);
                                                _updateServerAddress(formatted);
                                              }
                                            },
                                            child: const Text('Se connecter', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : _gameState == null
                            ? const Center(
                                child: Text(
                                  "Sélectionnez ou créez un monde pour démarrer la simulation",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(1.0, 1.0),
                                        blurRadius: 4.0,
                                        color: Colors.black,
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : InteractiveIslandPainterWidget(
                                key: ValueKey('${_selectedSimId}_${_gameState!['width']}_${_gameState!['height']}'),
                                gameState: _gameState!,
                                onTapCell: _handleCellTap,
                                onPaintCell: _handleCellPaint,
                                iconCache: _iconCache,
                                activeTool: _activeTool,
                                bubbleImage: _bubbleImage,
                              ),
                  ),
                  // Chevron flottant pour ouvrir le panneau si fermé
                  if (!_showStatsPanel && _gameState != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Tooltip(
                        message: 'Afficher les statistiques',
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () {
                            setState(() {
                              _showStatsPanel = true;
                            });
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Volet de statistiques latéral droit
          if (_showStatsPanel && _gameState != null) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 320,
              child: _buildStatsPanel(),
            ),
          ],
        ],
      ),
    );
  }

  Color _parseHexColor(String hex) {
    try {
      String cleanHex = hex.toUpperCase().replaceAll('#', '');
      if (cleanHex.length == 6) {
        cleanHex = 'FF$cleanHex';
      }
      return Color(int.parse(cleanHex, radix: 16));
    } catch (e) {
      return Colors.teal;
    }
  }

  IconData _getShapeIcon(String shape) {
    switch (shape) {
      case 'cercle':
        return Icons.circle;
      case 'triangle':
      case 'triangle_inverse':
        return Icons.details;
      case 'rectangle':
        return Icons.crop_landscape;
      case 'carré':
      default:
        return Icons.square;
    }
  }

  Widget _buildStatsPanel() {
    if (_gameState == null) return const SizedBox.shrink();

    final bool isComponentMode = _selectedStatsComponentId != null && _cachedComponentStats != null;
    final bool alive = _selectedComponentAlive;

    final Color cardColor = isComponentMode && !alive
        ? const Color(0xFF4D1010)
        : const Color(0xFF0F262A);

    final Color borderColor = isComponentMode && !alive
        ? Colors.red.shade800
        : Colors.teal.shade800;

    final comp = _cachedComponentStats;
    final String colorHex = comp != null ? (comp['couleur'] ?? '#000000') : '#000000';
    final String shape = comp != null ? (comp['forme'] ?? 'carré').toString().toLowerCase() : 'carré';

    final String typeId = comp != null ? (comp['type_id'] ?? '') : '';
    final local = typeId.isNotEmpty ? _getLocalComponent(typeId) : null;
    final String? variant = comp != null ? comp['icon_variant'] : null;
    Uint8List? displayIconBytes;
    if (local != null) {
      if (variant == 'M' && local.iconMBytes != null) {
        displayIconBytes = local.iconMBytes;
      } else if (variant == 'F' && local.iconFBytes != null) {
        displayIconBytes = local.iconFBytes;
      } else {
        displayIconBytes = local.iconBytes;
      }
    }

    return Card(
      elevation: 4,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isComponentMode && comp != null) ...[
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black26,
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1.5),
                ),
              ),
              child: displayIconBytes != null
                  ? Image.memory(
                      displayIconBytes,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: 180,
                    )
                  : (comp['type_id'] != null
                      ? Image.network(
                          comp['icon_variant'] != null
                              ? '${ApiClient.baseUrl}/api/components/${comp['type_id']}/icon?variant=${comp['icon_variant']}'
                              : '${ApiClient.baseUrl}/api/components/${comp['type_id']}/icon',
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: 180,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: _parseHexColor(colorHex).withValues(alpha: 0.2),
                            child: Center(
                              child: Icon(
                                _getShapeIcon(shape),
                                color: _parseHexColor(colorHex),
                                size: 64,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: _parseHexColor(colorHex).withValues(alpha: 0.2),
                          child: Center(
                            child: Icon(
                              _getShapeIcon(shape),
                              color: _parseHexColor(colorHex),
                              size: 64,
                            ),
                          ),
                        )),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.grey),
                  tooltip: 'Fermer le volet',
                  onPressed: () {
                    setState(() {
                      _showStatsPanel = false;
                    });
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isComponentMode ? 'Inspection' : 'Statistiques',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isComponentMode) ...[
                  IconButton(
                    icon: Icon(
                      _debugMode ? Icons.bug_report : Icons.bug_report_outlined,
                      color: _debugMode ? Colors.amberAccent : Colors.grey,
                      size: 20,
                    ),
                    tooltip: 'Mode Debug',
                    onPressed: () {
                      setState(() {
                        _debugMode = !_debugMode;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.public, size: 20),
                    tooltip: 'Statistiques globales',
                    onPressed: () {
                      setState(() {
                        _selectedStatsComponentId = null;
                        _cachedComponentStats = null;
                        _selectedComponentAlive = true;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: isComponentMode
                  ? _buildComponentStatsContent(alive)
                  : _buildGlobalStatsContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentStatsContent(bool alive) {
    final comp = _cachedComponentStats!;
    final String name = comp['type'] ?? 'Composant';
    final String id = comp['id'] ?? '';
    final String shortId = id.length > 8 ? id.substring(0, 8) : id;

    final Map<String, dynamic> stats = Map<String, dynamic>.from(comp['stats'] ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent),
        ),
        const SizedBox(height: 4),
        Text(
          'ID: $shortId',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (!alive)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade900,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent),
            ),
            child: const Text(
              'MORT / DÉCÉDÉ',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade900.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: const Text(
              'ÉTAT : VIVANT',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Données Spécifiques (Comportement)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.tealAccent),
        ),
        const SizedBox(height: 8),
        if (stats.isNotEmpty)
          ...stats.entries.map((entry) => _buildRichStatWidget(entry.key, entry.value))
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'Aucune statistique spécifique renvoyée par logic.py.',
              style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildRichStatWidget(String label, dynamic rawValue) {
    dynamic val = rawValue;
    String type = 'string';

    // Support du format tuple/liste [valeur, type]
    if (rawValue is List && rawValue.length == 2) {
      val = rawValue[0];
      type = rawValue[1].toString().toLowerCase();
    }

    final String id = _selectedStatsComponentId ?? '';
    Widget contentWidget;

    switch (type) {
      case 'progress_bar':
      case 'progress_bar_pink':
      case 'progress_bar_rose':
      case 'progress_bar_red':
      case 'progress_bar_rouge':
        double percentage = 0.0;
        String textVal = '0/0';
        if (val is List && val.length == 2) {
          try {
            final double current = double.parse(val[0].toString());
            final double maxVal = double.parse(val[1].toString());
            if (maxVal > 0) {
              percentage = (current / maxVal).clamp(0.0, 1.0);
            }
            textVal = '${val[0]}/${val[1]}';
          } catch (_) {}
        }

        Color barColor = Colors.tealAccent;
        Color bgColor = Colors.teal.shade900;
        Color textColor = Colors.tealAccent;

        if (type == 'progress_bar_pink' || type == 'progress_bar_rose') {
          barColor = Colors.pinkAccent;
          bgColor = Colors.pink.shade900;
          textColor = Colors.pinkAccent;
        } else if (type == 'progress_bar_red' || type == 'progress_bar_rouge') {
          barColor = Colors.redAccent;
          bgColor = Colors.red.shade900;
          textColor = Colors.redAccent;
        }

        if (_debugMode && val is List && val.length == 2) {
          double current = 0.0;
          double maxVal = 100.0;
          try {
            current = double.parse(val[0].toString());
            maxVal = double.parse(val[1].toString());
          } catch (_) {}
          contentWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '${current.round()}/${maxVal.round()}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: current.clamp(0.0, maxVal),
                  min: 0,
                  max: maxVal,
                  activeColor: barColor,
                  inactiveColor: bgColor,
                  onChanged: (newVal) {
                    setState(() {
                      if (_cachedComponentStats != null && _cachedComponentStats!['stats'] != null) {
                        final st = _cachedComponentStats!['stats'][label];
                        if (st is List && st.length == 2 && st[0] is List) {
                          st[0][0] = newVal.round();
                        }
                      }
                    });
                  },
                  onChangeEnd: (newVal) {
                    if (id.isNotEmpty) {
                      _updateComponentStat(id, label, newVal.round());
                    }
                  },
                ),
              ),
            ],
          );
        } else {
          contentWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    textVal,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage,
                  backgroundColor: bgColor,
                  color: barColor,
                  minHeight: 8,
                ),
              ),
            ],
          );
        }
        break;

      case 'percent':
      case 'percentage':
        double percentage = 0.0;
        try {
          percentage = double.parse(val.toString());
        } catch (_) {}

        if (_debugMode) {
          contentWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '${percentage.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.tealAccent),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: percentage.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  activeColor: Colors.tealAccent,
                  inactiveColor: Colors.teal.shade900,
                  onChanged: (newVal) {
                    setState(() {
                      if (_cachedComponentStats != null && _cachedComponentStats!['stats'] != null) {
                        final st = _cachedComponentStats!['stats'][label];
                        if (st is List && st.length == 2) {
                          st[0] = newVal.round();
                        } else {
                          _cachedComponentStats!['stats'][label] = newVal.round();
                        }
                      }
                    });
                  },
                  onChangeEnd: (newVal) {
                    if (id.isNotEmpty) {
                      _updateComponentStat(id, label, newVal.round());
                    }
                  },
                ),
              ),
            ],
          );
        } else {
          double percentageVal = 0.0;
          try {
            percentageVal = (percentage / 100.0).clamp(0.0, 1.0);
          } catch (_) {}
          contentWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '$val%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.tealAccent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentageVal,
                  backgroundColor: Colors.teal.shade900,
                  color: Colors.tealAccent.shade400,
                  minHeight: 8,
                ),
              ),
            ],
          );
        }
        break;

      case 'position':
        contentWidget = Row(
          children: [
            const Icon(Icons.location_on, color: Colors.tealAccent, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      Text(
                        val.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                  if (_debugMode)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16, color: Colors.amberAccent),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showEditStatDialog(label, val),
                    ),
                ],
              ),
            ),
          ],
        );
        break;

      case 'int':
      case 'float':
      case 'number':
        contentWidget = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade800),
                  ),
                  child: Text(
                    val.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.tealAccent),
                  ),
                ),
                if (_debugMode) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 14, color: Colors.amberAccent),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showEditStatDialog(label, val),
                  ),
                ],
              ],
            ),
          ],
        );
        break;

      case 'bool':
      case 'boolean':
        final bool isTrue = val.toString().toLowerCase() == 'true' || val == true || val == 1;
        contentWidget = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (_debugMode)
              Switch(
                value: isTrue,
                activeThumbColor: Colors.greenAccent,
                onChanged: (newVal) {
                  if (id.isNotEmpty) {
                    _updateComponentStat(id, label, newVal);
                  }
                },
              )
            else
              Icon(
                isTrue ? Icons.check_circle : Icons.cancel,
                color: isTrue ? Colors.greenAccent : Colors.redAccent,
                size: 18,
              ),
          ],
        );
        break;

      case 'string':
      default:
        contentWidget = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      val.toString(),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                    ),
                  ),
                  if (_debugMode) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 14, color: Colors.amberAccent),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showEditStatDialog(label, val),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        break;
    }

    return Card(
      color: Colors.black26,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: contentWidget,
      ),
    );
  }

  Widget _buildGlobalStatsContent() {
    final Map<String, dynamic> globalStats = _gameState != null
        ? Map<String, dynamic>.from(_gameState!['global_stats'] ?? {})
        : {};

    if (globalStats.isEmpty) {
      return const Center(
        child: Text(
          'Chargement des statistiques...',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final int totalEntities = globalStats["Total d'Entités"] ?? 0;
    final String landStr = globalStats["Terre"] ?? '';
    final String waterStr = globalStats["Eau"] ?? '';
    final String gridSize = globalStats["Taille de la Grille"] ?? '';
    final Map<String, dynamic> distribution = Map<String, dynamic>.from(globalStats["Répartition"] ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Environnement',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
        ),
        const SizedBox(height: 8),
        _buildStatItem('Grille théorique', gridSize),
        _buildStatItem('Biome Terre', landStr),
        _buildStatItem('Biome Eau', waterStr),
        const SizedBox(height: 20),
        const Text(
          'Population Active',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
        ),
        const SizedBox(height: 8),
        _buildStatItem('Total d\'entités vivantes', totalEntities.toString()),
        _buildStatItem('Naissances cumulées', (globalStats["Naissances"] ?? 0).toString()),
        _buildStatItem('Décès cumulés', (globalStats["Décès"] ?? 0).toString()),
        _buildStatItem('Meurtres cumulés 💀', (globalStats["Meurtres"] ?? 0).toString()),
        const SizedBox(height: 12),
        const Text(
          'Distribution des Espèces',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        if (distribution.isNotEmpty)
          ...distribution.entries.map((entry) {
            return Card(
              color: Colors.black12,
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.bubble_chart, color: Colors.tealAccent, size: 16),
                title: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Chip(
                  label: Text(
                    entry.value.toString(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.teal.shade900,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            );
          })
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'Aucune entité vivante sur la carte.',
              style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Graphe Social & Clustering (MMSB)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 250),
            child: Image.network(
              '${ApiClient.baseUrl}/api/simulations/${_selectedSimId ?? ''}/mmsb/plot?tick=${_gameState?["tick"] ?? 0}',
              key: ValueKey('mmsb_plot_${_gameState?["tick"] ?? 0}'),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'Graphe social indisponible (moins de 2 humains ou API inactive).',
                    style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_selectedSimId != null)
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.fullscreen, size: 16),
              label: const Text('Explorer le graphe interactif (Popup)', style: TextStyle(fontSize: 11)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => InteractiveSocialGraphDialog(
                    simId: _selectedSimId!,
                    onInspectNode: (nodeId) {
                      setState(() {
                        _selectedStatsComponentId = nodeId;
                        _showStatsPanel = true;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Journal des Dialogues (Gemini)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
        ),
        const SizedBox(height: 8),
        _buildDialoguesLog(_gameState != null ? (_gameState!['dialogues'] ?? []) : []),
      ],
    );
  }

  Widget _buildDialoguesLog(List<dynamic> dialogues) {
    if (dialogues.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'Aucune discussion enregistrée. Rapprochez deux humains avec la clé API Gemini configurée pour lancer les discussions.',
          style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: dialogues.reversed.map<Widget>((dynamic d) {
        final String speaker = d['speaker_name'] ?? 'Humain';
        final String listener = d['listener_name'] ?? 'Humain';
        final String phrase = d['phrase'] ?? '';
        final int sentiment = d['sentiment'] ?? 0;
        final int tick = d['tick'] ?? 0;

        Color sentimentColor;
        IconData sentimentIcon;
        if (sentiment > 3) {
          sentimentColor = Colors.pinkAccent;
          sentimentIcon = Icons.favorite;
        } else if (sentiment > 0) {
          sentimentColor = Colors.greenAccent;
          sentimentIcon = Icons.sentiment_satisfied;
        } else if (sentiment < -3) {
          sentimentColor = Colors.redAccent;
          sentimentIcon = Icons.sentiment_very_dissatisfied;
        } else if (sentiment < 0) {
          sentimentColor = Colors.orangeAccent;
          sentimentIcon = Icons.sentiment_dissatisfied;
        } else {
          sentimentColor = Colors.grey;
          sentimentIcon = Icons.chat_bubble_outline;
        }

        return Card(
          color: const Color(0x33008080),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$speaker ➔ $listener',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.tealAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        if (d['intime'] == true) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: sentimentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: sentimentColor.withValues(alpha: 0.4), width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, size: 10, color: sentimentColor),
                                const SizedBox(width: 2),
                                Text(
                                  'Intime',
                                  style: TextStyle(fontSize: 8, color: sentimentColor, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Icon(sentimentIcon, size: 12, color: sentimentColor),
                        const SizedBox(width: 4),
                        Text(
                          'Tick $tick',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '"$phrase"',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Card(
      color: Colors.black26,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateComponentStat(String compId, String key, dynamic value) async {
    if (_selectedSimId == null) return;
    try {
      final success = await ApiClient.updateComponentStat(_selectedSimId!, compId, key, value);
      if (success) {
        _fetchGameState();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de la mise à jour de la statistique')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  void _showEditStatDialog(String label, dynamic currentValue) {
    final textController = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Modifier $label'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(
              hintText: 'Entrez la nouvelle valeur',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                final newValue = textController.text.trim();
                Navigator.pop(context);
                if (_selectedStatsComponentId != null) {
                  _updateComponentStat(_selectedStatsComponentId!, label, newValue);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }
}

class InteractiveSocialGraphDialog extends StatefulWidget {
  final String simId;
  final Function(String nodeId)? onInspectNode;
  const InteractiveSocialGraphDialog({super.key, required this.simId, this.onInspectNode});

  @override
  State<InteractiveSocialGraphDialog> createState() => _InteractiveSocialGraphDialogState();
}

class _InteractiveSocialGraphDialogState extends State<InteractiveSocialGraphDialog> {
  bool _loading = true;
  List<dynamic> _nodes = [];
  List<dynamic> _links = [];
  String? _errorMsg;
  Map<String, dynamic>? _selectedNode;

  @override
  void initState() {
    super.initState();
    _fetchGraphData();
  }

  Future<void> _fetchGraphData() async {
    try {
      final response = await http.get(Uri.parse('${ApiClient.baseUrl}/api/simulations/${widget.simId}/mmsb/data'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _nodes = data['nodes'] ?? [];
          _links = data['links'] ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _errorMsg = "Erreur HTTP : ${response.statusCode}";
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = "Impossible de se connecter à l'API.";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Graphe Social MMSB Interactif',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.tealAccent),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, color: Colors.red, size: 10),
                      SizedBox(width: 4),
                      Text('Groupe 0', style: TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.circle, color: Colors.blue, size: 10),
                      SizedBox(width: 4),
                      Text('Groupe 1', style: TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.circle, color: Color(0xFF800080), size: 10),
                      SizedBox(width: 4),
                      Text('Appartenance Mixte', style: TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: _buildGraphContent(),
              ),
            ),
            if (_selectedNode != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Humain ${_selectedNode!['label']}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Probabilité Groupe 0 : ${(_selectedNode!['membership'][0] * 100).toStringAsFixed(1)}%\n"
                            "Probabilité Groupe 1 : ${(_selectedNode!['membership'][1] * 100).toStringAsFixed(1)}%",
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.search, size: 14),
                      label: const Text('Inspecter', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade800,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        if (widget.onInspectNode != null) {
                          widget.onInspectNode!(_selectedNode!['id']);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Astuce : Utilisez le pincement pour zoomer, glissez pour déplacer, cliquez sur un nœud pour afficher ses détails.',
              style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMsg != null) {
      return Center(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)));
    }
    if (_nodes.isEmpty) {
      return const Center(
        child: Text(
          'Pas assez de données pour générer le graphe (min. 2 humains).',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;

        // Calculer les bornes min/max pour le centrage
        double minX = -1.0;
        double maxX = 1.0;
        double minY = -1.0;
        double maxY = 1.0;

        if (_nodes.isNotEmpty) {
          minX = _nodes.map((n) => (n['x'] as num).toDouble()).reduce((a, b) => a < b ? a : b);
          maxX = _nodes.map((n) => (n['x'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
          minY = _nodes.map((n) => (n['y'] as num).toDouble()).reduce((a, b) => a < b ? a : b);
          maxY = _nodes.map((n) => (n['y'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
        }

        double widthRange = (maxX - minX).abs();
        double heightRange = (maxY - minY).abs();
        if (widthRange == 0) widthRange = 1.0;
        if (heightRange == 0) heightRange = 1.0;

        minX -= widthRange * 0.15;
        maxX += widthRange * 0.15;
        minY -= heightRange * 0.15;
        maxY += heightRange * 0.15;

        Offset getOffset(double x, double y) {
          final double cx = ((x - minX) / (maxX - minX)) * width;
          final double cy = (1.0 - ((y - minY) / (maxY - minY))) * height;
          return Offset(cx, cy);
        }

        final Map<String, Offset> nodeOffsets = {};
        for (var node in _nodes) {
          final double nx = (node['x'] as num).toDouble();
          final double ny = (node['y'] as num).toDouble();
          nodeOffsets[node['id']] = getOffset(nx, ny);
        }

        return GestureDetector(
          onTapUp: (details) {
            final Offset localPos = details.localPosition;
            String? clickedNodeId;
            final double hitRadius = _nodes.length > 50 ? (_nodes.length > 120 ? 10.0 : 15.0) : 20.0;
            for (var entry in nodeOffsets.entries) {
              if ((localPos - entry.value).distance <= hitRadius) {
                clickedNodeId = entry.key;
                break;
              }
            }
            if (clickedNodeId != null) {
              final node = _nodes.firstWhere((n) => n['id'] == clickedNodeId);
              setState(() {
                _selectedNode = node;
              });
            } else {
              setState(() {
                _selectedNode = null;
              });
            }
          },
          child: InteractiveViewer(
            boundaryMargin: const EdgeInsets.all(100.0),
            minScale: 0.1,
            maxScale: 4.0,
            child: SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: GraphPainter(
                  nodes: _nodes,
                  links: _links,
                  nodeOffsets: nodeOffsets,
                  selectedNodeId: _selectedNode != null ? _selectedNode!['id'] : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GraphPainter extends CustomPainter {
  final List<dynamic> nodes;
  final List<dynamic> links;
  final Map<String, Offset> nodeOffsets;
  final String? selectedNodeId;

  GraphPainter({
    required this.nodes,
    required this.links,
    required this.nodeOffsets,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 2.0;

    for (var link in links) {
      final String source = link['source'];
      final String target = link['target'];
      if (nodeOffsets.containsKey(source) && nodeOffsets.containsKey(target)) {
        canvas.drawLine(nodeOffsets[source]!, nodeOffsets[target]!, linePaint);
      }
    }

    final double nodeRadius = nodes.length > 50 ? (nodes.length > 120 ? 6.0 : 9.0) : 12.0;
    final double outerRadius = nodeRadius + 2.0;
    final double highlightRadius = outerRadius + 4.0;

    for (var node in nodes) {
      final String nId = node['id'];
      if (!nodeOffsets.containsKey(nId)) continue;
      final Offset offset = nodeOffsets[nId]!;

      final List<dynamic> membership = node['membership'] ?? [0.5, 0.5];
      final double p0 = (membership[0] as num).toDouble();
      final double p1 = (membership[1] as num).toDouble();

      final Color nodeColor = Color.fromARGB(
        240,
        (p0 * 255).round().clamp(0, 255),
        25,
        (p1 * 255).round().clamp(0, 255),
      );

      if (selectedNodeId == nId) {
        canvas.drawCircle(
          offset,
          highlightRadius,
          Paint()
            ..color = Colors.tealAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }

      canvas.drawCircle(offset, outerRadius, Paint()..color = Colors.white);
      canvas.drawCircle(offset, nodeRadius, Paint()..color = nodeColor);

      // Draw label text inside circle only if total nodes <= 120
      if (nodes.length <= 120) {
        final double fontSize = nodes.length > 50 ? 6.0 : 8.0;
        final String label = node['label'] ?? '';
        final TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(blurRadius: 4.0, color: Colors.black, offset: Offset(1, 1))
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(offset.dx - textPainter.width / 2, offset.dy - textPainter.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

