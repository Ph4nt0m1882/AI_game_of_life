import uuid

class Composant:
    def __init__(self, x, y, atb_vitesse=10):
        self.id = str(uuid.uuid4())
        self.x = x
        self.y = y
        self.atb_vitesse = atb_vitesse  # Montant d'ATB gagné par tick
        self.atb_actuel = 0
        self.atb_max = 100
        self.vivant = True
        self.type_nom = "Composant"

    def update_atb(self):
        """Ajoute de la vitesse à l'ATB. Retourne True si l'action doit être déclenchée."""
        if not self.vivant:
            return False
            
        self.atb_actuel += self.atb_vitesse
        if self.atb_actuel >= self.atb_max:
            self.atb_actuel = 0  # Reset après action
            return True
        return False

    def action(self, simulation):
        """Méthode à surcharger pour l'action spécifique du composant."""
        pass

    def to_dict(self):
        return {
            "id": self.id,
            "type": self.type_nom,
            "x": self.x,
            "y": self.y,
            "vivant": self.vivant
        }
