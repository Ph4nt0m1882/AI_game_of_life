import math
import random
from core.scheduler import Scheduler
from composants.cellule import Cellule

class Simulation:
    def __init__(self, width=50, height=50):
        self.width = width
        self.height = height
        self.scheduler = Scheduler()
        self.grille = [] # 0: Eau, 1: Terre
        self.composants = {} # id -> composant
        self.grille_entites = {} # (x, y) -> composant
        
        self.generer_ile()
        self.generer_cellules_initiales()

    def generer_ile(self):
        """Génère une île circulaire avec un peu de bruit."""
        cx, cy = self.width / 2, self.height / 2
        rayon_max = min(self.width, self.height) * 0.4
        
        for y in range(self.height):
            ligne = []
            for x in range(self.width):
                dist = math.sqrt((x - cx)**2 + (y - cy)**2)
                bruit = random.uniform(-3, 3)
                if dist + bruit < rayon_max:
                    ligne.append(1)
                else:
                    ligne.append(0)
            self.grille.append(ligne)

    def generer_cellules_initiales(self):
        """Place quelques cellules au centre pour démarrer le jeu."""
        cx, cy = int(self.width / 2), int(self.height / 2)
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if random.random() > 0.5 and self.is_terre(cx+dx, cy+dy):
                    c = Cellule(cx+dx, cy+dy)
                    self.ajouter_composant(c)

    def is_terre(self, x, y):
        if 0 <= x < self.width and 0 <= y < self.height:
            return self.grille[y][x] == 1
        return False

    def get_composant_at(self, x, y):
        comp = self.grille_entites.get((x, y))
        if comp and comp.vivant:
            return comp
        return None

    def get_voisins(self, x, y):
        voisins = []
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                if dx == 0 and dy == 0:
                    continue
                comp = self.get_composant_at(x + dx, y + dy)
                if comp:
                    voisins.append(comp)
        return voisins

    def ajouter_composant(self, composant):
        if not self.get_composant_at(composant.x, composant.y):
            self.composants[composant.id] = composant
            self.grille_entites[(composant.x, composant.y)] = composant

    def nettoyer_morts(self):
        morts = [c for c in self.composants.values() if not c.vivant]
        for c in morts:
            del self.composants[c.id]
            # Nettoyer la grille spatiale
            if self.grille_entites.get((c.x, c.y)) == c:
                del self.grille_entites[(c.x, c.y)]

    def tick(self):
        self.scheduler.tick(self)

    def get_state(self):
        return {
            "tick": self.scheduler.tick_count,
            "width": self.width,
            "height": self.height,
            "grille": self.grille,
            "composants": [c.to_dict() for c in self.composants.values()]
        }
