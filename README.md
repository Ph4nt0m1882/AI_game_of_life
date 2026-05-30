![alt text](.github/assets/Jörmungandr.png)

# Jörmungandr - AI Game of Life & Automated Agents

**Jörmungandr** (l'ouroboros) est un bac à sable (sandbox) de simulation d'automates cellulaires et d'agents intelligents développé en **Flutter** (pour l'interface graphique premium) et **FastAPI/Python** (pour le moteur de simulation dynamique).

Le projet permet de concevoir, tester et simuler des entités autonomes régies par des scripts logiques personnalisés, interagissant sur une île générée de manière procédurale.

---

## 🚀 Fonctionnalités Clés

*   **Moteur Environnemental Spacialisé** : Génération de grille représentant une île (Terre) entourée d'eau, où les entités peuvent se déplacer, survivre ou se noyer.
*   **Architecture 100% Modulaire (`.sssub`)** : Les composants ne sont pas codés en dur. Ce sont des modules autonomes empaquetés sous le format `.sssub` (archives ZIP renommées contenant un manifest JSON, un script logique Python `logic.py` et une icône PNG).
*   **Component Maker Intégratif** :
    *   Formulaire visuel pour éditer les métadonnées (nom, description, vitesse ATB).
    *   Éditeur de code Python temps réel intégré pour écrire les règles de comportement de l'agent.
    *   Sélecteur et éditeur géométrique de forme (avatar vectoriel avec forme, coin arrondi, orientation et palette de couleurs personnalisée) avec prévisualisation en direct.
    *   Éditeur de relations/interactions de base entre entités.
*   **Stockage Client Décentralisé (Workspace)** : Un onglet paramètres permet de définir n'importe quel dossier local comme répertoire de travail. Les fichiers `.sssub` créés ou importés y sont enregistrés directement et persistés dans la configuration serveur.

---

## 🛠️ Architecture du Projet

Le projet est divisé en deux parties indépendantes communiquant via une API REST :

```
├── backend/                  # Partie Serveur (FastAPI)
│   ├── core/                 # Coeur du système (loader dynamique, scheduler)
│   ├── app.py                # Routeur API (REST endpoints)
│   ├── simulation.py         # Moteur principal de la simulation (grille & ticks)
│   └── custom_components/    # Répertoire par défaut des composants personnalisés
│
└── frontend/                 # Partie Client (Flutter)
    ├── lib/
    │   ├── main.dart         # Point d'entrée de l'application & Sidebar de navigation
    │   ├── services/         # Client API centralisé (api_client.dart)
    │   ├── tabs/             # Onglets (Simulation, Component Maker, Paramètres)
    │   └── widgets/          # Peintres personnalisés (grille de l'île, avatar preview)
    └── pubspec.yaml          # Dépendances Flutter
```

---

## 📦 Le Format de Composant `.sssub`

Chaque entité créée par le **Component Maker** est compilée dans une archive `.sssub` contenant :

1.  **`manifest.json`** : Décrit l'identité visuelle et comportementale.
    ```json
    {
      "id": "robot_a8b27f",
      "name": "Robot",
      "description": "Une entité métallique autonome.",
      "atb_vitesse": 15,
      "forme": "triangle",
      "coin": "arrondi",
      "orientation": "90°",
      "couleur": "#FF9800",
      "interactions": {
        "arbre_827f": "Coupe le composant arbre si à proximité."
      }
    }
    ```
2.  **`logic.py`** : Script définissant les actions de l'entité lors de son activation.
3.  **`icon.png`** : Image servant d'illustration dans les menus d'informations.

---

## 🏁 Guide de Démarrage Rapide

### Prérequis
*   [Python 3.8+](https://www.python.org/)
*   [Flutter SDK](https://docs.flutter.dev/get-started/install)

### 1. Lancer le Serveur Backend
Placez-vous dans le dossier `backend`, installez les dépendances et démarrez l'API :
```bash
cd backend
pip install -r requirements.txt
python app.py
```
Le serveur démarrera en mode rechargement automatique sur `http://127.0.0.1:5000`.

### 2. Lancer l'Application Frontend (Flutter)
Dans un autre terminal, placez-vous dans le dossier `frontend` et exécutez le client :
```bash
cd frontend
flutter run -d chrome  # Ou remplacez "chrome" par votre OS natif (ex: windows)
```

---

## 💡 Créer un Composant Personnalisé

Dans l'onglet **Component Maker** :
1.  Saisissez le **Nom** et la **Description** du composant.
2.  Importez une icône au format **PNG** (utilisée pour les fiches info).
3.  Configurez l'aspect de son **Avatar** (forme géométrique, couleur, rotation). L'aperçu s'affiche en temps réel.
4.  Modifiez le script logique Python dans l'éditeur de code. Votre classe doit hériter de `Composant` et implémenter `action(self, simulation)` :
    ```python
    from core.composant import Composant
    import random

    class MonComposant(Composant):
        def action(self, simulation):
            # Se déplace aléatoirement sur une case "Terre" adjacente non occupée
            dx, dy = random.choice([-1, 0, 1]), random.choice([-1, 0, 1])
            nx, ny = self.x + dx, self.y + dy
            if simulation.is_terre(nx, ny) and simulation.get_composant_at(nx, ny) is None:
                simulation.grille_entites.pop((self.x, self.y), None)
                self.x, self.y = nx, ny
                simulation.grille_entites[(self.x, self.y)] = self
    ```
5.  Cliquez sur **GÉNÉRER ET CHARGER COMPOSANT (.sssub)**. L'entité sera disponible immédiatement dans le menu de placement de la simulation.

---

## 🔮 Évolutions Futures (Post-MVP)

*   **Noyade** : Les cellules sur les cases d'eau se noient si elles y restent plus de 3 itérations.
*   **NLP & IA Conversationnelle** : Intégration de LLM locaux pour générer des discussions textuelles entre les agents lors de rencontres sur l'île.
*   **Analyse d'Intention** : Un modèle NLP écoutera les dialogues et modifiera dynamiquement les relations sociales (amitiés, hostilités) ou déclenchera des comportements de survie ou d'attaque.