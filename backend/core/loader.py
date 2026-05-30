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
    """Initialise les répertoires et charge tous les composants du registre."""
    SETTINGS_FILE = BASE_DIR / "settings.json"
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if "data_dir" in data:
                    global CUSTOM_DIR, EXTRACTED_DIR, REGISTRY_FILE
                    CUSTOM_DIR = Path(data["data_dir"])
                    EXTRACTED_DIR = CUSTOM_DIR / "extracted"
                    REGISTRY_FILE = CUSTOM_DIR / "registry.json"
        except Exception as e:
            print(f"Impossible de charger settings.json: {e}")

    os.makedirs(CUSTOM_DIR, exist_ok=True)
    os.makedirs(EXTRACTED_DIR, exist_ok=True)
    
    if not REGISTRY_FILE.exists():
        with open(REGISTRY_FILE, "w", encoding="utf-8") as f:
            json.dump([], f, indent=4)
    else:
        try:
            with open(REGISTRY_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
                for item in saved:
                    comp_id = item["id"]
                    logic_path = EXTRACTED_DIR / comp_id / "logic.py"
                    if logic_path.exists():
                        try:
                            cls = load_class_from_file(comp_id, logic_path)
                            if cls:
                                LOADED_CLASSES[comp_id] = cls
                                METADATA_REGISTRY.append({
                                    "id": comp_id,
                                    "name": item.get("name", comp_id),
                                    "description": item.get("description", ""),
                                    "atb_vitesse": item.get("atb_vitesse", 10),
                                    "is_builtin": False,
                                    "icon_url": f"/api/components/{comp_id}/icon",
                                    "forme": item.get("forme", "carré"),
                                    "coin": item.get("coin", "droit"),
                                    "orientation": item.get("orientation", "standard"),
                                    "couleur": item.get("couleur", "#000000"),
                                    "interactions": item.get("interactions", {})
                                })
                        except Exception as e:
                            print(f"Erreur lors du chargement de {comp_id}: {e}")
        except Exception as e:
            print(f"Impossible de lire le registre : {e}")

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
            return obj
    return None

def save_to_registry(metadata: dict):
    """Enregistre un composant dans registry.json."""
    saved_components = []
    if REGISTRY_FILE.exists():
        try:
            with open(REGISTRY_FILE, "r", encoding="utf-8") as f:
                saved_components = json.load(f)
        except Exception:
            pass
            
    saved_components = [c for c in saved_components if c["id"] != metadata["id"]]
    saved_components.append(metadata)
    
    with open(REGISTRY_FILE, "w", encoding="utf-8") as f:
        json.dump(saved_components, f, indent=4)

def build_sssub(comp_id: str, name: str, description: str, atb_vitesse: int, logic_code: str, icon_bytes: bytes, interactions: dict, forme: str, coin: str, orientation: str, couleur: str) -> Path:
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
        
    # 3. Écrire manifest.json
    manifest = {
        "id": comp_id,
        "name": name,
        "description": description,
        "atb_vitesse": atb_vitesse,
        "forme": forme,
        "coin": coin,
        "orientation": orientation,
        "couleur": couleur,
        "interactions": interactions
    }
    with open(comp_dir / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=4)
        
    # 4. Créer l'archive zip .sssub
    zip_path = CUSTOM_DIR / f"{comp_id}.sssub"
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        zip_file.write(comp_dir / "logic.py", "logic.py")
        zip_file.write(comp_dir / "icon.png", "icon.png")
        zip_file.write(comp_dir / "manifest.json", "manifest.json")
        
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
        "interactions": interactions
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
        "interactions": interactions
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
            zip_file.extract("icon.png", comp_dir)
            zip_file.extract("manifest.json", comp_dir)
            
            final_zip_path = CUSTOM_DIR / f"{comp_id}.sssub"
            shutil.copyfile(temp_zip_path, final_zip_path)
            
            cls = load_class_from_file(comp_id, comp_dir / "logic.py")
            if cls is None:
                shutil.rmtree(comp_dir, ignore_errors=True)
                if final_zip_path.exists():
                    final_zip_path.unlink()
                raise ValueError("Le fichier logic.py importé ne contient pas de classe valide héritant de Composant.")
                
            LOADED_CLASSES[comp_id] = cls
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
                "interactions": interactions
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
