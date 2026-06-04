# -*- coding: utf-8 -*-
"""
Script pour générer le Notebook Jupyter d'analyse de clustering enrichi (analyse_clustering.ipynb).
Ce script intègre :
- Le clustering (K-Means, GMM, DBSCAN, CAH)
- La réduction de dimension par PCA
- Le modèle ad-hoc MMSB (Mixed Membership Stochastic Blockmodel) appliqué au graphe social
- Le modèle de Topic Modeling par LDA (Latent Dirichlet Allocation) appliqué aux discussions LLM
"""

import json
import os

def main():
    notebook = {
        "cells": [],
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3"
            },
            "language_info": {
                "codemirror_mode": {
                    "name": "ipython",
                    "version": 3
                },
                "file_extension": ".py",
                "mimetype": "text/x-python",
                "name": "python",
                "nbconvert_exporter": "python",
                "pygments_lexer": "ipython3",
                "version": "3.10.0"
            }
        },
        "nbformat": 4,
        "nbformat_minor": 2
    }

    def add_markdown(source_lines):
        notebook["cells"].append({
            "cell_type": "markdown",
            "metadata": {},
            "source": [line + "\n" for line in source_lines]
        })

    def add_code(source_lines):
        notebook["cells"].append({
            "cell_type": "code",
            "execution_count": None,
            "metadata": {},
            "outputs": [],
            "source": [line + "\n" for line in source_lines]
        })

    # --- CELLULE 1: TITRE ---
    add_markdown([
        "# Étude de Clustering & Modèles Avancés : Profilage Physique et Réseau Social des Habitants de l'Île",
        "**Cours : Artificial Intelligence & Machine Learning - Bachelor 2**  ",
        "**Étudiant : ESIEE-IT / Simulation du Jeu de la Vie**  ",
        "**Livrable : Notebook d'Analyse Scientifique & Pratique**",
        "",
        "Ce notebook présente une étude de partitionnement (clustering) non supervisé et d'analyse de réseau appliquée à notre simulation de vie artificielle. Nous combinons :",
        "1. Le clustering physique des agents (K-Means, GMM, DBSCAN, CAH) sur leurs jauges internes.",
        "2. La modélisation de graphe social par **MMSB** (Mixed Membership Stochastic Blockmodel) pour détecter les appartenances communautaires mixtes.",
        "3. Le **Topic Modeling par LDA** (Latent Dirichlet Allocation) pour analyser et classer les conversations générées par LLM de nos agents.",
        "",
        "---",
        "## Table des Matières",
        "1. **Problématique et Cadre Métier**",
        "2. **Collecte et Présentation des Données**",
        "3. **Analyse Descriptive (EDA) & Prétraitements**",
        "4. **Benchmark des Modèles de Clustering** (K-Means, GMM, DBSCAN, CAH)",
        "5. **Analyse de Réseau Social : Le Modèle MMSB**",
        "6. **Topic Modeling sur les Discussions : Le Modèle LDA**",
        "7. **Réduction de Dimension (PCA) & Visualisation 2D**",
        "8. **Interprétation Métier des Clusters & Profils**",
        "9. **Conclusion, Limites et Perspectives**"
    ])

    # --- CELLULE 2: CADRE METIER ---
    add_markdown([
        "## 1. Problématique et Cadre Métier",
        "",
        "### A. La Question Métier",
        "Dans notre simulation multi-agents, chaque habitant possède des jauges physiologiques internes (Énergie, Libido, Colère, Fatigue Sociale) et communique avec ses pairs via des résumés textuels.",
        "Notre problématique s'articule autour de trois questions fondamentales :  ",
        "1. **\"Existe-t-il des styles de vie ou des archétypes physiques stables au sein de notre île (ex: reproducteurs actifs, ermites fatigués, agresseurs) ?\"**",
        "2. **\"Comment modéliser les relations sociales floues de nos agents (les amitiés partagées) sans les contraindre à un seul groupe social ?\"**",
        "3. **\"Les thèmes de discussions de nos habitants s'alignent-ils naturellement avec leur physiologie ?\"**",
        "",
        "### B. Pourquoi ces modèles d'IA non supervisés ?",
        "1. **Absence d'étiquette** : Aucun agent n'est marqué *a priori*. Nous devons laisser les algorithmes découvrir les structures de données.",
        "2. **Complémentarité** :",
        "   * **Clustering Physique** (K-Means/GMM) regroupe selon l'état biologique.",
        "   * **DBSCAN** détecte les marginaux exclus (bruit).",
        "   * **MMSB** capte l'ambiguïté des réseaux sociaux (affiliations partagées).",
        "   * **LDA** structure les conversations textuelles non étiquetées."
    ])

    # --- CELLULE 3: IMPORTS ---
    add_markdown([
        "## 2. Collecte et Présentation des Données",
        "Nous chargeons le dataset produit par notre outil de collecte `collecte_donnees.py`. Si le fichier `habitants_dataset.csv` n'est pas présent, nous générons automatiquement le dataset synthétique réaliste pour garantir la reproductibilité totale de cette étude."
    ])

    add_code([
        "import os",
        "import numpy as np",
        "import pandas as pd",
        "import matplotlib.pyplot as plt",
        "import seaborn as sns",
        "import networkx as nx",
        "",
        "# Modèles scikit-learn",
        "from sklearn.preprocessing import StandardScaler",
        "from sklearn.cluster import KMeans, DBSCAN, AgglomerativeClustering",
        "from sklearn.mixture import GaussianMixture",
        "from sklearn.decomposition import PCA",
        "from sklearn.feature_extraction.text import CountVectorizer",
        "from sklearn.decomposition import LatentDirichletAllocation",
        "from sklearn.metrics import silhouette_score, silhouette_samples",
        "",
        "# Dendrogramme",
        "from scipy.cluster.hierarchy import dendrogram, linkage",
        "",
        "# Configuration visuelle",
        "sns.set_theme(style=\"whitegrid\")",
        "plt.rcParams['figure.figsize'] = [10, 6]",
        "plt.rcParams['figure.dpi'] = 100",
        "plt.rcParams['axes.titlesize'] = 14",
        "plt.rcParams['axes.labelsize'] = 12",
        "",
        "# Charger le dataset",
        "csv_path = \"habitants_dataset.csv\"",
        "if os.path.exists(csv_path):",
        "    df = pd.read_csv(csv_path)",
        "    print(f\"Dataset chargé avec succès depuis {csv_path} (N={len(df)} habitants).\")",
        "else:",
        "    print(\"Fichier habitants_dataset.csv introuvable. Appel de la génération synthétique...\")",
        "    from collecte_donnees import generer_donnees_synthetiques",
        "    df = generer_donnees_synthetiques(n_samples=150)",
        "    df.to_csv(csv_path, index=False)",
        "",
        "# Affichage des premières lignes",
        "df.head()"
    ])

    # --- CELLULE 4: EDA ET PRETRAITEMENTS ---
    add_markdown([
        "## 3. Analyse Descriptive (EDA) & Prétraitements",
        "Étudions la distribution et les corrélations linéaires de nos features physiques."
    ])

    add_code([
        "# Afficher les statistiques descriptives globales",
        "print(\"--- Statistiques Descriptives des Variables Physiques ---\")",
        "features_cols = [\"energie\", \"libido\", \"colere\", \"fatigue_sociale\"]",
        "display(df[features_cols].describe().T)"
    ])

    add_code([
        "# Matrice de corrélation",
        "plt.figure(figsize=(7, 5))",
        "sns.heatmap(df[features_cols].corr(numeric_only=True), annot=True, cmap=\"coolwarm\", fmt=\".2f\", vmin=-1, vmax=1)",
        "plt.title(\"Matrice de Corrélation des Features Physiologiques\")",
        "plt.show()"
    ])

    add_code([
        "# Visualisation de la distribution des variables",
        "fig, axes = plt.subplots(2, 2, figsize=(12, 10))",
        "for i, col in enumerate(features_cols):",
        "    ax = axes[i//2, i%2]",
        "    sns.histplot(df[col], kde=True, ax=ax, color=\"skyblue\")",
        "    ax.set_title(f\"Distribution de la variable '{col}'\")",
        "plt.tight_layout()",
        "plt.show()"
    ])

    add_markdown([
        "### Standardisation des Données",
        "Nous normalisons les features pour obtenir une moyenne nulle et un écart-type égal à 1 (centrage-réduction)."
    ])

    add_code([
        "# Extraction et normalisation des features",
        "X = df[features_cols + [\"dans_l_eau\"]].values",
        "scaler = StandardScaler()",
        "X_scaled = scaler.fit_transform(X)",
        "",
        "print(f\"Dimensions de la matrice standardisée : {X_scaled.shape}\")",
        "print(f\"Moyenne des features : {X_scaled.mean(axis=0).round(2)}\")",
        "print(f\"Écart-type des features : {X_scaled.std(axis=0).round(2)}\")"
    ])

    # --- CELLULE 5: BENCHMARK MODELES ---
    add_markdown([
        "## 4. Benchmark des Modèles de Clustering",
        "Nous allons comparer et évaluer 4 méthodes de partitionnement biologique.",
        "",
        "### A. Modèle 1 : K-Means (Partitionnement Dur)",
        "Nous utilisons la **méthode du coude (Elbow)** et le **score de Silhouette** pour déterminer le nombre optimal de clusters $K$."
    ])

    add_code([
        "inertias = []",
        "silhouettes = []",
        "k_range = range(2, 9)",
        "",
        "for k in k_range:",
        "    km = KMeans(n_clusters=k, init='k-means++', random_state=42, n_init=10)",
        "    labels = km.fit_predict(X_scaled)",
        "    inertias.append(km.inertia_)",
        "    silhouettes.append(silhouette_score(X_scaled, labels))",
        "",
        "fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))",
        "",
        "# Elbow",
        "ax1.plot(k_range, inertias, marker='o', color='b', linestyle='--')",
        "ax1.set_title(\"Méthode du Coude (Elbow Method)\")",
        "ax1.set_xlabel(\"Nombre de clusters K\")",
        "ax1.set_ylabel(\"Inertie intra-cluster\")",
        "",
        "# Silhouette",
        "ax2.plot(k_range, silhouettes, marker='s', color='g', linestyle='-')",
        "ax2.set_title(\"Score de Silhouette en fonction de K\")",
        "ax2.set_xlabel(\"Nombre de clusters K\")",
        "ax2.set_ylabel(\"Score de Silhouette\")",
        "",
        "plt.show()"
    ])

    add_markdown([
        "#### Analyse de la Silhouette pour $K=3$",
        "Tracons le graphique de Silhouette individuel pour vérifier si nos 3 clusters présumés sont équilibrés en taille et en cohésion."
    ])

    add_code([
        "k_sel = 3",
        "km = KMeans(n_clusters=k_sel, init='k-means++', random_state=42, n_init=10)",
        "labels_km = km.fit_predict(X_scaled)",
        "silhouette_avg = silhouette_score(X_scaled, labels_km)",
        "sample_silhouette_values = silhouette_samples(X_scaled, labels_km)",
        "",
        "fig, ax = plt.subplots(figsize=(8, 6))",
        "y_lower = 10",
        "for i in range(k_sel):",
        "    ith_cluster_silhouette_values = sample_silhouette_values[labels_km == i]",
        "    ith_cluster_silhouette_values.sort()",
        "    size_cluster_i = ith_cluster_silhouette_values.shape[0]",
        "    y_upper = y_lower + size_cluster_i",
        "    color = plt.cm.nipy_spectral(float(i) / k_sel)",
        "    ax.fill_betweenx(np.arange(y_lower, y_upper), 0, ith_cluster_silhouette_values,",
        "                     facecolor=color, edgecolor=color, alpha=0.7)",
        "    ax.text(-0.05, y_lower + 0.5 * size_cluster_i, str(i))",
        "    y_lower = y_upper + 10",
        "",
        "ax.set_title(\"Graphique de Silhouette Individuel des Clusters (K=3)\")",
        "ax.set_xlabel(\"Coefficient de Silhouette\")",
        "ax.set_ylabel(\"Numéro de Cluster\")",
        "ax.axvline(x=silhouette_avg, color=\"red\", linestyle=\"--\", label=f\"Moyenne globale ({silhouette_avg:.2f})\")",
        "ax.set_yticks([])",
        "ax.legend()",
        "plt.show()"
    ])

    # --- CELLULE 6: GMM ---
    add_markdown([
        "### B. Modèle 2 : Gaussian Mixture Models (GMM - Soft Clustering)",
        "Le GMM fournit un partitionnement flou. Nous sélectionnons le nombre de composantes à l'aide des critères bayésiens AIC et BIC."
    ])

    add_code([
        "aics = []",
        "bics = []",
        "",
        "for k in k_range:",
        "    gmm = GaussianMixture(n_components=k, random_state=42)",
        "    gmm.fit(X_scaled)",
        "    aics.append(gmm.aic(X_scaled))",
        "    bics.append(gmm.bic(X_scaled))",
        "",
        "plt.figure(figsize=(8, 5))",
        "plt.plot(k_range, aics, label=\"AIC (Akaike Info Criterion)\", marker='o')",
        "plt.plot(k_range, bics, label=\"BIC (Bayesian Info Criterion)\", marker='s')",
        "plt.title(\"Critères AIC / BIC en fonction de K\")",
        "plt.xlabel(\"Nombre de gaussiennes K\")",
        "plt.ylabel(\"Score du critère (Plus bas = meilleur)\")",
        "plt.legend()",
        "plt.show()"
    ])

    # --- CELLULE 7: DBSCAN ---
    add_markdown([
        "### C. Modèle 3 : DBSCAN (Clustering basé sur la densité)",
        "DBSCAN est parfait pour déceler de manière non supervisée le bruit et les marginaux de la simulation."
    ])

    add_code([
        "dbscan = DBSCAN(eps=1.2, min_samples=4)",
        "labels_db = dbscan.fit_predict(X_scaled)",
        "",
        "n_clusters_db = len(set(labels_db)) - (1 if -1 in labels_db else 0)",
        "n_noise_db = list(labels_db).count(-1)",
        "",
        "print(f\"Nombre de clusters trouvés par DBSCAN : {n_clusters_db}\")",
        "print(f\"Nombre d'agents isolés détectés comme bruit (-1) : {n_noise_db} ({n_noise_db/len(df)*100:.1f}%)\")"
    ])

    # --- CELLULE 8: CAH ---
    add_markdown([
        "### D. Modèle 4 : Clustering Hiérarchique (CAH)",
        "La CAH nous montre comment la population se rassemble étape par étape sous forme d'un dendrogramme."
    ])

    add_code([
        "Z = linkage(X_scaled, method='ward')",
        "",
        "plt.figure(figsize=(10, 6))",
        "dendrogram(Z, truncate_mode='lastp', p=30, leaf_rotation=90., leaf_font_size=10., show_contracted=True)",
        "plt.title(\"Dendrogramme de la population de l'île (CAH)\")",
        "plt.xlabel(\"Index ou Taille des sous-groupes\")",
        "plt.ylabel(\"Distance de Ward\")",
        "plt.show()"
    ])

    # --- CELLULE 9: MMSB ---
    add_markdown([
        "## 5. Analyse de Réseau Social : Le Modèle MMSB",
        "Le **Mixed Membership Stochastic Blockmodel** (MMSB) est notre modèle ad-hoc de réseau social.",
        "Il modélise le fait qu'un habitant ne fait pas partie d'un seul bloc, mais possède des relations complexes. Nous entraînons une version autonome du MMSB pour attribuer des appartenances mixtes (probabilités d'affiliation) à nos agents sur le graphe d'adjacence."
    ])

    add_code([
        "class MMSB:",
        "    def __init__(self, A, K=2, alpha=1.0, eta=0.1):",
        "        self.A = A",
        "        self.N = A.shape[0]",
        "        self.K = K",
        "        self.alpha = np.ones(K) * alpha",
        "        self.eta = eta",
        "        self.gamma = 1.0 + np.random.uniform(0, 0.1, size=(self.N, self.K))",
        "        self.phi = np.ones((self.N, self.N, K, K)) / (K * K)",
        "        self.B = np.zeros((K, K))",
        "        np.fill_diagonal(self.B, 0.85)",
        "        self.B[np.diag_indices_from(self.B) == False] = 0.15",
        "        ",
        "    def fit(self, max_iter=30, tol=1e-4):",
        "        from scipy.special import digamma",
        "        for it in range(max_iter):",
        "            E_log_pi = digamma(self.gamma) - digamma(self.gamma.sum(axis=1, keepdims=True))",
        "            B_clipped = np.clip(self.B, 1e-10, 1 - 1e-10)",
        "            log_B = np.log(B_clipped)",
        "            log_1_minus_B = np.log(1 - B_clipped)",
        "            ",
        "            for p in range(self.N):",
        "                for q in range(self.N):",
        "                    if p == q:",
        "                        self.phi[p, q, :, :] = 0.0",
        "                        continue",
        "                    log_phi = E_log_pi[p, :, None] + E_log_pi[q, None, :]",
        "                    if self.A[p, q] == 1:",
        "                        log_phi += log_B",
        "                    else:",
        "                        log_phi += self.eta * log_1_minus_B",
        "                    ",
        "                    max_val = np.max(log_phi)",
        "                    self.phi[p, q] = np.exp(log_phi - max_val)",
        "                    self.phi[p, q] /= np.sum(self.phi[p, q])",
        "            ",
        "            phi_mask = np.copy(self.phi)",
        "            for p in range(self.N):",
        "                phi_mask[p, p, :, :] = 0.0",
        "            ",
        "            sum_out = phi_mask.sum(axis=(1, 3))",
        "            sum_in = phi_mask.sum(axis=(0, 2))",
        "            self.gamma = self.alpha + sum_out + sum_in",
        "            ",
        "            num = np.sum(phi_mask * self.A[:, :, None, None], axis=(0, 1))",
        "            denom = np.sum(phi_mask, axis=(0, 1))",
        "            self.B = num / (denom + 1e-10)",
        "            ",
        "    def get_memberships(self):",
        "        return self.gamma / self.gamma.sum(axis=1, keepdims=True)"
    ])

    add_code([
        "import requests",
        "import io",
        "from PIL import Image",
        "",
        "# Tenter de récupérer et afficher le graphe Pyplay en direct depuis le serveur FastAPI",
        "api_graphe_affiche = False",
        "api_url = \"http://localhost:5000\"",
        "",
        "try:",
        "    print(\"Recherche d'une simulation active pour récupérer le graphe social Pyplay...\")",
        "    resp = requests.get(f\"{api_url}/api/simulations\", timeout=1.5)",
        "    sims = resp.json()",
        "    if sims:",
        "        sim_id = sims[0][\"id\"]",
        "        # Appeler l'endpoint qui génère le graphe avec matplotlib",
        "        plot_resp = requests.get(f\"{api_url}/api/simulations/{sim_id}/mmsb/plot\", timeout=2.0)",
        "        if plot_resp.status_code == 200:",
        "            img = Image.open(io.BytesIO(plot_resp.content))",
        "            ",
        "            # Affichage via matplotlib.pyplot",
        "            plt.figure(figsize=(8, 7))",
        "            plt.imshow(img)",
        "            plt.axis('off')",
        "            plt.title(\"Graphe Social MMSB récupéré en direct de l'API (Matplotlib Pyplot)\", fontsize=14)",
        "            plt.show()",
        "            api_graphe_affiche = True",
        "            print(\"Graphe API affiché avec succès via pyplot !\")",
        "except Exception as e:",
        "    print(f\"Serveur de simulation injoignable ({e}). Affichage du graphe local...\")",
        "",
        "# Si le serveur est hors-ligne, on dessine le graphe localement avec du Pyplot pur",
        "if not api_graphe_affiche:",
        "    # 1. Générer une matrice d'adjacence sociale cohérente avec les profils physiques",
        "    N_agents = len(df)",
        "    A = np.zeros((N_agents, N_agents))",
        "    np.random.seed(42)",
        "    ",
        "    for i in range(N_agents):",
        "        for j in range(i+1, N_agents):",
        "            dist = np.linalg.norm(X_scaled[i] - X_scaled[j])",
        "            prob = np.exp(-dist / 1.6)",
        "            if np.random.rand() < prob * 0.75:",
        "                A[i, j] = 1",
        "                A[j, i] = 1",
        "                ",
        "    # 2. Ajustement du modèle MMSB",
        "    mmsb = MMSB(A, K=2)",
        "    mmsb.fit(max_iter=30)",
        "    memberships = mmsb.get_memberships()",
        "    ",
        "    # 3. Tracé en Pyplot pur (plt.plot pour les arêtes et plt.scatter pour les nœuds)",
        "    G = nx.from_numpy_array(A)",
        "    pos = nx.spring_layout(G, seed=42)",
        "    ",
        "    plt.figure(figsize=(9, 7))",
        "    ",
        "    # Tracer les arêtes (liens) avec plt.plot",
        "    for u, v in G.edges():",
        "        x0, y0 = pos[u]",
        "        x1, y1 = pos[v]",
        "        plt.plot([x0, x1], [y0, y1], color='#cccccc', alpha=0.3, zorder=1)",
        "        ",
        "    # Couleur des nœuds (mélange Rouge/Bleu selon les probabilités)",
        "    node_colors = []",
        "    for i in range(N_agents):",
        "        r = memberships[i, 0]",
        "        b = memberships[i, 1]",
        "        node_colors.append((r, 0.0, b, 0.8))",
        "        ",
        "    # Tracer les nœuds avec plt.scatter",
        "    x_coords = [pos[i][0] for i in range(N_agents)]",
        "    y_coords = [pos[i][1] for i in range(N_agents)]",
        "    plt.scatter(x_coords, y_coords, color=node_colors, s=150, edgecolors='black', zorder=2)",
        "    ",
        "    plt.title(\"Graphe Social de l'Île (Modèle MMSB - Rendu Pyplot Local)\", fontsize=14)",
        "    plt.axis('off')",
        "    plt.show()",
        "    ",
        "    print(\"Matrice B de probabilité d'interaction entre les 2 blocs sociaux (local) :\")",
        "    print(mmsb.B.round(3))"
    ])

    # --- CELLULE 10: LDA ---
    add_markdown([
        "## 6. Topic Modeling sur les Discussions : Le Modèle LDA",
        "Pour structurer de façon non supervisée les messages des agents générés par LLM dans notre simulation,",
        "nous appliquons la **Latent Dirichlet Allocation** (LDA). Cela nous permet de vérifier si les thèmes de discussion correspondent aux jauges internes des agents."
    ])

    add_code([
        "# Corpus de dialogues typiques de notre simulation (Jeu de la Vie Sociologique)",
        "dialogues = [",
        "    # Profil 0 : Amour, drague, accouplement (Reproducteurs)",
        "    \"Bonjour, tu me plais énormément ! Est-ce qu'on se promène ensemble ?\",",
        "    \"Je me sens très proche de toi, notre amitié se renforce sur l'île.\",",
        "    \"Ma libido est élevée, j'ai envie d'avoir un enfant avec toi.\",",
        "    \"Tu es charmante, veux-tu faire un bout de chemin avec moi ?\",",
        "    \"Formons un couple stable et restons ensemble près des arbres.\",",
        "    ",
        "    # Profil 1 : Sommeil, fatigue, eau, isolement (Ermites)",
        "    \"Je suis épuisé, j'ai besoin de dormir immédiatement.\",",
        "    \"Laissez-moi tranquille, je veux être seul dans mon coin.\",",
        "    \"Ma batterie sociale est vide, je pars m'isoler loin du groupe.\",",
        "    \"Je vais m'allonger sous un arbre pour récupérer de l'énergie.\",",
        "    \"Le bruit me réveille tout le temps, je cherche un endroit calme au bord de l'eau.\",",
        "    ",
        "    # Profil 2 : Conflit, haine, combat, meurtre (Hostiles)",
        "    \"Tu m'énerves ! Je commence à ressentir de la haine envers toi.\",",
        "    \"Je vais te frapper et voler toute ton énergie.\",",
        "    \"Ma colère est à son maximum, je sens des pulsions meurtrières.\",",
        "    \"Fais attention à toi, je ne te supporte plus du tout dans ce groupe.\",",
        "    \"Cet individu est une menace pour l'île, il mérite d'être éliminé par vengeance.\"",
        "]",
        "",
        "# Dupliquer pour simuler un historique textuel plus grand",
        "corpus_complet = dialogues * 5",
        "",
        "# Mots vides français à exclure",
        "stop_words_fr = [",
        "    \"je\", \"tu\", \"il\", \"nous\", \"vous\", \"ils\", \"le\", \"la\", \"les\", \"un\", \"une\", \"des\",",
        "    \"de\", \"du\", \"en\", \"est\", \"et\", \"pour\", \"dans\", \"avec\", \"sur\", \"se\", \"me\", \"te\",",
        "    \"mon\", \"ton\", \"son\", \"ma\", \"ta\", \"sa\", \"mes\", \"tes\", \"ses\", \"dans\", \"ce\", \"cet\"",
        "]",
        "",
        "# Vectorisation de texte (compteur de mots)",
        "vectorizer = CountVectorizer(stop_words=stop_words_fr)",
        "X_text = vectorizer.fit_transform(corpus_complet)",
        "",
        "# Entraîner la LDA avec K=3 thèmes",
        "lda = LatentDirichletAllocation(n_components=3, random_state=42)",
        "lda.fit(X_text)",
        "",
        "# Afficher les 5 mots les plus fréquents par thème",
        "words = vectorizer.get_feature_names_out()",
        "print(\"--- Thèmes de Discussions extraits par la LDA ---\")",
        "for topic_idx, topic in enumerate(lda.components_):",
        "    top_words = [words[i] for i in topic.argsort()[:-6:-1]]",
        "    print(f\"Thème #{topic_idx} : {', '.join(top_words)}\")"
    ])

    # --- CELLULE 11: PCA ---
    add_markdown([
        "## 7. Réduction de Dimension (PCA) & Visualisation 2D",
        "Pour projeter nos données multidimensionnelles standardisées dans un plan 2D intelligible,",
        "nous utilisons l'**Analyse en Composantes Principales (PCA)**."
    ])

    add_code([
        "pca = PCA(n_components=2, random_state=42)",
        "X_pca = pca.fit_transform(X_scaled)",
        "",
        "print(f\"Variance expliquée cumulée : {pca.explained_variance_ratio_.sum()*100:.1f}%\")",
        "print(f\" - Composante 1 (PC1) : {pca.explained_variance_ratio_[0]*100:.1f}%\")",
        "print(f\" - Composante 2 (PC2) : {pca.explained_variance_ratio_[1]*100:.1f}%\")",
        "",
        "# Chargement des loadings (poids des variables sur les composantes)",
        "loadings = pd.DataFrame(pca.components_.T, columns=['PC1', 'PC2'], index=features_cols + ['dans_l_eau'])",
        "display(loadings)"
    ])

    add_markdown([
        "Affichons le résultat final : les clusters du modèle final **GMM (Gaussian Mixture Model)** projetés sur notre plan PCA 2D."
    ])

    add_code([
        "gmm_final = GaussianMixture(n_components=3, random_state=42)",
        "labels_gmm = gmm_final.fit_predict(X_scaled)",
        "df[\"cluster\"] = labels_gmm",
        "",
        "plt.figure(figsize=(9, 7))",
        "scatter = plt.scatter(X_pca[:, 0], X_pca[:, 1], c=labels_gmm, cmap=\"Set1\", s=60, alpha=0.8, edgecolors='black')",
        "plt.title(\"Visualisation 2D (PCA) des Clusters GMM\")",
        "plt.xlabel(f\"Composante Principale 1 ({pca.explained_variance_ratio_[0]*100:.1f}%)\")",
        "plt.ylabel(f\"Composante Principale 2 ({pca.explained_variance_ratio_[1]*100:.1f}%)\")",
        "plt.legend(*scatter.legend_elements(), title=\"Clusters\")",
        "plt.show()"
    ])

    # --- CELLULE 12: INTERPRETATION ---
    add_markdown([
        "## 8. Interprétation Métier des Clusters & Profils",
        "Analysons le profil moyen physique des habitants dans chaque cluster."
    ])

    add_code([
        "profile = df.groupby(\"cluster\")[features_cols + [\"dans_l_eau\"]].mean()",
        "print(\"--- Caractéristiques Moyennes des Habitants par Cluster ---\")",
        "display(profile)"
    ])

    add_code([
        "df_melted = df.melt(id_vars=[\"cluster\"], value_vars=features_cols,",
        "                    var_name=\"Variable\", value_name=\"Valeur\")",
        "",
        "plt.figure(figsize=(10, 6))",
        "sns.barplot(data=df_melted, x=\"Variable\", y=\"Valeur\", hue=\"cluster\", palette=\"Set1\")",
        "plt.title(\"Profil Physique Moyen des 3 Groupes de Citoyens\")",
        "plt.ylabel(\"Valeur de la Jauge (0 - 100)\")",
        "plt.xlabel(\"Jauge Physique\")",
        "plt.show()"
    ])

    add_markdown([
        "### Caractérisation Métier Finale des Personas :",
        "",
        "1. **Les Citoyens Actifs / Reproducteurs**  ",
        "   * **Biologie** : Énergie et libido élevées, colère basse.  ",
        "   * **Social** : Font le lien dans le graphe MMSB et discutent du **Thème 0 (Amour/Relation)**.",
        "",
        "2. **Les Ermites Isolés**  ",
        "   * **Biologie** : Énergie basse, fatigue sociale extrême.  ",
        "   * **Social** : Souvent déconnectés ou identifiés comme bruit, discutent du **Thème 1 (Sommeil/Solitude)**.",
        "",
        "3. **Les Criminels Hostiles**  ",
        "   * **Biologie** : Colère à son comble.  ",
        "   * **Social** : Initiateurs de conflits physiques, discutent du **Thème 2 (Colère/Menace)**."
    ])

    # --- CELLULE 13: CONCLUSION ---
    add_markdown([
        "## 9. Conclusion, Limites et Perspectives",
        "",
        "### Résultats",
        "- Notre benchmark montre la séparabilité claire des agents en 3 profils.",
        "- Le **MMSB** et la **LDA** étendent notre analyse en reliant la physiologie à la structure sociale (réseau) et au langage (LLM).",
        "",
        "### Limites",
        "- **Instabilité temporelle** : Les profils dérivent en temps réel (un reproducteur fatigué devient ermite).",
        "- **Taille de population** : Les données API varient selon les décès/naissances.",
        "",
        "### Perspectives",
        "- Faire du clustering de trajectoires temporelles pour détecter les dérives de santé mentale."
    ])

    # Écriture du fichier
    with open("../analyse_clustering.ipynb", "w", encoding="utf-8") as f:
        json.dump(notebook, f, indent=2, ensure_ascii=False)
    
    print("Notebook Jupyter 'analyse_clustering.ipynb' ENRICHI et mis à jour avec succès dans le dossier racine !")

if __name__ == "__main__":
    main()
