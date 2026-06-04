import os
import sys
import numpy as np
import networkx as nx
from scipy.special import digamma, gammaln
import requests

# -------------------------------------------------------------
# 1. TON IMPLÉMENTATION MMSB (INTÉGRALE ET COMPATIBLE)
# -------------------------------------------------------------
class MMSB:
    def __init__(self, G, K, alpha=1.0, eta=0.1):
        self.N = G.number_of_nodes()
        self.K = K
        # Hyperparamètre du Dirichlet prior alpha
        self.alpha = np.ones(K) * alpha
        self.eta = eta
        
        # Initialisation spectrale pour K=2
        if K == 2:
            try:
                fiedler = nx.fiedler_vector(G)
                self.gamma = np.ones((self.N, K)) * 0.5
                for i in range(self.N):
                    if fiedler[i] > 0:
                        self.gamma[i, 0] = 0.8
                        self.gamma[i, 1] = 0.2
                    else:
                        self.gamma[i, 0] = 0.2
                        self.gamma[i, 1] = 0.8
            except Exception as e:
                # Fallback si le graphe est déconnecté ou s'il y a un problème
                self.gamma = 1.0 + np.random.uniform(0, 0.1, size=(self.N, K))
        else:
            self.gamma = 1.0 + np.random.uniform(0, 0.1, size=(self.N, K))
            
        self.phi = np.ones((self.N, self.N, K, K)) / (K * K)
        
        # Matrice de blocs B (probabilités de connexion inter/intra)
        # Initialisation avec une matrice assortative
        self.B = np.zeros((K, K))
        np.fill_diagonal(self.B, 0.8)
        self.B[np.diag_indices_from(self.B) == False] = 0.1
        
    def fit(self, A, max_iter=100, tol=1e-5):
        elbos = []
        for it in range(max_iter):
            # 1. Étape E : Mise à jour des paramètres variationnels phi et gamma
            E_log_pi = digamma(self.gamma) - digamma(self.gamma.sum(axis=1, keepdims=True))
            
            B_clipped = np.clip(self.B, 1e-10, 1 - 1e-10)
            log_B = np.log(B_clipped)
            log_1_minus_B = np.log(1 - B_clipped)
            
            # Mise à jour de phi (pour chaque paire p != q)
            for p in range(self.N):
                for q in range(self.N):
                    if p == q:
                        self.phi[p, q, :, :] = 0.0
                        continue
                    
                    log_phi = E_log_pi[p, :, None] + E_log_pi[q, None, :]
                    if A[p, q] == 1:
                        log_phi += log_B
                    else:
                        log_phi += self.eta * log_1_minus_B
                    
                    # Softmax stable
                    max_val = np.max(log_phi)
                    self.phi[p, q] = np.exp(log_phi - max_val)
                    self.phi[p, q] /= np.sum(self.phi[p, q])
            
            # Mise à jour de gamma
            phi_mask = np.copy(self.phi)
            for p in range(self.N):
                phi_mask[p, p, :, :] = 0.0
                
            sum_out = phi_mask.sum(axis=(1, 3))
            sum_in = phi_mask.sum(axis=(0, 2))
            
            self.gamma = self.alpha + sum_out + sum_in
            
            # 2. Étape M : Mise à jour de la matrice de blocs B
            num = np.sum(phi_mask * A[:, :, None, None], axis=(0, 1))
            denom = np.sum(phi_mask, axis=(0, 1))
            self.B = num / (denom + 1e-10)
            self.B = np.clip(self.B, 1e-10, 1 - 1e-10)
            
            # Calcul de l'ELBO
            elbo = self._compute_elbo(A, E_log_pi, phi_mask, log_B, log_1_minus_B)
            elbos.append(elbo)
            
            # Test de convergence
            if it > 0 and abs(elbos[-1] - elbos[-2]) < tol:
                print(f"Convergence atteinte à l'itération {it+1}.")
                break
                
        return elbos
        
    def _compute_elbo(self, A, E_log_pi, phi_mask, log_B, log_1_minus_B):
        # E_q[log p(A | z, w, B)] avec pondération eta pour les non-liens
        term_A = np.sum(phi_mask * (A[:, :, None, None] * log_B[None, None, :, :] + self.eta * (1 - A[:, :, None, None]) * log_1_minus_B[None, None, :, :]))
        
        # E_q[log p(z, w | pi)] - E_q[log q(z, w)]
        phi_clipped = np.clip(self.phi, 1e-10, None)
        term_zw = 0.0
        for p in range(self.N):
            for q in range(self.N):
                if p == q:
                    continue
                term_zw += np.sum(phi_mask[p, q] * (E_log_pi[p, :, None] + E_log_pi[q, None, :] - np.log(phi_clipped[p, q])))
                
        # Dirichlet
        term_dir = 0.0
        sum_alpha = np.sum(self.alpha)
        for p in range(self.N):
            sum_gamma = np.sum(self.gamma[p])
            term_dir += (gammaln(sum_alpha) - np.sum(gammaln(self.alpha)) 
                         - gammaln(sum_gamma) + np.sum(gammaln(self.gamma[p])) 
                         + np.sum((self.alpha - self.gamma[p]) * E_log_pi[p]))
                         
        return term_A + term_zw + term_dir

    def get_memberships(self):
        return self.gamma / self.gamma.sum(axis=1, keepdims=True)


# -------------------------------------------------------------
# 2. CHARGEMENT ET PRÉPARATION DES DONNÉES DU GRAPHE
# -------------------------------------------------------------
def recuperer_graphe_simulation(api_url="http://localhost:5000"):
    """Récupère l'état courant de la simulation et construit le graphe de relations."""
    try:
        # 1. Lister les simulations en cours
        resp = requests.get(f"{api_url}/api/simulations", timeout=2.0)
        sims = resp.json()
        if not sims:
            print("Aucune simulation active trouvée sur le serveur.")
            return None
        
        # Prendre la première simulation active
        sim_id = sims[0]["id"]
        
        # 2. Récupérer l'état de cette simulation
        state_resp = requests.get(f"{api_url}/api/simulations/{sim_id}/state")
        state = state_resp.json()
        
        composants = state.get("composants", [])
        humans = [c for c in composants if "humain" in c["type_id"].lower() and c.get("vivant", True)]
        
        if len(humans) < 2:
            print(f"Nombre d'humains insuffisants ({len(humans)}) pour faire du clustering.")
            return None
        
        print(f"Simulation récupérée (ID: {sim_id}, Tick: {state.get('tick')}).")
        print(f"Analyse de {len(humans)} humains vivants...")
        
        # Construire le graphe de relations
        G = nx.Graph()
        labels = {}
        
        for h in humans:
            # Identifiant court et nom complet pour l'affichage
            h_id = h["id"]
            sexe = h.get("icon_variant", "?")
            short_name = f"{sexe}-{h_id[:4]}"
            labels[h_id] = short_name
            G.add_node(h_id, label=short_name)
            
        # Ajouter les arêtes (liens d'amitié réciproques ou unilatéraux > 50)
        for h in humans:
            h_id = h["id"]
            relations = h.get("relations", {})
            for other_id, score in relations.items():
                if other_id in labels and score > 50:
                    # Graphe non dirigé : on ajoute l'arête si elle n'existe pas
                    G.add_edge(h_id, other_id)
                    
        return G
        
    except Exception as e:
        print(f"Impossible de se connecter au serveur backend ({e}).")
        return None


def generer_donnees_synthetiques():
    """Génère un graphe synthétique à deux blocs pour tester le MMSB hors-ligne."""
    print("\n--- Utilisation d'un Graphe Synthétique de Test (K=2) ---")
    G = nx.Graph()
    # Deux groupes distincts de 5 nœuds chacun
    group_A = [f"A{i}" for i in range(5)]
    group_B = [f"B{i}" for i in range(5)]
    
    for n in group_A + group_B:
        G.add_node(n, label=n)
        
    # Liens denses intra-groupe A
    for i in range(len(group_A)):
        for j in range(i+1, len(group_A)):
            G.add_edge(group_A[i], group_A[j])
            
    # Liens denses intra-groupe B
    for i in range(len(group_B)):
        for j in range(i+1, len(group_B)):
            G.add_edge(group_B[i], group_B[j])
            
    # Un nœud 'ambassadeur' ou 'espion' connecté aux deux groupes (appartenance mixte !)
    G.add_node("Espion", label="Espion")
    G.add_edge("Espion", "A0")
    G.add_edge("Espion", "A1")
    G.add_edge("Espion", "B0")
    G.add_edge("Espion", "B1")
    
    return G


# -------------------------------------------------------------
# 3. POINT D'ENTRÉE ET ENTRAÎNEMENT DU MODÈLE
# -------------------------------------------------------------
def main():
    # Tenter de récupérer le graphe de la simulation
    G = recuperer_graphe_simulation()
    
    # Fallback sur les données synthétiques si simulation éteinte
    if G is None:
        G = generer_donnees_synthetiques()
        
    N = G.number_of_nodes()
    A = nx.to_numpy_array(G)
    
    # Nombre de communautés (K=2 par défaut pour l'initialisation spectrale Fiedler)
    K = 2
    
    print(f"\nInitialisation du modèle MMSB pour N={N} nœuds et K={K} groupes...")
    mmsb = MMSB(G, K=K, alpha=0.5, eta=0.05)
    
    print("Entraînement de l'inférence variationnelle (EM)...")
    elbos = mmsb.fit(A, max_iter=80, tol=1e-4)
    
    # Récupérer les memberships
    memberships = mmsb.get_memberships()
    
    print("\n--- RÉSULTATS DES APPARTENANCES SOCIALES (Clustering Mixte) ---")
    node_list = list(G.nodes(data=True))
    for idx, (node_id, data) in enumerate(node_list):
        label = data.get("label", node_id[:6])
        probs = memberships[idx]
        # Formatter l'affichage
        probs_str = " | ".join([f"Groupe {k}: {probs[k]*100:.1f}%" for k in range(K)])
        print(f"Humain {label:<10} -> {probs_str}")
        
    print("\n--- MATRICE DE BLOCS B (Probabilités de connexion) ---")
    print("    " + " ".join([f" Grp{k} " for k in range(K)]))
    for r in range(K):
        row_str = " ".join([f"{mmsb.B[r, c]*100:5.1f}%" for c in range(K)])
        print(f"Grp{r}  {row_str}")
        
    print("\nÉvolution de l'ELBO (Inférence bayésienne) :")
    print([round(e, 2) for e in elbos[:10]], "... final:", round(elbos[-1], 2))


if __name__ == "__main__":
    main()
