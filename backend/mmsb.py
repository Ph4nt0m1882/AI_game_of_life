import numpy as np
import networkx as nx
from scipy.special import digamma, gammaln

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
