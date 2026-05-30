# Idées et To-Do : Jeu de la Vie & IA (Brainstorming)

## Concepts de Base (Mécaniques d'Automates Cellulaires Avancés)
- [ ] **Génération de Terrain (L'Île) :**
  - Matrice avec différents types de biomes/cases (ex: Terre, Eau).
  - Génération procédurale (ex: Bruit de Perlin) pour créer une île centrale entourée d'eau de manière naturelle.

## Règles de Survie (Environnementales)
- [ ] **Interaction avec l'environnement :**
  - **Terre :** Les cellules "marchent" (comportement normal du jeu de la vie ou déplacement d'agents).
  - **Eau :** Les cellules "nagent" mais ont une limite de respiration.
  - **Noyade :** Une cellule sur une case "Eau" meurt (se noie) si elle y reste pendant plus de 3 itérations consécutives.

## Architecture Technique (Backend & Frontend)
- [ ] **Moteur Principal (`simulation.py` - Backend Python) :**
  - Gère la boucle principale, le temps (itérations) et la grille spatiale.
  - S'occupe de la génération de l'île (bruit de Perlin, biomes : terre, eau).
  - Fonctionne de manière autonome en arrière-plan (serveur/API).
- [ ] **Système de Composants Modulaires (Dossier `composants/`) :**
  - Architecture type "Plugin" : on peut ajouter/retirer des entités facilement (humains, arbres, chats).
  - Chaque composant est un module indépendant avec son propre script Python et ses fichiers d'interaction.
- [ ] **Interface d'Administration (Frontend Web) :**
  - **Visualisation de l'Île :** Rendu en temps réel (ou différé) de la grille et du déplacement des entités (Canvas/WebGL).
  - **Tableau de bord et Statistiques :** Un grand nombre de visualisations de données.
  - **Graphes Relationnels :** Génération de graphes de type MMSB (Mixed Membership Stochastic Blockmodel) pour observer les réseaux d'amitiés, d'hostilités ou d'interactions sociales entre les agents.

## Règles de Survie (Environnementales)
- [ ] **Interaction basique avec l'environnement :**
  - L'entité sur la "Terre" se déplace selon son comportement.
  - L'entité sur "L'Eau" a une limite de temps avant noyade (ex: 3 itérations).

## Intégration de l'IA et Comportements
- [ ] **Modèle de Connaissance Locale :**
  - Les composants n'ont accès qu'à leur propre champ de vision et mémoire (brouillard de guerre cognitif).
  - *Note :* Les graphes de réseau (comme le MMSB) sont calculés globalement de manière omnisciente mais uniquement affichés dans le tableau de bord web à des fins statistiques.
- [ ] **Discussions via LLM (Génération de Langage) :**
  - Intégration d'un petit modèle de langage (LLM local ou API) pour générer des dialogues entre les composants lorsqu'ils se rencontrent.
- [ ] **Analyseur de Sentiments / d'Intentions :**
  - Un module d'analyse NLP écoute les discussions générées par le LLM et traduit les mots en actions ou en changements de statistiques (ex: l'analyseur détecte une insulte -> l'amitié baisse -> déclenchement d'un combat).
- [ ] **Gestion des Interactions (Jörmungandr) :**
  - Gérer les interactions de manière unilatérale/asymétrique : toutes les interactions entre deux entités (ex. Arbre et Humain) sont définies et gérées au sein d'un seul des deux composants (par exemple, dans l'Humain) pour simplifier le moteur.

## Mécaniques Futures (Post-MVP)
- [ ] **Gestion des Ressources (ex: Manger) :**
  - Sera implémenté ultérieurement.
  - Entièrement dépendant du composant (un humain a besoin de manger, un arbre n'a besoin que d'eau/lumière). Cela sera défini dans la classe Python de chaque composant.

---
*Ce document évoluera au fur et à mesure de nos discussions.*
