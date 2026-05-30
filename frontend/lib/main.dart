import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Game of Life',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<dynamic> _simulations = [];
  String? _selectedSimId;
  Timer? _listTimer;

  @override
  void initState() {
    super.initState();
    _fetchSimulations();
    _listTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchSimulations();
    });
  }

  @override
  void dispose() {
    _listTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSimulations() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/list_sims'));
      if (response.statusCode == 200) {
        setState(() {
          _simulations = json.decode(response.body);
          if (_selectedSimId == null && _simulations.isNotEmpty) {
            _selectedSimId = _simulations.first['id'];
          }
        });
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _createNewSim() async {
    try {
      final response = await http.post(Uri.parse('http://127.0.0.1:5000/new_sim'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _selectedSimId = data['sim_id'];
        });
        _fetchSimulations();
      }
    } catch (e) {
      // Ignorer
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulations (ATB Multi-Mondes)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Créer un nouveau monde',
            onPressed: _createNewSim,
          ),
          if (_simulations.isNotEmpty)
            DropdownButton<String>(
              value: _selectedSimId,
              icon: const Icon(Icons.arrow_downward),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedSimId = newValue;
                });
              },
              items: _simulations.map<DropdownMenuItem<String>>((dynamic sim) {
                return DropdownMenuItem<String>(
                  value: sim['id'],
                  child: Text('Monde: ${sim['id']}'),
                );
              }).toList(),
            )
        ],
      ),
      body: _selectedSimId == null
          ? const Center(child: Text("Aucune simulation active. Cliquez sur + pour créer un monde."))
          : SimulationViewer(simId: _selectedSimId!),
    );
  }
}

class SimulationViewer extends StatefulWidget {
  final String simId;
  const SimulationViewer({super.key, required this.simId});

  @override
  State<SimulationViewer> createState() => _SimulationViewerState();
}

class _SimulationViewerState extends State<SimulationViewer> {
  Timer? _timer;
  Map<String, dynamic>? _gameState;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant SimulationViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.simId != widget.simId) {
      _gameState = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      _fetchState();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchState() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/state/${widget.simId}'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _gameState = json.decode(response.body);
          });
        }
      }
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _startSim() async {
    await http.post(Uri.parse('http://127.0.0.1:5000/start/${widget.simId}'));
    setState(() { _isRunning = true; });
  }

  Future<void> _stopSim() async {
    await http.post(Uri.parse('http://127.0.0.1:5000/stop/${widget.simId}'));
    setState(() { _isRunning = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
                onPressed: _startSim,
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
                onPressed: _stopSim,
              ),
            ],
          ),
        ),
        Expanded(
          child: _gameState == null
              ? const Center(child: CircularProgressIndicator())
              : IslandPainterWidget(gameState: _gameState!),
        ),
      ],
    );
  }
}

class IslandPainterWidget extends StatelessWidget {
  final Map<String, dynamic> gameState;
  const IslandPainterWidget({super.key, required this.gameState});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: IslandPainter(gameState: gameState),
        );
      },
    );
  }
}

class IslandPainter extends CustomPainter {
  final Map<String, dynamic> gameState;

  IslandPainter({required this.gameState});

  @override
  void paint(Canvas canvas, Size size) {
    final int width = gameState['width'];
    final int height = gameState['height'];
    final List<dynamic> grille = gameState['grille'];
    final List<dynamic> composants = gameState['composants'];

    final double cellWidth = size.width / width;
    final double cellHeight = size.height / height;
    final double cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;
    
    final double offsetX = (size.width - (width * cellSize)) / 2;
    final double offsetY = (size.height - (height * cellSize)) / 2;

    final Paint waterPaint = Paint()..color = Colors.blue.shade800;
    final Paint landPaint = Paint()..color = Colors.green.shade600;
    final Paint cellPaint = Paint()..color = Colors.black87;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final Rect rect = Rect.fromLTWH(
          offsetX + x * cellSize,
          offsetY + y * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, grille[y][x] == 1 ? landPaint : waterPaint);
      }
    }

    for (var comp in composants) {
      if (comp['vivant']) {
        final Rect rect = Rect.fromLTWH(
          offsetX + comp['x'] * cellSize + 1,
          offsetY + comp['y'] * cellSize + 1,
          cellSize - 2,
          cellSize - 2,
        );
        canvas.drawRect(rect, cellPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
