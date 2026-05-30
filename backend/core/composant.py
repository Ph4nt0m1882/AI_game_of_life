import uuid

class Composant:
    def __init__(self, x, y, atb_vitesse=10):
        self.id = str(uuid.uuid4())
        self.type_id = getattr(self.__class__, "type_id", None)
        self.x = x
        self.y = y
        self.atb_vitesse = atb_vitesse  # Montant d'ATB gagné par tick
        self.atb_actuel = 0
        self.atb_max = 100
        self.vivant = True
        self.type_nom = "Composant"
        self.couleur = "#000000"  # Noir par défaut, format hexadécimal
        self.forme = "carré"  # carré, carré_arrondi, cercle, triangle, triangle_inverse

    def update_atb(self):
        """Ajoute de la vitesse à l'ATB. Retourne True si l'action doit être déclenchée."""
        if not self.vivant:
            return False
            
        # Si le composant a agi au tick précédent (atb >= max), on réinitialise à 0
        if self.atb_actuel >= self.atb_max:
            self.atb_actuel = 0
            
        self.atb_actuel += self.atb_vitesse
        if self.atb_actuel >= self.atb_max:
            return True
        return False

    def stats(self):
        """Retourne un dictionnaire de statistiques spécifiques à ce composant."""
        return {
            "Vitesse ATB": (self.atb_vitesse, 'int'),
            "ATB Accumulé": ((self.atb_actuel, self.atb_max), 'progress_bar'),
            "Position": (f"({self.x}, {self.y})", 'position'),
        }

    def to_dict(self):
        # Récupération dynamique des statistiques du composant
        stats_data = {}
        if hasattr(self, "stats"):
            try:
                stats_data = self.stats()
            except Exception as e:
                stats_data = {"Erreur": str(e)}
        return {
            "id": self.id,
            "type_id": self.type_id,
            "type": self.type_nom,
            "x": self.x,
            "y": self.y,
            "vivant": self.vivant,
            "couleur": self.couleur,
            "forme": self.forme,
            "stats": stats_data
        }

