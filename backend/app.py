import asyncio
import uuid
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from simulation import Simulation
import uvicorn

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

async def simulation_loop():
    while True:
        for sim_id, sim_data in list(simulations.items()):
            if sim_data["is_running"]:
                sim_data["sim"].tick()
        # 30 ticks par seconde max
        await asyncio.sleep(1/30)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(simulation_loop())

@app.post("/new_sim")
def create_new_sim():
    sim_id = str(uuid.uuid4())[:8] # Un petit ID lisible
    # On augmente la taille par défaut pour éviter le blocage trop rapide (ex: 80x80)
    simulations[sim_id] = {
        "sim": Simulation(width=80, height=80),
        "is_running": False
    }
    return {"sim_id": sim_id}

@app.get("/list_sims")
def list_sims():
    return [{"id": k, "is_running": v["is_running"]} for k, v in simulations.items()]

@app.get("/state/{sim_id}")
def get_state(sim_id: str):
    if sim_id not in simulations:
        raise HTTPException(status_code=404, detail="Simulation non trouvée")
    return simulations[sim_id]["sim"].get_state()

@app.post("/start/{sim_id}")
def start_sim(sim_id: str):
    if sim_id in simulations:
        simulations[sim_id]["is_running"] = True
        return {"status": "started"}
    raise HTTPException(status_code=404)

@app.post("/stop/{sim_id}")
def stop_sim(sim_id: str):
    if sim_id in simulations:
        simulations[sim_id]["is_running"] = False
        return {"status": "stopped"}
    raise HTTPException(status_code=404)

if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=5000, reload=True)
