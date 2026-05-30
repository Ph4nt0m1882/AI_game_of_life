from core.composant import Composant

class Cellule(Composant):
    def __init__(self, x, y, atb_vitesse=100):
        # Les cellules sont très rapides par défaut (100 = agit à chaque tick si max=100)
        super().__init__(x, y, atb_vitesse)
        self.type_nom = "Cellule"

    def action(self, simulation):
        """Application des règles de Conway asynchrones."""
        voisins = simulation.get_voisins(self.x, self.y)
        nb_vivants = sum(1 for v in voisins if isinstance(v, Cellule) and v.vivant)

        # Règle 1: Sous-population ou Surpopulation
        if nb_vivants < 2 or nb_vivants > 3:
            self.vivant = False

        # Règle 2: Reproduction (on regarde les cases vides autour de soi)
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                if dx == 0 and dy == 0:
                    continue
                nx, ny = self.x + dx, self.y + dy
                
                # Vérifier que c'est sur la terre et qu'il n'y a personne
                if simulation.is_terre(nx, ny) and simulation.get_composant_at(nx, ny) is None:
                    # On compte les voisins potentiels de cette case vide
                    voisins_vide = simulation.get_voisins(nx, ny)
                    nb_vivants_autour_vide = sum(1 for v in voisins_vide if isinstance(v, Cellule) and v.vivant)
                    
                    if nb_vivants_autour_vide == 3:
                        # Naissance !
                        nouvelle_cellule = Cellule(nx, ny, self.atb_vitesse)
                        simulation.ajouter_composant(nouvelle_cellule)
