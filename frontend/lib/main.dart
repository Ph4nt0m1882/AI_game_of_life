import 'package:flutter/material.dart';
import 'tabs/simulation_tab.dart';
import 'tabs/component_maker_tab.dart';
import 'tabs/settings_tab.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jörmungandr - AI Game of Life',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const SimulationTab(),
    const ComponentMakerTab(),
    const SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar de navigation gauche (look Premium)
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: const Color(0x660A2E2E),
            leading: Column(
              children: [
                const SizedBox(height: 16),
                Icon(Icons.blur_circular, size: 48, color: Colors.tealAccent.shade400),
                const SizedBox(height: 8),
                const Text(
                  'Jörmungandr',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.tealAccent,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle_filled, color: Colors.tealAccent),
                label: Text('Simulation'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.handyman_outlined),
                selectedIcon: Icon(Icons.handyman, color: Colors.tealAccent),
                label: Text('Component Maker'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: Colors.tealAccent),
                label: Text('Paramètres'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Contenu principal
          Expanded(
            child: _tabs[_currentIndex],
          ),
        ],
      ),
    );
  }
}
