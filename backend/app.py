import asyncio
import uuid
import json
import core.loader
from fastapi import FastAPI, HTTPException, Form, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from simulation import Simulation
import uvicorn
from core.loader import init_loader, build_sssub, import_sssub, save_settings_dir

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



async def simulation_loop():
    while True:
        for sim_id, sim_data in list(simulations.items()):
            if sim_data["is_running"]:
                sim_data["sim"].tick()
        # 30 ticks par seconde max
        await asyncio.sleep(1/30)

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
        "is_running": False
    }
    return {"sim_id": sim_id}

@app.get("/api/simulations")
def list_sims():
    return [{"id": k, "is_running": v["is_running"]} for k, v in simulations.items()]

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
    """Retourne la liste de tous les composants enregistrés."""
    return core.loader.METADATA_REGISTRY

@app.get("/api/components/{comp_id}/icon")
def get_component_icon(comp_id: str):
    """Sert l'icône d'un composant personnalisé."""
    icon_path = core.loader.EXTRACTED_DIR / comp_id / "icon.png"
    if icon_path.exists():
        return FileResponse(str(icon_path))
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
    icon: UploadFile = File(...)
):
    """Crée un composant à partir des champs du Component Maker et l'enregistre."""
    try:
        icon_bytes = await icon.read()
        
        # Nettoyer le nom pour l'ID
        clean_name = "".join(c for c in name if c.isalnum() or c in (" ", "_", "-")).strip()
        comp_id = f"{clean_name.lower().replace(' ', '_')}_{uuid.uuid4().hex[:8]}"
        
        try:
            interactions_dict = json.loads(interactions)
        except Exception:
            interactions_dict = {}
            
        build_sssub(
            comp_id=comp_id,
            name=name,
            description=description,
            atb_vitesse=atb_vitesse,
            logic_code=logic_py,
            icon_bytes=icon_bytes,
            interactions=interactions_dict,
            forme=forme,
            coin=coin,
            orientation=orientation,
            couleur=couleur
        )
        return {"status": "success", "id": comp_id}
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
        
        # Extraire le code logic.py et l'icône icon.png en base64 pour renvoi à l'éditeur
        import io
        import zipfile
        import base64
        logic_py = ""
        icon_base64 = ""
        try:
            with zipfile.ZipFile(io.BytesIO(file_bytes), 'r') as zip_file:
                namelist = zip_file.namelist()
                if "logic.py" in namelist:
                    with zip_file.open("logic.py") as lf:
                        logic_py = lf.read().decode("utf-8", errors="ignore")
                if "icon.png" in namelist:
                    with zip_file.open("icon.png") as imgf:
                        icon_base64 = base64.b64encode(imgf.read()).decode("utf-8")
        except Exception:
            pass  # Si l'extraction échoue, on renvoie les chaînes vides
            
        return {
            "status": "success",
            "metadata": manifest,
            "logic_py": logic_py,
            "icon_base64": icon_base64
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
    sim.noyade_active = req.noyade_active
    if not sim.noyade_active:
        sim.grille = [[1] * sim.width for _ in range(sim.height)]
    else:
        sim.generer_ile("circular")
    return {"status": "success", "noyade_active": sim.noyade_active}

if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=5000, reload=True)

