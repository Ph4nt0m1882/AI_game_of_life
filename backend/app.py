import asyncio
import uuid
import json
import os
from dotenv import load_dotenv
from typing import Optional, Dict, Any
import core.loader
from fastapi import FastAPI, HTTPException, Form, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from simulation import Simulation
import uvicorn
from core.loader import init_loader, build_sssub, import_sssub, save_settings_dir

load_dotenv()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Stockage des simulations (ID -> { "sim": Simulation, "is_running": bool })
simulations = {}

class AddComponentRequest(BaseModel):
    type_id: str
    x: int
    y: int

class SettingsRequest(BaseModel):
    data_dir: str

class PaintCellRequest(BaseModel):
    x: int
    y: int
    value: int
    brush_size: int = 1

class GenerateMapRequest(BaseModel):
    algorithm: str
    python_code: str = ""

class SimulationSettingsRequest(BaseModel):
    noyade_active: bool
    speed_factor: float = 1.0
    gemini_api_key: str = ""



async def simulation_loop():
    import time
    last_time = time.perf_counter()
    while True:
        await asyncio.sleep(0.005) # 5ms precision sleep
        now = time.perf_counter()
        dt = now - last_time
        last_time = now
        
        for sim_id, sim_data in list(simulations.items()):
            if sim_data["is_running"]:
                speed = sim_data.get("speed_factor", 1.0)
                # 1.0 speed = 30 ticks per second, meaning 1 tick every 0.03333 seconds
                tick_interval = 0.03333 / speed
                
                accumulated = sim_data.get("accumulated_time", 0.0) + dt
                ticks_to_run = int(accumulated // tick_interval)
                sim_data["accumulated_time"] = accumulated % tick_interval
                
                for _ in range(min(ticks_to_run, 20)): # Cap at 20 ticks per loop to prevent lockup
                    sim_data["sim"].tick()

@app.on_event("startup")
async def startup_event():
    init_loader()
    asyncio.create_task(simulation_loop())

@app.post("/api/simulations")
def create_new_sim():
    sim_id = str(uuid.uuid4())[:8] # Un petit ID lisible
    # On augmente la taille par défaut pour éviter le blocage trop rapide (ex: 80x80)
    simulations[sim_id] = {
        "sim": Simulation(width=80, height=80),
        "is_running": False,
        "speed_factor": 1.0,
        "accumulated_time": 0.0
    }
    return {"sim_id": sim_id}

@app.get("/api/simulations")
def list_sims():
    return [{"id": k, "is_running": v["is_running"], "speed_factor": v.get("speed_factor", 1.0)} for k, v in simulations.items()]

@app.get("/api/simulations/{sim_id}/state")
def get_state(sim_id: str):
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    return simulations[sim_id]["sim"].get_state()

@app.post("/api/simulations/{sim_id}/start")
def start_sim(sim_id: str):
    if sim_id in simulations:
        simulations[sim_id]["is_running"] = True
        return {"status": "started"}
    raise HTTPException(status_code=404)

@app.post("/api/simulations/{sim_id}/stop")
def stop_sim(sim_id: str):
    if sim_id in simulations:
        simulations[sim_id]["is_running"] = False
        return {"status": "stopped"}
    raise HTTPException(status_code=404)

# ==================== NOUVELLES ROUTES POUR COMPOSANTS ====================

@app.get("/api/components")
def get_components():
    """Retourne la liste de tous les composants enregistrés après rescan dynamique."""
    core.loader.scan_custom_components()
    return core.loader.METADATA_REGISTRY

@app.get("/api/components/{comp_id}/icon")
def get_component_icon(comp_id: str, variant: Optional[str] = None):
    """Sert l'icône directement depuis le fichier .sssub du workspace (Thumbnail Provider)."""
    import zipfile
    import io
    from fastapi.responses import StreamingResponse
    
    zip_path = core.loader.CUSTOM_DIR / f"{comp_id}.sssub"
    if not zip_path.exists():
        raise HTTPException(status_code=404, detail="Composant non trouvé")
        
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_file:
            namelist = zip_file.namelist()
            icon_name = "icon.png"
            if variant:
                clean_variant = "".join(c for c in variant if c.isalnum() or c in ("_", "-")).strip()
                v_name = f"icon_{clean_variant}.png"
                if v_name in namelist:
                    icon_name = v_name
                    
            if icon_name in namelist:
                with zip_file.open(icon_name) as f:
                    return StreamingResponse(io.BytesIO(f.read()), media_type="image/png")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur de lecture de l'icône : {str(e)}")
        
    raise HTTPException(status_code=404, detail="Icône non trouvée")

@app.post("/api/components/build")
async def build_component(
    name: str = Form(...),
    description: str = Form(""),
    atb_vitesse: int = Form(10),
    logic_py: str = Form(...),
    interactions: str = Form("{}"),
    forme: str = Form("carré"),
    coin: str = Form("droit"),
    orientation: str = Form("standard"),
    couleur: str = Form("#000000"),
    icon: Optional[UploadFile] = File(None),
    icon_m: Optional[UploadFile] = File(None),
    icon_f: Optional[UploadFile] = File(None),
    comp_id: Optional[str] = Form(None)
):
    """Crée ou met à jour un composant à partir des champs du Component Maker et l'enregistre."""
    try:
        icon_bytes = b""
        if icon is not None:
            icon_bytes = await icon.read()
        elif comp_id:
            # Récupérer l'icône existante du composant
            icon_path = core.loader.EXTRACTED_DIR / comp_id / "icon.png"
            if icon_path.exists():
                with open(icon_path, "rb") as f:
                    icon_bytes = f.read()
                    
        if not icon_bytes:
            raise ValueError("Une icône PNG est requise pour créer ou modifier ce composant.")
            
        icon_m_bytes = b""
        if icon_m is not None:
            icon_m_bytes = await icon_m.read()
        elif comp_id:
            icon_m_path = core.loader.EXTRACTED_DIR / comp_id / "icon_M.png"
            if icon_m_path.exists():
                with open(icon_m_path, "rb") as f:
                    icon_m_bytes = f.read()

        icon_f_bytes = b""
        if icon_f is not None:
            icon_f_bytes = await icon_f.read()
        elif comp_id:
            icon_f_path = core.loader.EXTRACTED_DIR / comp_id / "icon_F.png"
            if icon_f_path.exists():
                with open(icon_f_path, "rb") as f:
                    icon_f_bytes = f.read()

        # Si un comp_id est fourni, on l'utilise pour écraser, sinon on en génère un nouveau
        if comp_id:
            target_comp_id = comp_id
        else:
            # Nettoyer le nom pour l'ID
            clean_name = "".join(c for c in name if c.isalnum() or c in (" ", "_", "-")).strip()
            target_comp_id = f"{clean_name.lower().replace(' ', '_')}_{uuid.uuid4().hex[:8]}"
            
        try:
            interactions_dict = json.loads(interactions)
        except Exception:
            interactions_dict = {}
            
        zip_path = build_sssub(
            comp_id=target_comp_id,
            name=name,
            description=description,
            atb_vitesse=atb_vitesse,
            logic_code=logic_py,
            icon_bytes=icon_bytes,
            interactions=interactions_dict,
            forme=forme,
            coin=coin,
            orientation=orientation,
            couleur=couleur,
            icon_m_bytes=icon_m_bytes if icon_m_bytes else None,
            icon_f_bytes=icon_f_bytes if icon_f_bytes else None
        )
        
        import base64
        import shutil
        
        zip_base64 = ""
        if zip_path.exists():
            with open(zip_path, "rb") as f:
                zip_base64 = base64.b64encode(f.read()).decode("utf-8")
            try:
                zip_path.unlink()
            except Exception:
                pass
                
        # Supprimer le dossier extrait temporaire pour rester complètement stateless
        comp_dir = core.loader.EXTRACTED_DIR / target_comp_id
        if comp_dir.exists():
            shutil.rmtree(comp_dir, ignore_errors=True)
            
        # Retirer de LOADED_CLASSES pour rester stateless
        core.loader.LOADED_CLASSES.pop(target_comp_id, None)
        
        # Mettre à jour le registre en mémoire du serveur pour enlever le composant qui vient d'être supprimé du disque
        core.loader.METADATA_REGISTRY = [m for m in core.loader.METADATA_REGISTRY if m["id"] != target_comp_id]
        
        return {"status": "success", "id": target_comp_id, "zip_base64": zip_base64}
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur interne : {str(e)}")

@app.post("/api/components/upload")
async def upload_component(file: UploadFile = File(...)):
    """Importe manuellement un fichier .sssub."""
    if not file.filename.endswith(".sssub"):
        raise HTTPException(status_code=400, detail="Le fichier doit avoir l'extension .sssub")
    try:
        file_bytes = await file.read()
        manifest = import_sssub(file_bytes)
        
        # Extraire le code logic.py et les icônes en base64 pour renvoi à l'éditeur
        import io
        import zipfile
        import base64
        logic_py = ""
        icon_base64 = ""
        icon_m_base64 = ""
        icon_f_base64 = ""
        try:
            with zipfile.ZipFile(io.BytesIO(file_bytes), 'r') as zip_file:
                namelist = zip_file.namelist()
                if "logic.py" in namelist:
                    with zip_file.open("logic.py") as lf:
                        logic_py = lf.read().decode("utf-8", errors="ignore")
                if "icon.png" in namelist:
                    with zip_file.open("icon.png") as imgf:
                        icon_base64 = base64.b64encode(imgf.read()).decode("utf-8")
                if "icon_M.png" in namelist:
                    with zip_file.open("icon_M.png") as imgf:
                        icon_m_base64 = base64.b64encode(imgf.read()).decode("utf-8")
                if "icon_F.png" in namelist:
                    with zip_file.open("icon_F.png") as imgf:
                        icon_f_base64 = base64.b64encode(imgf.read()).decode("utf-8")
        except Exception:
            pass  # Si l'extraction échoue, on renvoie les chaînes vides
            
        return {
            "status": "success",
            "metadata": manifest,
            "logic_py": logic_py,
            "icon_base64": icon_base64,
            "icon_m_base64": icon_m_base64,
            "icon_f_base64": icon_f_base64
        }
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur lors de l'importation : {str(e)}")

@app.post("/api/simulations/{sim_id}/components")
def add_component_to_sim(sim_id: str, req: AddComponentRequest):
    """Ajoute un composant à la simulation à des coordonnées spécifiques."""
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    sim = simulations[sim_id]["sim"]
    
    try:
        comp = sim.creer_composant(req.type_id, req.x, req.y)
        success = sim.ajouter_composant(comp)
        if not success:
            raise HTTPException(status_code=400, detail="Emplacement déjà occupé")
        return {"status": "success"}
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))

@app.delete("/api/simulations/{sim_id}/components")
def remove_component_from_sim(sim_id: str, x: int, y: int):
    """Supprime le composant situé à des coordonnées spécifiques (via query parameters)."""
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    sim = simulations[sim_id]["sim"]
    
    success = sim.supprimer_composant_at(x, y)
    if not success:
        return {"status": "no_change", "detail": "Aucun composant à cet emplacement"}
    return {"status": "success"}

@app.get("/api/settings")
def get_settings():
    return {"data_dir": str(core.loader.CUSTOM_DIR)}

@app.post("/api/settings")
def update_settings(req: SettingsRequest):
    try:
        core.loader.save_settings_dir(req.data_dir)
        return {"status": "success", "data_dir": str(core.loader.CUSTOM_DIR)}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/simulations/{sim_id}/map")
def paint_simulation_map(sim_id: str, req: PaintCellRequest):
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    sim = simulations[sim_id]["sim"]
    success = sim.paint_cell(req.x, req.y, req.value, req.brush_size)
    if not success:
        raise HTTPException(status_code=400, detail="Coordonnées en dehors de la grille de l'île")
    return {"status": "success"}

@app.post("/api/simulations/{sim_id}/generate_map")
def generate_simulation_map(sim_id: str, req: GenerateMapRequest):
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    sim = simulations[sim_id]["sim"]
    try:
        sim.generer_ile(req.algorithm, req.python_code)
        # Supprimer les entités hors grille si la noyade est active
        if sim.noyade_active:
            for comp in list(sim.composants.values()):
                if not sim.is_terre(comp.x, comp.y):
                    comp.vivant = False
            sim.nettoyer_morts()
        return {"status": "success"}
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur interne : {str(e)}")

@app.put("/api/simulations/{sim_id}/settings")
def update_simulation_settings(sim_id: str, req: SimulationSettingsRequest):
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    sim = simulations[sim_id]["sim"]
    simulations[sim_id]["speed_factor"] = req.speed_factor
    sim.gemini_api_key = req.gemini_api_key or os.getenv("API_KEY", "")
    
    # Ne régénérer que si le mode île (noyade) a changé
    if sim.noyade_active != req.noyade_active:
        sim.noyade_active = req.noyade_active
        if not sim.noyade_active:
            sim.grille = [[1] * sim.width for _ in range(sim.height)]
        else:
            sim.generer_ile("circular")
            
    return {"status": "success", "noyade_active": sim.noyade_active, "speed_factor": req.speed_factor}

if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=5000)


