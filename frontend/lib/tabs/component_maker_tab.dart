import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as io;
import '../services/api_client.dart';
import '../widgets/avatar_preview.dart';

class ComponentMakerTab extends StatefulWidget {
  const ComponentMakerTab({super.key});

  @override
  State<ComponentMakerTab> createState() => _ComponentMakerTabState();
}

class _ComponentMakerTabState extends State<ComponentMakerTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  double _atbSpeed = 10.0;
  
  Uint8List? _selectedIconBytes;
  String? _selectedIconName;

  String _selectedForme = "carré";
  String _selectedCoin = "droit";
  String _selectedOrientation = "standard";
  final _colorController = TextEditingController(text: "#008080");

  Color _parsePreviewColor(String hex) {
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

  // Code Python de base par défaut
  final _logicController = TextEditingController(text: '''from core.composant import Composant

class MonComposant(Composant):
    def __init__(self, x, y, atb_vitesse=10):
        super().__init__(x, y, atb_vitesse)
        self.type_nom = "MonComposant"
        self.forme = "triangle"  # formes valides : carré, carré_arrondi, cercle, triangle, triangle_inverse
        self.couleur = "#00FF00"  # Couleur hexadécimale de départ (Vert)

    def action(self, simulation):
        # Action exécutée lorsque l'ATB atteint 100
        # Exemple : déplacement aléatoire sur la terre
        import random
        dx = random.choice([-1, 0, 1])
        dy = random.choice([-1, 0, 1])
        nx, ny = self.x + dx, self.y + dy
        if simulation.is_terre(nx, ny) and simulation.get_composant_at(nx, ny) is None:
            # Pop l'ancienne case et enregistre la nouvelle
            simulation.grille_entites.pop((self.x, self.y), None)
            self.x = nx
            self.y = ny
            simulation.grille_entites[(self.x, self.y)] = self
            
        # Exemple de couleur dynamique : changer de couleur de façon aléatoire à chaque tick d'action
        # self.couleur = random.choice(["#FF0000", "#00FF00", "#0000FF", "#FFFF00"])

    def stats(self):
        """Retourne des statistiques spécifiques affichées dans l'inspecteur."""
        return {
            "Statut": ("Actif", "string"),
            "Énergie": (100, "percent"),
            "Position": (f"({self.x}, {self.y})", "position")
        }
''');

  // Gestion des interactions
  List<dynamic> _existingComponents = [];
  String? _selectedTargetId;
  final _interactionDescController = TextEditingController();
  final Map<String, String> _localInteractions = {}; // id_cible -> description

  String _compilerError = '';
  bool _isBuilding = false;

  @override
  void initState() {
    super.initState();
    _fetchExistingComponents();
  }

  Future<void> _fetchExistingComponents() async {
    try {
      final fetchedComps = await ApiClient.fetchComponents();
      setState(() {
        _existingComponents = fetchedComps;
        if (_selectedTargetId == null || !_existingComponents.any((c) => c['id'] == _selectedTargetId)) {
          _selectedTargetId = _existingComponents.isNotEmpty ? _existingComponents.first['id'] : null;
        }
      });
    } catch (e) {
      // Ignorer
    }
  }

  Future<void> _pickIcon() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        try {
          bytes = io.File(file.path!).readAsBytesSync();
        } catch (e) {
          // Ignorer
        }
      }
      if (bytes != null) {
        setState(() {
          _selectedIconBytes = bytes;
          _selectedIconName = file.name;
        });
      }
    }
  }

  void _addInteraction() {
    if (_selectedTargetId == null || _interactionDescController.text.trim().isEmpty) return;
    setState(() {
      _localInteractions[_selectedTargetId!] = _interactionDescController.text.trim();
      _interactionDescController.clear();
    });
  }

  void _removeInteraction(String targetId) {
    setState(() {
      _localInteractions.remove(targetId);
    });
  }

  Future<void> _buildAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedIconBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une icône PNG pour le composant.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isBuilding = true;
      _compilerError = '';
    });

    try {
      final response = await ApiClient.buildComponent(
        name: _nameController.text,
        description: _descController.text,
        vitesse: _atbSpeed.toInt(),
        logicPy: _logicController.text,
        interactionsJson: json.encode(_localInteractions),
        forme: _selectedForme,
        coin: _selectedCoin,
        orientation: _selectedOrientation,
        couleur: _colorController.text,
        iconBytes: _selectedIconBytes!,
        iconFilename: _selectedIconName ?? 'icon.png',
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Composant généré et chargé avec succès !'), backgroundColor: Colors.green),
          );
        }
        // Reset form
        setState(() {
          _nameController.clear();
          _descController.clear();
          _selectedIconBytes = null;
          _selectedIconName = null;
          _localInteractions.clear();
          _selectedForme = "carré";
          _selectedCoin = "droit";
          _selectedOrientation = "standard";
          _colorController.text = "#008080";
        });
        _fetchExistingComponents();
      } else {
        final errorDetail = json.decode(response.body)['detail'] ?? 'Erreur inconnue';
        setState(() {
          _compilerError = errorDetail.toString();
        });
      }
    } catch (e) {
      setState(() {
        _compilerError = 'Impossible de se connecter au serveur backend : $e';
      });
    } finally {
      setState(() {
        _isBuilding = false;
      });
    }
  }

  Future<void> _importSssub() async {
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
          bytes = io.File(file.path!).readAsBytesSync();
        } catch (e) {
          // Ignorer
        }
      }
      if (bytes == null) return;

      setState(() {
        _isBuilding = true;
        _compilerError = '';
      });

      try {
        final response = await ApiClient.uploadComponent(bytes, file.name);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final meta = data['metadata'] ?? {};
          final String logicPy = data['logic_py'] ?? '';
          final String iconBase64 = data['icon_base64'] ?? '';

          setState(() {
            _nameController.text = meta['name'] ?? '';
            _descController.text = meta['description'] ?? '';
            _colorController.text = meta['couleur'] ?? '#008080';
            _atbSpeed = (meta['atb_vitesse'] ?? 10).toDouble();
            _selectedForme = meta['forme'] ?? 'carré';
            _selectedCoin = meta['coin'] ?? 'droit';
            _selectedOrientation = meta['orientation'] ?? 'standard';
            _logicController.text = logicPy;
            if (iconBase64.isNotEmpty) {
              _selectedIconBytes = base64.decode(iconBase64);
              _selectedIconName = 'icon.png';
            } else {
              _selectedIconBytes = null;
              _selectedIconName = null;
            }
            
            // Charger les interactions
            _localInteractions.clear();
            final rawInteractions = meta['interactions'];
            if (rawInteractions is Map) {
              rawInteractions.forEach((key, value) {
                _localInteractions[key.toString()] = value.toString();
              });
            }
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Composant "${meta['name']}" importé et chargé dans l\'éditeur !'), backgroundColor: Colors.green),
            );
          }
          _fetchExistingComponents();
        } else {
          final errorDetail = json.decode(response.body)['detail'] ?? 'Erreur inconnue';
          setState(() {
            _compilerError = errorDetail.toString();
          });
        }
      } catch (e) {
        setState(() {
          _compilerError = 'Erreur lors de l\'importation : $e';
        });
      } finally {
        setState(() {
          _isBuilding = false;
        });
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
          // Panneau Gauche : Formulaire Manifest & Interactions
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Créateur de Composants',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                            ),
                            ElevatedButton.icon(
                              onPressed: _importSssub,
                              icon: const Icon(Icons.file_upload),
                              label: const Text('Importer .sssub'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade900,
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Nom
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nom du Composant (ex: Arbre)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Veuillez saisir un nom';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Description
                        TextFormField(
                          controller: _descController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ATB Speed
                        Text(
                          'Vitesse ATB (ticks requis pour agir) : ${_atbSpeed.toInt()}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: _atbSpeed,
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: _atbSpeed.round().toString(),
                          onChanged: (double val) {
                            setState(() {
                              _atbSpeed = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        // Icon Picker
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _pickIcon,
                                icon: const Icon(Icons.image),
                                label: Text(_selectedIconName ?? 'Choisir une Icône PNG'),
                              ),
                            ),
                            if (_selectedIconBytes != null) ...[
                              const SizedBox(width: 16),
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.tealAccent),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _selectedIconBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ]
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Caractéristiques Visuelles (Avatar)',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Configurez l\'aspect géométrique de votre entité sur la carte.',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            AvatarPreviewWidget(
                              shape: _selectedForme,
                              coin: _selectedCoin,
                              orientation: _selectedOrientation,
                              color: _parsePreviewColor(_colorController.text),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Forme de l\'avatar',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedForme,
                              isExpanded: true,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(value: 'carré', child: Text('Carré')),
                                DropdownMenuItem(value: 'rectangle', child: Text('Rectangle')),
                                DropdownMenuItem(value: 'cercle', child: Text('Cercle')),
                                DropdownMenuItem(value: 'triangle', child: Text('Triangle')),
                              ],
                              onChanged: (String? val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedForme = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Coins',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedCoin,
                              isExpanded: true,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(value: 'droit', child: Text('Droit')),
                                DropdownMenuItem(value: 'arrondi', child: Text('Arrondi')),
                              ],
                              onChanged: (String? val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedCoin = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Orientation',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedOrientation,
                              isExpanded: true,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(value: 'standard', child: Text('Standard')),
                                DropdownMenuItem(value: 'inversé', child: Text('Inversé (180°)')),
                                DropdownMenuItem(value: '90°', child: Text('90°')),
                                DropdownMenuItem(value: '180°', child: Text('180°')),
                                DropdownMenuItem(value: '210°', child: Text('210°')),
                                DropdownMenuItem(value: '270°', child: Text('270°')),
                              ],
                              onChanged: (String? val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedOrientation = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _colorController,
                          decoration: InputDecoration(
                            labelText: 'Couleur de l\'avatar (Hexadécimal)',
                            border: const OutlineInputBorder(),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _parsePreviewColor(_colorController.text),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            '#000000',
                            '#808080',
                            '#E53935',
                            '#FB8C00',
                            '#FDD835',
                            '#4CAF50',
                            '#008080',
                            '#1E88E5',
                            '#3949AB',
                            '#8E24AA',
                            '#D81B60',
                            '#6D4C41',
                          ].map((String hex) {
                            final Color c = _parsePreviewColor(hex);
                            final bool isSelected = _colorController.text.toUpperCase() == hex.toUpperCase();
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _colorController.text = hex;
                                });
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    if (isSelected)
                                      const BoxShadow(
                                        color: Colors.tealAccent,
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        // INTERACTIONS
                        const Text(
                          'Interactions (Configuration)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Composant cible',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedTargetId,
                                    isExpanded: true,
                                    isDense: true,
                                    items: _existingComponents.map<DropdownMenuItem<String>>((dynamic c) {
                                      return DropdownMenuItem<String>(
                                        value: c['id'],
                                        child: Text(c['name']),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedTargetId = val;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _interactionDescController,
                                decoration: const InputDecoration(
                                  labelText: 'Description de l\'interaction',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: _addInteraction,
                              icon: const Icon(Icons.add),
                              tooltip: 'Ajouter l\'interaction',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Liste des interactions locales
                        if (_localInteractions.isNotEmpty) ...[
                          const Text('Interactions définies :'),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _localInteractions.length,
                            itemBuilder: (context, index) {
                              final key = _localInteractions.keys.elementAt(index);
                              final value = _localInteractions[key];
                              final targetName = _existingComponents.firstWhere(
                                (c) => c['id'] == key,
                                orElse: () => {'name': key},
                              )['name'];
                              return Card(
                                color: const Color(0x4D0A2E2E),
                                child: ListTile(
                                  title: Text('$targetName'),
                                  subtitle: Text('$value'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _removeInteraction(key),
                                  ),
                                ),
                              );
                            },
                          ),
                        ] else
                          const Text(
                            'Aucune interaction configurée pour le moment.',
                            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Panneau Droite : Éditeur de Code & Logs de Compilation
          Expanded(
            flex: 4,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Logique Python (logic.py)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                           color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade800),
                        ),
                        child: TextField(
                          controller: _logicController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Colors.greenAccent,
                          ),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.all(12),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    if (_compilerError.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x802D0A0A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          'Erreur de compilation / exécution :\n$_compilerError',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isBuilding ? null : _buildAndSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isBuilding
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'GÉNÉRER ET CHARGER COMPOSANT (.sssub)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
