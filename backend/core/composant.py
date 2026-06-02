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
        self.coin = "droit"
        self.orientation = "standard"
        
        # Charger les métadonnées depuis le registre
        if self.type_id:
            try:
                from core.loader import METADATA_REGISTRY
                meta = next((m for m in METADATA_REGISTRY if m["id"] == self.type_id), None)
                if meta:
                    self.type_nom = meta.get("name", self.type_nom)
                    self.forme = meta.get("forme", self.forme)
                    self.couleur = meta.get("couleur", self.couleur)
                    self.coin = meta.get("coin", self.coin)
                    self.orientation = meta.get("orientation", self.orientation)
                    if atb_vitesse == 10:
                        self.atb_vitesse = meta.get("atb_vitesse", atb_vitesse)
            except Exception:
                pass

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
                
        # Détection dynamique d'une variante d'icône (ex: sexe)
        icon_variant = None
        if hasattr(self, "sexe"):
            icon_variant = str(self.sexe)
        elif hasattr(self, "variant"):
            icon_variant = str(self.variant)
            
        return {
            "id": self.id,
            "type_id": self.type_id,
            "type": self.type_nom,
            "x": self.x,
            "y": self.y,
            "vivant": self.vivant,
            "couleur": self.couleur,
            "forme": self.forme,
            "stats": stats_data,
            "icon_variant": icon_variant,
            "relations": getattr(self, "relations", {})
        }

