import os
import sys
import json
import zipfile
import shutil
import importlib.util
from pathlib import Path
from core.composant import Composant

BASE_DIR = Path(__file__).resolve().parent.parent
CUSTOM_DIR = BASE_DIR / "custom_components"
EXTRACTED_DIR = CUSTOM_DIR / "extracted"
REGISTRY_FILE = CUSTOM_DIR / "registry.json"

# Global dictionary to map component ID to its actual Python class
LOADED_CLASSES = {}

# In-memory registry list of component metadata
METADATA_REGISTRY = []


def init_loader():
    """Initialise les répertoires et effectue un scan des composants .sssub réels."""
    global CUSTOM_DIR, EXTRACTED_DIR
    CUSTOM_DIR = BASE_DIR / "custom_components"
    EXTRACTED_DIR = CUSTOM_DIR / "extracted"

    os.makedirs(CUSTOM_DIR, exist_ok=True)
    os.makedirs(EXTRACTED_DIR, exist_ok=True)
    
    # Nettoyer les anciens fichiers sssub pour démarrer de façon totalement stateless
    try:
        for item in os.listdir(CUSTOM_DIR):
            item_path = CUSTOM_DIR / item
            if item_path.is_file() and item.endswith(".sssub"):
                item_path.unlink()
    except Exception:
        pass

    # Scanner le répertoire CUSTOM_DIR pour trouver les .sssub réels
    scan_custom_components()

def scan_custom_components():
    """Scanne le dossier CUSTOM_DIR, lit les manifestes des fichiers .sssub réels et met à jour le registre."""
    global METADATA_REGISTRY
    METADATA_REGISTRY = []
    
    if not CUSTOM_DIR.exists():
        return
        
    found_ids = set()
    for item in os.listdir(CUSTOM_DIR):
        if item.endswith(".sssub"):
            comp_id = item[:-6]
            found_ids.add(comp_id)
            zip_path = CUSTOM_DIR / item
            try:
                with zipfile.ZipFile(zip_path, 'r') as zip_file:
                    if "manifest.json" in zip_file.namelist():
                        with zip_file.open("manifest.json") as mf:
                            manifest = json.load(mf)
                            
                        has_icon_m = "icon_M.png" in zip_file.namelist()
                        has_icon_f = "icon_F.png" in zip_file.namelist()
                        
                        METADATA_REGISTRY.append({
                            "id": comp_id,
                            "name": manifest.get("name", comp_id),
                            "description": manifest.get("description", ""),
                            "atb_vitesse": manifest.get("atb_vitesse", 10),
                            "is_builtin": False,
                            "icon_url": f"/api/components/{comp_id}/icon",
                            "forme": manifest.get("forme", "carré"),
                            "coin": manifest.get("coin", "droit"),
                            "orientation": manifest.get("orientation", "standard"),
                            "couleur": manifest.get("couleur", "#000000"),
                            "interactions": manifest.get("interactions", {}),
                            "has_icon_m": has_icon_m,
                            "has_icon_f": has_icon_f
                        })
            except Exception as e:
                print(f"Erreur lors de la lecture de {item}: {e}")

    # Nettoyage automatique des répertoires extraits orphelins
    if EXTRACTED_DIR.exists():
        for sub_dir_name in os.listdir(EXTRACTED_DIR):
            sub_dir_path = EXTRACTED_DIR / sub_dir_name
            if sub_dir_path.is_dir() and sub_dir_name not in found_ids:
                try:
                    shutil.rmtree(sub_dir_path, ignore_errors=True)
                    # Supprimer aussi de LOADED_CLASSES
                    LOADED_CLASSES.pop(sub_dir_name, None)
                except Exception:
                    pass

def load_component_class(comp_id: str):
    """Extrait logic.py et charge la classe en mémoire depuis l'archive .sssub si nécessaire."""
    if comp_id in LOADED_CLASSES:
        return LOADED_CLASSES[comp_id]
        
    zip_path = CUSTOM_DIR / f"{comp_id}.sssub"
    if not zip_path.exists():
        raise ValueError(f"L'archive {comp_id}.sssub n'existe pas dans le dossier de travail.")
        
    comp_dir = EXTRACTED_DIR / comp_id
    os.makedirs(comp_dir, exist_ok=True)
    
    with zipfile.ZipFile(zip_path, 'r') as zip_file:
        zip_file.extract("logic.py", comp_dir)
        zip_file.extract("manifest.json", comp_dir)
        for f_name in zip_file.namelist():
            if f_name.startswith("icon") and f_name.endswith(".png"):
                zip_file.extract(f_name, comp_dir)
                
    cls = load_class_from_file(comp_id, comp_dir / "logic.py")
    if cls is None:
        raise ValueError(f"Le fichier logic.py de {comp_id} ne contient pas de classe valide.")
        
    LOADED_CLASSES[comp_id] = cls
    return cls

def load_class_from_file(comp_id: str, file_path: Path):
    """Charge une classe héritant de Composant depuis un fichier logic.py."""
    module_name = f"custom_component_{comp_id}"
    spec = importlib.util.spec_from_file_location(module_name, str(file_path))
    if spec is None or spec.loader is None:
        return None
    
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    
    for name in dir(module):
        obj = getattr(module, name)
        if isinstance(obj, type) and issubclass(obj, Composant) and obj is not Composant:
            obj.type_id = comp_id
            return obj
    return None

def save_to_registry(metadata: dict):
    """Enregistre un composant (sans effet car le registre est dynamique)."""
    pass

def build_sssub(comp_id: str, name: str, description: str, atb_vitesse: int, logic_code: str, icon_bytes: bytes, interactions: dict, forme: str, coin: str, orientation: str, couleur: str, icon_m_bytes: bytes = None, icon_f_bytes: bytes = None) -> Path:
    """
    Génère les fichiers manifest, logic et icon, extrait le composant,
    crée l'archive .sssub et recharge la classe dans le moteur.
    """
    comp_dir = EXTRACTED_DIR / comp_id
    os.makedirs(comp_dir, exist_ok=True)
    
    # 1. Écrire logic.py
    with open(comp_dir / "logic.py", "w", encoding="utf-8") as f:
        f.write(logic_code)
        
    # 2. Écrire icon.png
    with open(comp_dir / "icon.png", "wb") as f:
        f.write(icon_bytes)

    # Écrire les icônes de variantes si fournies
    if icon_m_bytes:
        with open(comp_dir / "icon_M.png", "wb") as f:
            f.write(icon_m_bytes)
    if icon_f_bytes:
        with open(comp_dir / "icon_F.png", "wb") as f:
            f.write(icon_f_bytes)
        
    # 3. Écrire manifest.json
    has_icon_m = (comp_dir / "icon_M.png").exists()
    has_icon_f = (comp_dir / "icon_F.png").exists()
    
    manifest = {
        "id": comp_id,
        "name": name,
        "description": description,
        "atb_vitesse": atb_vitesse,
        "forme": forme,
        "coin": coin,
        "orientation": orientation,
        "couleur": couleur,
        "interactions": interactions,
        "has_icon_m": has_icon_m,
        "has_icon_f": has_icon_f
    }
    with open(comp_dir / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=4)
        
    # 4. Créer l'archive zip .sssub
    zip_path = CUSTOM_DIR / f"{comp_id}.sssub"
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        zip_file.write(comp_dir / "logic.py", "logic.py")
        zip_file.write(comp_dir / "manifest.json", "manifest.json")
        for f_name in os.listdir(comp_dir):
            if f_name.startswith("icon") and f_name.endswith(".png"):
                zip_file.write(comp_dir / f_name, f_name)
        
    # 5. Charger la classe en mémoire
    cls = load_class_from_file(comp_id, comp_dir / "logic.py")
    if cls is None:
        shutil.rmtree(comp_dir, ignore_errors=True)
        if zip_path.exists():
            zip_path.unlink()
        raise ValueError("Le fichier logic.py ne contient pas de classe valide héritant de Composant.")
        
    LOADED_CLASSES[comp_id] = cls
    
    # 6. Mettre à jour le registre
    metadata = {
        "id": comp_id,
        "name": name,
        "description": description,
        "atb_vitesse": atb_vitesse,
        "forme": forme,
        "coin": coin,
        "orientation": orientation,
        "couleur": couleur,
        "interactions": interactions,
        "has_icon_m": has_icon_m,
        "has_icon_f": has_icon_f
    }
    save_to_registry(metadata)
    
    global METADATA_REGISTRY
    METADATA_REGISTRY = [m for m in METADATA_REGISTRY if m["id"] != comp_id]
    METADATA_REGISTRY.append({
        "id": comp_id,
        "name": name,
        "description": description,
        "atb_vitesse": atb_vitesse,
        "is_builtin": False,
        "icon_url": f"/api/components/{comp_id}/icon",
        "forme": forme,
        "coin": coin,
        "orientation": orientation,
        "couleur": couleur,
        "interactions": interactions,
        "has_icon_m": has_icon_m,
        "has_icon_f": has_icon_f
    })
    
    return zip_path

def import_sssub(zip_bytes: bytes) -> dict:
    """Importe un fichier .sssub existant, l'extrait, l'enregistre et le charge."""
    temp_zip_path = CUSTOM_DIR / "temp_import.zip"
    with open(temp_zip_path, "wb") as f:
        f.write(zip_bytes)
        
    try:
        with zipfile.ZipFile(temp_zip_path, 'r') as zip_file:
            file_list = zip_file.namelist()
            if "manifest.json" not in file_list or "logic.py" not in file_list or "icon.png" not in file_list:
                raise ValueError("L'archive .sssub doit contenir manifest.json, logic.py, et icon.png")
                
            with zip_file.open("manifest.json") as mf:
                manifest = json.load(mf)
                
            comp_id = manifest.get("id")
            name = manifest.get("name")
            description = manifest.get("description", "")
            atb_vitesse = manifest.get("atb_vitesse", 10)
            forme = manifest.get("forme", "carré")
            coin = manifest.get("coin", "droit")
            orientation = manifest.get("orientation", "standard")
            couleur = manifest.get("couleur", "#000000")
            interactions = manifest.get("interactions", {})
            
            if not comp_id or not name:
                raise ValueError("Le manifest doit contenir un 'id' et un 'name'")
                
            comp_dir = EXTRACTED_DIR / comp_id
            os.makedirs(comp_dir, exist_ok=True)
            
            zip_file.extract("logic.py", comp_dir)
            zip_file.extract("manifest.json", comp_dir)
            
            for f_name in file_list:
                if f_name.startswith("icon") and f_name.endswith(".png"):
                    zip_file.extract(f_name, comp_dir)
            
            final_zip_path = CUSTOM_DIR / f"{comp_id}.sssub"
            shutil.copyfile(temp_zip_path, final_zip_path)
            
            cls = load_class_from_file(comp_id, comp_dir / "logic.py")
            if cls is None:
                shutil.rmtree(comp_dir, ignore_errors=True)
                if final_zip_path.exists():
                    final_zip_path.unlink()
                raise ValueError("Le fichier logic.py importé ne contient pas de classe valide héritant de Composant.")
                
            LOADED_CLASSES[comp_id] = cls
            
            has_icon_m = (comp_dir / "icon_M.png").exists()
            has_icon_f = (comp_dir / "icon_F.png").exists()
            manifest["has_icon_m"] = has_icon_m
            manifest["has_icon_f"] = has_icon_f
            
            save_to_registry(manifest)
            
            global METADATA_REGISTRY
            METADATA_REGISTRY = [m for m in METADATA_REGISTRY if m["id"] != comp_id]
            METADATA_REGISTRY.append({
                "id": comp_id,
                "name": name,
                "description": description,
                "atb_vitesse": atb_vitesse,
                "is_builtin": False,
                "icon_url": f"/api/components/{comp_id}/icon",
                "forme": forme,
                "coin": coin,
                "orientation": orientation,
                "couleur": couleur,
                "interactions": interactions,
                "has_icon_m": has_icon_m,
                "has_icon_f": has_icon_f
            })
            
            return manifest
    finally:
        if temp_zip_path.exists():
            temp_zip_path.unlink()


def save_settings_dir(data_dir: str):
    """Met à jour le dossier de travail personnalisé et le sauvegarde."""
    SETTINGS_FILE = BASE_DIR / "settings.json"
    try:
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump({"data_dir": data_dir}, f, indent=4)
            
        global CUSTOM_DIR, EXTRACTED_DIR, REGISTRY_FILE
        CUSTOM_DIR = Path(data_dir)
        EXTRACTED_DIR = CUSTOM_DIR / "extracted"
        REGISTRY_FILE = CUSTOM_DIR / "registry.json"
        
        LOADED_CLASSES.clear()
        METADATA_REGISTRY.clear()
        init_loader()
    except Exception as e:
        raise ValueError(f"Impossible d'enregistrer le dossier de travail : {e}")
