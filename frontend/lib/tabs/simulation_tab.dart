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
  bool _isPlacementMode = true; // true: Placer, false: Retirer
  Timer? _pollingTimer;
  Timer? _listTimer;
  Map<String, dynamic>? _gameState;
  bool _isRunning = false;

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
        // S'assurer que le composant sélectionné existe toujours
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

  Future<void> _handleCellTap(int x, int y) async {
    if (_selectedSimId == null) return;
    
    if (_isPlacementMode) {
      if (_selectedComponentId == null) return;
      try {
        final response = await ApiClient.addComponent(_selectedSimId!, _selectedComponentId!, x, y);
        if (response.statusCode == 200) {
          _fetchGameState(); // Actualisation immédiate
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
    } else {
      // Retirer (via endpoint DELETE avec query params)
      try {
        final success = await ApiClient.removeComponent(_selectedSimId!, x, y);
        if (success) {
          _fetchGameState(); // Actualisation immédiate
        }
      } catch (e) {
        // Ignorer
      }
    }
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
                    const SizedBox(height: 16),
                    const Text(
                      'Contrôles Temporels',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    Text(
                      _gameState != null ? 'Ticks écoulés : ${_gameState!['tick']}' : 'Ticks : -',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Placement des Entités',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
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
                    const SizedBox(height: 16),
                    // Mode : Placer ou Retirer
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Placer')),
                            selected: _isPlacementMode,
                            onSelected: (selected) {
                              setState(() {
                                _isPlacementMode = true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Retirer')),
                            selected: !_isPlacementMode,
                            onSelected: (selected) {
                              setState(() {
                                _isPlacementMode = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_components.isNotEmpty) ...[
                      Builder(
                        builder: (context) {
                          final selectedComp = _components.firstWhere(
                            (c) => c['id'] == _selectedComponentId,
                            orElse: () => null,
                          );
                          if (selectedComp == null) return const SizedBox.shrink();
                          return Card(
                            color: const Color(0x33004D40), // Vert foncé translucide
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.teal.shade800),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  selectedComp['is_builtin'] == true
                                      ? const Icon(Icons.apps, size: 40, color: Colors.tealAccent)
                                      : Image.network(
                                          '${ApiClient.baseUrl}${selectedComp['icon_url']}',
                                          width: 40,
                                          height: 40,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.image, size: 40),
                                        ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedComp['name'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          selectedComp['description'] ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Vitesse ATB : ${selectedComp['atb_vitesse'] ?? 10}',
                                          style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
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
                      'Astuce : Cliquez directement sur la grille pour placer ou retirer des entités.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _gameState == null
                    ? const Center(
                        child: Text(
                          "Sélectionnez ou créez un monde pour démarrer la simulation",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : InteractiveIslandPainterWidget(
                        gameState: _gameState!,
                        onTapCell: _handleCellTap,
                        iconCache: _iconCache,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
