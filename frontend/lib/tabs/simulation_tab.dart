import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../widgets/island_painter.dart';

class SimulationTab extends StatefulWidget {
  const SimulationTab({super.key});

  @override
  State<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  List<dynamic> _simulations = [];
  List<dynamic> _components = [];
  String? _selectedSimId;
  String? _selectedComponentId;
  String _activeTool = 'place'; // 'place', 'remove', 'paint_land', 'paint_water'
  int _brushSize = 1; // Taille du pinceau (1 = 1x1, 2 = rayon 1, etc.)
  bool _noyadeActive = true;
  Timer? _pollingTimer;
  Timer? _listTimer;
  Map<String, dynamic>? _gameState;
  bool _isRunning = false;
  
  // États pour le volet de statistiques
  bool _showStatsPanel = false;
  String? _selectedStatsComponentId;
  Map<String, dynamic>? _cachedComponentStats;
  bool _selectedComponentAlive = true;

  final Map<String, ui.Image> _iconCache = {};

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
    _fetchSimulations();
    _fetchComponents();
    
    // Polling régulier de l'état du monde
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_selectedSimId != null) {
        _fetchGameState();
      }
    });

    // Polling des mondes et des composants disponibles
    _listTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchSimulations();
      _fetchComponents();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _listTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSimulations() async {
    try {
      final fetchedSims = await ApiClient.fetchSimulations();
      setState(() {
        _simulations = fetchedSims;
        if (_selectedSimId == null && _simulations.isNotEmpty) {
          _selectedSimId = _simulations.first['id'];
          _isRunning = _simulations.first['is_running'];
        }
      });
    } catch (e) {
      // Ignorer les erreurs de connexion réseau temporaires
    }
  }

  Future<void> _fetchComponents() async {
    try {
      final fetchedComps = await ApiClient.fetchComponents();
      setState(() {
        _components = fetchedComps;
        if (_selectedComponentId == null || !_components.any((c) => c['id'] == _selectedComponentId)) {
          _selectedComponentId = _components.isNotEmpty ? _components.first['id'] : null;
        }
      });

      // Charger les images dans le cache
      for (var c in fetchedComps) {
        if (c['is_builtin'] == false && c['id'] != null && c['icon_url'] != null) {
          _loadIconToCache(c['name'], '${ApiClient.baseUrl}${c['icon_url']}');
        }
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _fetchGameState() async {
    if (_selectedSimId == null) return;
    try {
      final state = await ApiClient.fetchGameState(_selectedSimId!);
      if (mounted) {
        setState(() {
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
      // Ignorer
    }
  }

  Future<void> _createNewSim() async {
    try {
      final simId = await ApiClient.createSimulation();
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

  Future<void> _toggleSim(bool start) async {
    if (_selectedSimId == null) return;
    try {
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
      final success = await ApiClient.updateSimulationSettings(_selectedSimId!, noyadeActive: value);
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
        final response = await ApiClient.addComponent(_selectedSimId!, _selectedComponentId!, x, y);
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
                          onPressed: _createNewSim,
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
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
                      InputDecorator(
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
                                        : Image.network(
                                            '${ApiClient.baseUrl}${c['icon_url']}',
                                            width: 20,
                                            height: 20,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Icon(Icons.image, size: 20),
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
                                      : Image.network(
                                          '${ApiClient.baseUrl}${selectedComp['icon_url']}',
                                          width: 36,
                                          height: 36,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.image, size: 36),
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
                    const Spacer(),
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
                    child: _gameState == null
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
                            gameState: _gameState!,
                            onTapCell: _handleCellTap,
                            onPaintCell: _handleCellPaint,
                            iconCache: _iconCache,
                            activeTool: _activeTool,
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
              child: comp['type_id'] != null
                  ? Image.network(
                      '${ApiClient.baseUrl}/api/components/${comp['type_id']}/icon',
                      fit: BoxFit.cover,
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
                    ),
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
                if (isComponentMode)
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

    Widget contentWidget;

    switch (type) {
      case 'progress_bar':
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.tealAccent),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                backgroundColor: Colors.teal.shade900,
                color: Colors.tealAccent,
                minHeight: 8,
              ),
            ),
          ],
        );
        break;

      case 'percent':
      case 'percentage':
        double percentage = 0.0;
        try {
          percentage = (double.parse(val.toString()) / 100.0).clamp(0.0, 1.0);
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
                value: percentage,
                backgroundColor: Colors.teal.shade900,
                color: Colors.tealAccent.shade400,
                minHeight: 8,
              ),
            ),
          ],
        );
        break;

      case 'position':
        contentWidget = Row(
          children: [
            const Icon(Icons.location_on, color: Colors.tealAccent, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
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
            Text(
              val.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
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
      ],
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
}
