import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/client_settings.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _dirController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });
    try {
      if (kIsWeb) {
        _dirController.text = 'Mode Web (fichiers téléchargés par le navigateur)';
      } else {
        final dataDir = await ClientSettings.getWorkspacePath();
        _dirController.text = dataDir;
      }
      
      final apiKey = await ClientSettings.getGeminiApiKey();
      _apiKeyController.text = apiKey;
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur lors du chargement : $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _browseDirectory() async {
    if (kIsWeb) return;
    try {
      final String? selectedPath = await FilePicker.getDirectoryPath();
      if (selectedPath != null) {
        setState(() {
          _dirController.text = selectedPath;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de sélectionner le dossier : $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    final path = _dirController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      if (!kIsWeb && path.isNotEmpty) {
        await ClientSettings.setWorkspacePath(path);
      }
      await ClientSettings.setGeminiApiKey(apiKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paramètres mis à jour avec succès !'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur lors de l\'enregistrement : ${e.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: SizedBox(
          width: 600,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, size: 28, color: Colors.tealAccent.shade400),
                      const SizedBox(width: 12),
                      const Text(
                        'Paramètres Jörmungandr',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Dossier de travail (Workspace & .sssub)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Définissez le dossier dans lequel vos fichiers .sssub, configurations et paramètres seront stockés.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dirController,
                          enabled: !kIsWeb,
                          decoration: const InputDecoration(
                            labelText: 'Chemin du dossier de travail',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _browseDirectory,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Parcourir'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade800),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blueAccent),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'En mode Web, la configuration du répertoire de travail local n\'est pas prise en charge pour des raisons de sécurité. Les composants générés seront directement téléchargés par votre navigateur.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Configuration d\'Intelligence Artificielle',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Renseignez votre clé API Gemini (Google AI Studio) pour activer la génération automatique et l\'analyse de sentiment des dialogues entre habitants.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Clé API Gemini (Google AI Studio)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  if (_statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isLoading ? null : _loadSettings,
                        child: const Text('Réinitialiser'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveSettings,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Enregistrer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
