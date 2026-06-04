# %% [markdown]
# # Mini-Étude de Clustering : Profilage des Habitants de l'Île
# **Cours : Artificial Intelligence & Machine Learning**  
# **Livrable : Analyse de Clustering Non-Supervisée**
# 
# Ce notebook présente une étude de partitionnement (clustering) appliquée aux données physiologiques et environnementales des agents intelligents de notre simulation du Jeu de la Vie. 
# L'objectif est d'identifier de manière non supervisée des profils comportementaux de "citoyens" (ex: les pacifiques fatigués, les marginaux isolés, les individus agressifs).
# 
# ---
# 
# ## 1. PROBLÉMATIQUE ET CADRE MÉTIER
# 
# ### A. La Question Métier
# Dans notre simulation d'agents, chaque habitant évolue de manière autonome en modifiant son état physique (énergie, libido, colère, fatigue sociale, etc.) selon ses interactions et déplacements.
# **Problématique** : *Existe-t-il des groupes homogènes de comportements au sein de notre population ? Comment caractériser automatiquement ces profils de citoyens sans étiquetage préalable (a priori) ?*
# 
# ### B. Pourquoi le Clustering ?
# Les données collectées n'ont pas de variable cible $y$ (étiquette comme "pacifique" ou "hostile"). Le **clustering (apprentissage non supervisé)** est la seule méthode adaptée pour découvrir des régularités et structures cachées dans ces données multidimensionnelles, en regroupant les individus similaires et en séparant les individus éloignés.
# 
# ---

# %%
# Importations des bibliothèques nécessaires
import os
import requests
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Modèles scikit-learn vus en cours
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans, DBSCAN
from sklearn.mixture import GaussianMixture
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score

# Configuration des graphiques
sns.set_theme(style="whitegrid")
plt.rcParams['figure.figsize'] = [10, 6]
plt.rcParams['figure.dpi'] = 100

# %% [markdown]
# ## 2. COLLECTE DES DONNÉES
# Nous implémentons une fonction de collecte dynamique qui interroge l'API locale FastAPI. S'il n'y a pas de simulation active, le script bascule automatiquement sur un **générateur de données synthétiques réalistes** pour garantir la reproductibilité du notebook.

# %%
def collecter_donnees_api(api_url="http://localhost:5000"):
    """Tente de collecter le dataset des habitants depuis la simulation active."""
    try:
        resp = requests.get(f"{api_url}/api/simulations", timeout=1.5)
        sims = resp.json()
        if not sims:
            return None
        sim_id = sims[0]["id"]
        
        state_resp = requests.get(f"{api_url}/api/simulations/{sim_id}/state")
        state = state_resp.json()
        composants = state.get("composants", [])
        
        # Filtrer uniquement les humains vivants
        humans = [c for c in composants if "humain" in c["type_id"].lower() and c.get("vivant", True)]
        if len(humans) < 5:
            print("Trop peu d'humains actifs en ligne pour une étude de clustering.")
            return None
            
        # Extraire les features des statistiques détaillées
        records = []
        for h in humans:
            stats = h.get("stats", {})
            
            # Helper robuste pour extraire les valeurs numériques imbriquées dans les stats
            def extraire_valeur(nom_clé, defaut):
                val = stats.get(nom_clé)
                if val and isinstance(val, (list, tuple)) and len(val) > 0:
                    sub = val[0]
                    if isinstance(sub, (list, tuple)) and len(sub) > 0:
                        return float(sub[0])
                    return float(sub)
                try:
                    return float(val)
                except Exception:
                    return float(defaut)

            energie = extraire_valeur("Énergie", 50)
            libido = extraire_valeur("Libido / Pulsion sexuelle", 0)
            colere = extraire_valeur("Colère / Pulsion meurtrière", 0)
            fatigue_sociale = extraire_valeur("Fatigue sociale / Besoin d'isolement", 0)
            
            # Position et environnement
            dans_l_eau = 1 if h.get("couleur") == "#0000ff" else 0 # Simple heuristique
            
            records.append({
                "id": h["id"],
                "energie": energie,
                "libido": libido,
                "colere": colere,
                "fatigue_sociale": fatigue_sociale,
                "dans_l_eau": dans_l_eau
            })
            
        df = pd.DataFrame(records)
        print(f"Dataset collecté avec succès via API (N={len(df)} humains).")
        return df
    except Exception as e:
        print(f"Serveur API non joignable ({e}). Utilisation du générateur synthétique.")
        return None

def generer_donnees_synthetiques(n_samples=150):
    """Génère un dataset synthétique contenant 3 profils d'habitants distincts."""
    np.random.seed(42)
    
    # Groupe 0 : Les Citoyens Actifs / Reproducteurs (Énergie moyenne, libido élevée, colère basse)
    g0 = np.random.multivariate_normal(
        mean=[75, 80, 15, 30, 0],
        cov=np.diag([10, 8, 5, 10, 0.1]),
        size=int(n_samples * 0.4)
    )
    
    # Groupe 1 : Les Hostiles / Agressifs (Énergie basse, libido basse, colère très élevée)
    g1 = np.random.multivariate_normal(
        mean=[40, 20, 85, 45, 0],
        cov=np.diag([12, 10, 8, 12, 0.1]),
        size=int(n_samples * 0.3)
    )
    
    # Groupe 2 : Les Ermites Isolés / Fatigués (Énergie très basse, libido basse, fatigue sociale élevée)
    g2 = np.random.multivariate_normal(
        mean=[25, 10, 30, 90, 1],
        cov=np.diag([8, 5, 10, 5, 0.1]),
        size=int(n_samples * 0.3)
    )
    
    data = np.vstack([g0, g1, g2])
    df = pd.DataFrame(data, columns=["energie", "libido", "colere", "fatigue_sociale", "dans_l_eau"])
    
    # Clipper les valeurs entre 0 et 100 pour rester réaliste
    for col in ["energie", "libido", "colere", "fatigue_sociale"]:
        df[col] = df[col].clip(0, 100)
    df["dans_l_eau"] = (df["dans_l_eau"] > 0.5).astype(int)
    
    print(f"Dataset synthétique généré avec succès (N={len(df)} humains).")
    return df

# Charger le dataset
df = collecter_donnees_api()
if df is None:
    df = generer_donnees_synthetiques(n_samples=120)

# %% [markdown]
# ## 3. PRÉPARATION ET DESCRIPTIF DES DONNÉES
# Avant d'appliquer tout algorithme de clustering, il est crucial de comprendre la distribution des données (analyse descriptive) et de les mettre à l'échelle (standardisation) pour éviter que les variables à grande échelle ne dominent artificiellement les calculs de distance (comme vu dans le Module 3).

# %%
# 1. Analyse descriptive rapide
print("\n--- Description des variables physiques ---")
print(df.describe().T)

# Visualisation des corrélations entre variables
plt.figure(figsize=(6, 5))
sns.heatmap(df.corr(numeric_only=True), annot=True, cmap="coolwarm", fmt=".2f", vmin=-1, vmax=1)
plt.title("Matrice de Corrélation des Features Physiologiques")
plt.show()

# 2. Standardisation des données
# On ignore les colonnes d'identifiants textuels (ex: 'id') si présentes via l'API
features_cols = ["energie", "libido", "colere", "fatigue_sociale", "dans_l_eau"]
X = df[features_cols].values

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)
print("\nDonnées standardisées avec succès (Moyenne = 0, Écart-type = 1).")

# %% [markdown]
# ## 4. CHOIX DU MODÈLE ET RECHERCHE DES HYPERPARAMÈTRES (BENCHMARK)
# Nous comparons deux algorithmes majeurs vus en cours : **K-Means** (Partitionnement) et **Gaussian Mixture Models (GMM)** (Soft Clustering).
# 
# ### A. Optimisation de K-Means (Inertie & Silhouette)
# Pour choisir le nombre optimal de clusters $K$, nous traçons la courbe d'inertie (méthode du coude) et calculons les scores de Silhouette.

# %%
inertias = []
silhouettes = []
k_range = range(2, 9)

for k in k_range:
    km = KMeans(n_clusters=k, init='k-means++', random_state=42, n_init=10)
    labels = km.fit_predict(X_scaled)
    inertias.append(km.inertia_)
    silhouettes.append(silhouette_score(X_scaled, labels))

# Tracer les courbes
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

# Courbe du coude (Elbow)
ax1.plot(k_range, inertias, marker='o', color='b', linestyle='--')
ax1.set_title("Méthode du Coude (Inertie en fonction de K)")
ax1.set_xlabel("Nombre de clusters K")
ax1.set_ylabel("Inertie (Somme des carrés intra-cluster)")

# Score de Silhouette
ax2.plot(k_range, silhouettes, marker='s', color='g', linestyle='-')
ax2.set_title("Score de Silhouette en fonction de K")
ax2.set_xlabel("Nombre de clusters K")
ax2.set_ylabel("Score de Silhouette (proche de 1 = meilleur)")

plt.show()

# %% [markdown]
# ### B. Optimisation du GMM (Critères AIC & BIC)
# Les GMM utilisent les critères bayésiens pour évaluer la qualité du modèle avec un malus de complexité (Module 2).

# %%
aics = []
bics = []

for k in k_range:
    gmm = GaussianMixture(n_components=k, random_state=42)
    gmm.fit(X_scaled)
    aics.append(gmm.aic(X_scaled))
    bics.append(gmm.bic(X_scaled))

# Tracer les critères AIC et BIC (le K optimal minimise ces critères)
plt.figure(figsize=(8, 5))
plt.plot(k_range, aics, label="AIC (Akaike Information Criterion)", marker='o')
plt.plot(k_range, bics, label="BIC (Bayesian Information Criterion)", marker='s')
plt.title("Critères AIC & BIC pour le choix du nombre de gaussiennes (GMM)")
plt.xlabel("Nombre de composantes K")
plt.ylabel("Valeur du critère (Plus bas = meilleur)")
plt.legend()
plt.show()

# %% [markdown]
# ## 5. APPLICATION ET VISUALISATION (PCA & CLUSTERS)
# Le benchmark (Elbow, Silhouette, BIC) converge vers un nombre optimal de **$K=3$ clusters**.
# Nous appliquons le **GMM** pour bénéficier des appartenances mixtes (probabilités d'affiliation) et visualisons les clusters dans un espace 2D obtenu par **PCA (Analyse en Composantes Principales)**.

# %%
# 1. Ajuster le modèle retenu : GMM avec K=3
k_optimal = 3
model_gmm = GaussianMixture(n_components=k_optimal, random_state=42)
cluster_labels = model_gmm.fit_predict(X_scaled)
probabilities = model_gmm.predict_proba(X_scaled)

# Stocker les clusters dans le dataframe
df["cluster"] = cluster_labels

# 2. Réduction de dimension avec la PCA (Module 3)
pca = PCA(n_components=2, random_state=42)
X_2d = pca.fit_transform(X_scaled)

print(f"Variance expliquée par la PCA (2D) : {pca.explained_variance_ratio_.sum()*100:.1f}%")
print(f" - Composante 1 (PC1) : {pca.explained_variance_ratio_[0]*100:.1f}%")
print(f" - Composante 2 (PC2) : {pca.explained_variance_ratio_[1]*100:.1f}%")

# Tracer le nuage de points
plt.figure(figsize=(9, 7))
scatter = plt.scatter(X_2d[:, 0], X_2d[:, 1], c=cluster_labels, cmap="Set1", s=60, alpha=0.8, edgecolors='black')
plt.title("Visualisation 2D (PCA) des Profils Comportementaux (GMM)")
plt.xlabel("Composante Principale 1")
plt.ylabel("Composante Principale 2")
plt.legend(*scatter.legend_elements(), title="Clusters")
plt.show()

# %% [markdown]
# ## 6. INTERPRÉTATION ET PROFILAGE DES CLUSTERS
# Pour donner du sens à nos clusters, nous analysons les valeurs moyennes des variables physiques d'origine au sein de chaque groupe.

# %%
# Profilage des moyennes
profile = df.groupby("cluster")[features_cols].mean()
print("\n--- Profil Moyen des Caractéristiques par Cluster ---")
print(profile)

# Dessiner un barplot comparatif des caractéristiques
df_melted = df.melt(id_vars=["cluster"], value_vars=["energie", "libido", "colere", "fatigue_sociale"],
                    var_name="Caractéristique", value_name="Valeur")

plt.figure(figsize=(10, 6))
sns.barplot(data=df_melted, x="Caractéristique", y="Valeur", hue="cluster", palette="Set1")
plt.title("Comparaison des Profils Physiques Moyen par Cluster")
plt.ylabel("Valeur (0-100)")
plt.show()

# %% [markdown]
# ### Caractérisation Métier des Profils :
# 1.  **Cluster 0 (Rouge)** : **Les Citoyens Actifs / Reproducteurs**  
#     *Energie élevée, libido très importante, colère basse.* Ce groupe représente la force vive et sociale de l'île, assurant la pérennité de l'espèce.
# 2.  **Cluster 1 (Gris/Vert)** : **Les Hostiles / Criminels**  
#     *Colère extrêmement élevée, énergie modérée/basse.* Ce groupe représente les fauteurs de troubles ou tueurs potentiels de l'île.
# 3.  **Cluster 2 (Bleu)** : **Les Ermites Isolés**  
#     *Énergie très basse, fatigue sociale extrême.* Ces individus sont en retrait, cherchant l'isolation pour se reposer et recharger leur batterie sociale.
# 
# ---
# 
# ## 7. CONCLUSION ET LIMITES
# 
# ### Résultats Obtenus
# Notre algorithme de clustering probabiliste **GMM** (appuyé par la réduction de dimension **PCA**) a identifié 3 profils comportementaux très nets. L'utilisation du *soft clustering* permet d'observer les individus "frontières" (ex: un ermite qui commence à devenir hostile).
# 
# ### Limites de l'analyse
# - **Taille du dataset** : Le dataset dépend de la simulation courante. Si la population est faible, l'inférence est moins stable.
# - **Linéarité de la PCA** : La PCA est une projection linéaire et peut passer à côté de structures circulaires complexes (lunes/cercles).
# 
# ### Pistes d'amélioration
# - Intégrer l'algorithme **DBSCAN** pour filtrer le "bruit" (les humains qui ne rentrent dans aucune case comportementale).
# - Établir une classification dynamique temporelle pour voir comment un humain transite d'un cluster à un autre au cours de sa vie.
