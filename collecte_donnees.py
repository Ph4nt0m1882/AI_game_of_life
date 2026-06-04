# -*- coding: utf-8 -*-
"""
Script de collecte des données pour le projet de clustering.
Ce script extrait les données physiques et sociales des habitants (humains)
depuis l'API locale de la simulation active du Jeu de la Vie.
Si l'API n'est pas joignable, il génère un jeu de données synthétique réaliste
conforme aux dynamiques de notre simulation.
"""

import os
import requests
import numpy as np
import pandas as pd

def extraire_valeur(stats, nom_cle, defaut):
    """
    Extrait de manière robuste une valeur numérique depuis le dictionnaire des statistiques.
    Gère les valeurs simples, les listes/tuples imbriqués (ex: ((valeur, max), type)).
    """
    val = stats.get(nom_cle)
    if val is None:
        return float(defaut)
    
    # Si c'est un tuple/liste (ex: ((valeur, max), 'jauge') ou [valeur, max])
    if isinstance(val, (list, tuple)):
        if len(val) > 0:
            sub = val[0]
            if isinstance(sub, (list, tuple)) and len(sub) > 0:
                return float(sub[0])
            return float(sub)
        return float(defaut)
    
    try:
        return float(val)
    except Exception:
        return float(defaut)

def collecter_donnees_api(api_url="http://localhost:5000"):
    """
    Tente de collecter le dataset des habitants depuis la simulation active.
    """
    print(f"Tentative de connexion à l'API de simulation ({api_url})...")
    try:
        resp = requests.get(f"{api_url}/api/simulations", timeout=2.0)
        sims = resp.json()
        if not sims:
            print("Aucune simulation active sur le serveur.")
            return None
        
        sim_id = sims[0]["id"]
        state_resp = requests.get(f"{api_url}/api/simulations/{sim_id}/state")
        state = state_resp.json()
        composants = state.get("composants", [])
        
        # Filtrer uniquement les humains vivants
        humans = [c for c in composants if "humain" in c["type_id"].lower() and c.get("vivant", True)]
        if len(humans) < 5:
            print(f"Trop peu d'humains actifs en ligne ({len(humans)}) pour une étude de clustering.")
            return None
            
        records = []
        for h in humans:
            stats = h.get("stats", {})
            
            # Extraction propre des features
            energie = extraire_valeur(stats, "Énergie", 50.0)
            libido = extraire_valeur(stats, "Libido / Pulsion sexuelle", 0.0)
            colere = extraire_valeur(stats, "Colère / Pulsion meurtrière", 0.0)
            fatigue_sociale = extraire_valeur(stats, "Fatigue sociale / Besoin d'isolement", 0.0)
            
            # Feature binaire simplifiée : l'agent est-il bleu (dans l'eau / nage) ?
            dans_l_eau = 1 if h.get("couleur") == "#0000ff" else 0
            
            records.append({
                "agent_id": h["id"],
                "nom": h.get("nom", f"Agent_{h['id'][:4]}"),
                "energie": energie,
                "libido": libido,
                "colere": colere,
                "fatigue_sociale": fatigue_sociale,
                "dans_l_eau": dans_l_eau
            })
            
        df = pd.DataFrame(records)
        print(f"Succès ! {len(df)} profils d'habitants récupérés via l'API.")
        return df
    except Exception as e:
        print(f"Impossible de contacter l'API ({e}).")
        return None

def generer_donnees_synthetiques(n_samples=150):
    """
    Génère un dataset synthétique contenant 3 profils d'habitants très distincts :
    - Groupe 0 : Les Citoyens Actifs / Reproducteurs (Énergie et Libido élevées)
    - Groupe 1 : Les Criminels Hostiles (Colère extrême, Énergie moyenne)
    - Groupe 2 : Les Ermites Fatigués (Énergie très basse, Fatigue sociale très haute)
    """
    print(f"Génération d'un jeu de données synthétique réaliste (N={n_samples} habitants)...")
    np.random.seed(42)
    
    # 40% de reproducteurs actifs (G0)
    n_g0 = int(n_samples * 0.4)
    g0 = np.random.multivariate_normal(
        mean=[75.0, 80.0, 15.0, 25.0, 0.0],
        cov=np.diag([100.0, 64.0, 25.0, 100.0, 0.1]),
        size=n_g0
    )
    
    # 30% d'individus hostiles / colériques (G1)
    n_g1 = int(n_samples * 0.3)
    g1 = np.random.multivariate_normal(
        mean=[45.0, 20.0, 85.0, 40.0, 0.0],
        cov=np.diag([144.0, 100.0, 64.0, 144.0, 0.1]),
        size=n_g1
    )
    
    # 30% d'ermites isolés / fatigués (G2)
    n_g2 = n_samples - n_g0 - n_g1
    g2 = np.random.multivariate_normal(
        mean=[25.0, 10.0, 30.0, 90.0, 1.0],
        cov=np.diag([64.0, 25.0, 100.0, 25.0, 0.1]),
        size=n_g2
    )
    
    data = np.vstack([g0, g1, g2])
    cols = ["energie", "libido", "colere", "fatigue_sociale", "dans_l_eau"]
    df = pd.DataFrame(data, columns=cols)
    
    # Nettoyage et bornage des features physiques (0 - 100)
    for col in ["energie", "libido", "colere", "fatigue_sociale"]:
        df[col] = df[col].clip(0.0, 100.0).round(1)
        
    # Feature dans_l_eau binarisée (0 ou 1)
    df["dans_l_eau"] = (df["dans_l_eau"] > 0.5).astype(int)
    
    # Ajout d'identifiants
    df.insert(0, "nom", [f"Citoyen_{i+1}" for i in range(n_samples)])
    df.insert(0, "agent_id", [f"uuid_{1000+i}" for i in range(n_samples)])
    
    return df

def main():
    remote = input("adresse du serveur")
    # 1. Tenter la collecte en direct
    df = collecter_donnees_api(remote)
    
    # 2. Repli synthétique si l'API est absente
    if df is None:
        df = generer_donnees_synthetiques(n_samples=150)
        
    # 3. Sauvegarder en CSV
    output_path = "habitants_dataset.csv"
    df.to_csv(output_path, index=False, encoding="utf-8")
    print(f"Jeu de données sauvegardé avec succès dans : {os.path.abspath(output_path)}")
    print(f"\nAperçu du dataset (les 5 premières lignes) :")
    print(df.head())

if __name__ == "__main__":
    main()
