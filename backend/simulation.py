import math
import random
from core.scheduler import Scheduler

class Simulation:
    def __init__(self, width=80, height=80, noyade_active=True):
        self.width = width
        self.height = height
        self.scheduler = Scheduler()
        self.noyade_active = noyade_active
        self.grille = [] # 0: Eau, 1: Terre
        self.composants = {} # id -> composant
        self.grille_entites = {} # (x, y) -> composant
        
        self.generer_ile("circular")
        self.generer_cellules_initiales()

    def generer_ile(self, algorithme="circular", python_code=None):
        """Régénère la grille selon l'algorithme choisi."""
        if algorithme == "circular":
            self.generer_ile_circulaire()
        elif algorithme == "organique":
            self.generer_ile_organique()
        elif algorithme == "custom" and python_code:
            self.generate_grid_from_python(python_code)
        else:
            self.generer_ile_circulaire()

    def generer_ile_circulaire(self):
        """Génère une île circulaire simple avec un peu de bruit."""
        self.grille = []
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

    def generer_ile_organique(self):
        """Génère une île de forme organique en utilisant un automate cellulaire."""
        cx, cy = self.width / 2, self.height / 2
        max_dist = math.sqrt(cx**2 + cy**2)
        grid = [[0] * self.width for _ in range(self.height)]
        
        for y in range(self.height):
            for x in range(self.width):
                dist = math.sqrt((x - cx)**2 + (y - cy)**2)
                # Plus on est près du centre, plus on a de chances d'avoir de la terre
                probability = max(0.0, 1.0 - (dist / (max_dist * 0.6)))
                if random.random() < probability * 0.85:
                    grid[y][x] = 1
                    
        # 3 itérations de lissage par automate cellulaire
        for _ in range(3):
            new_grid = [[0] * self.width for _ in range(self.height)]
            for y in range(self.height):
                for x in range(self.width):
                    # Compter les voisins terre dans une fenêtre 3x3
                    terre_count = 0
                    for dy in [-1, 0, 1]:
                        for dx in [-1, 0, 1]:
                            nx, ny = x + dx, y + dy
                            if 0 <= nx < self.width and 0 <= ny < self.height:
                                terre_count += grid[ny][nx]
                    # Règle de lissage (B5678/S45678)
                    if grid[y][x] == 1:
                        new_grid[y][x] = 1 if terre_count >= 4 else 0
                    else:
                        new_grid[y][x] = 1 if terre_count >= 5 else 0
            grid = new_grid
            
        self.grille = grid

    def generate_grid_from_python(self, python_code):
        """Exécute un script Python utilisateur pour générer la grille de l'île."""
        local_scope = {}
        try:
            exec(python_code, {}, local_scope)
        except Exception as e:
            raise ValueError(f"Erreur de syntaxe ou d'exécution dans le script : {e}")
            
        if "generer_grille" not in local_scope:
            raise ValueError("Le script doit définir une fonction nommée 'generer_grille(width, height)'.")
            
        func = local_scope["generer_grille"]
        try:
            grid = func(self.width, self.height)
        except Exception as e:
            raise ValueError(f"Erreur lors de l'exécution de generer_grille : {e}")
            
        # Validation du retour
        if not isinstance(grid, list) or len(grid) != self.height:
            raise ValueError(f"La fonction doit retourner une liste de hauteur {self.height}.")
            
        for y, row in enumerate(grid):
            if not isinstance(row, list) or len(row) != self.width:
                raise ValueError(f"La ligne {y} de la grille retournée doit avoir une longueur de {self.width}.")
            for x, val in enumerate(row):
                # Tenter de convertir en entier (0 ou 1)
                try:
                    int_val = int(val)
                    if int_val not in (0, 1):
                        raise Exception()
                    grid[y][x] = int_val
                except Exception:
                    raise ValueError(f"La valeur à ({x}, {y}) doit être 0 (eau) ou 1 (terre). Reçu: {val}")
                        
        self.grille = grid

    def paint_cell(self, x, y, value, brush_size=1):
        """Modifie manuellement une cellule ou un cercle de cellules (0: eau, 1: terre)."""
        if brush_size <= 1:
            if 0 <= x < self.width and 0 <= y < self.height:
                self.grille[y][x] = 1 if value == 1 else 0
                return True
            return False
        else:
            radius = brush_size - 1
            any_success = False
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if dx * dx + dy * dy <= radius * radius:
                        px, py = x + dx, y + dy
                        if 0 <= px < self.width and 0 <= py < self.height:
                            self.grille[py][px] = 1 if value == 1 else 0
                            any_success = True
            return any_success

    def generer_cellules_initiales(self):
        """Place quelques cellules au centre pour démarrer le jeu."""
        from core.loader import LOADED_CLASSES
        type_id = None
        for k in LOADED_CLASSES.keys():
            if "cellule" in k.lower():
                type_id = k
                break
        if not type_id and LOADED_CLASSES:
            type_id = list(LOADED_CLASSES.keys())[0]
            
        if not type_id:
            return
            
        cx, cy = int(self.width / 2), int(self.height / 2)
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if random.random() > 0.5 and self.is_terre(cx+dx, cy+dy):
                    try:
                        c = self.creer_composant(type_id, cx+dx, cy+dy)
                        self.ajouter_composant(c)
                    except Exception:
                        pass

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
            return True
        return False

    def supprimer_composant_at(self, x, y):
        comp = self.get_composant_at(x, y)
        if comp:
            comp.vivant = False
            if comp.id in self.composants:
                del self.composants[comp.id]
            if (x, y) in self.grille_entites:
                del self.grille_entites[(x, y)]
            return True
        return False

    def creer_composant(self, type_id, x, y, atb_vitesse=None):
        from core.loader import LOADED_CLASSES, METADATA_REGISTRY
        if type_id not in LOADED_CLASSES:
            raise ValueError(f"Composant de type '{type_id}' inconnu.")
        cls = LOADED_CLASSES[type_id]
        
        if atb_vitesse is not None:
            comp = cls(x, y, atb_vitesse=atb_vitesse)
        else:
            comp = cls(x, y)
        comp.type_id = type_id
            
        meta = next((m for m in METADATA_REGISTRY if m["id"] == type_id), None)
        if meta:
            comp.forme = meta.get("forme", getattr(comp, "forme", "carré"))
            comp.coin = meta.get("coin", getattr(comp, "coin", "droit"))
            comp.orientation = meta.get("orientation", getattr(comp, "orientation", "standard"))
            comp.couleur = meta.get("couleur", getattr(comp, "couleur", "#000000"))
            
        return comp

    def nettoyer_morts(self):
        morts = [c for c in self.composants.values() if not c.vivant]
        for c in morts:
            del self.composants[c.id]
            if self.grille_entites.get((c.x, c.y)) == c:
                del self.grille_entites[(c.x, c.y)]

    def tick(self):
        # 1. ATB Scheduler ticks
        self.scheduler.tick(self)
        
        # 2. Gestion de la noyade
        if self.noyade_active:
            for comp in list(self.composants.values()):
                if comp.vivant:
                    if not self.is_terre(comp.x, comp.y):
                        comp.noyade_ticks = getattr(comp, "noyade_ticks", 0) + 1
                        if comp.noyade_ticks >= 3:
                            comp.vivant = False
                    else:
                        comp.noyade_ticks = 0
            self.nettoyer_morts()

    def get_global_stats(self):
        """Retourne des statistiques globales sur la simulation."""
        type_counts = {}
        for c in self.composants.values():
            if c.vivant:
                type_counts[c.type_nom] = type_counts.get(c.type_nom, 0) + 1
                
        total_cells = self.width * self.height
        land_cells = sum(row.count(1) for row in self.grille)
        water_cells = total_cells - land_cells
        
        return {
            "Total d'Entités": len(self.composants),
            "Répartition": type_counts,
            "Terre": f"{land_cells} cases ({land_cells/total_cells*100:.1f}%)",
            "Eau": f"{water_cells} cases ({water_cells/total_cells*100:.1f}%)",
            "Taille de la Grille": f"{self.width}x{self.height}",
        }

    def get_state(self):
        return {
            "tick": self.scheduler.tick_count,
            "width": self.width,
            "height": self.height,
            "grille": self.grille,
            "noyade_active": self.noyade_active,
            "composants": [c.to_dict() for c in self.composants.values()],
            "global_stats": self.get_global_stats()
        }
