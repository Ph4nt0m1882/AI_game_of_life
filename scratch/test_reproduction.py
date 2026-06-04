import os
import sys
from pathlib import Path

# Add backend and root to sys.path
sys.path.append(str(Path("c:/Users/barre/Workspace/AI_game_of_life/backend")))
sys.path.append(str(Path("c:/Users/barre/Workspace/AI_game_of_life")))

from simulation import Simulation
import core.loader

def test():
    # Force UTF-8 stdout
    sys.stdout.reconfigure(encoding='utf-8')
    
    print("Configuring custom loader directory...")
    core.loader.CUSTOM_DIR = Path("c:/Users/barre/Workspace/AI_game_of_life/custom_components")
    core.loader.EXTRACTED_DIR = core.loader.CUSTOM_DIR / "extracted"
    
    print("Scanning custom components...")
    core.loader.scan_custom_components()
    
    for metadata in core.loader.METADATA_REGISTRY:
        core.loader.load_component_class(metadata["id"])
        
    print("Loaded component types in memory:", list(core.loader.LOADED_CLASSES.keys()))
    
    print("Creating simulation...")
    sim = Simulation(width=10, height=10)
    sim.grille = [[1] * 10 for _ in range(10)]
    
    # CLEAR all auto-spawned components
    sim.composants.clear()
    sim.grille_entites.clear()
    
    type_id = None
    for k in core.loader.LOADED_CLASSES.keys():
        if "humain" in k.lower():
            type_id = k
            break
    if not type_id:
        print("Error: Humain component not found!")
        return
        
    print(f"Creating parents of type {type_id}...")
    h1 = sim.creer_composant(type_id, 3, 3)
    h1.sexe = "M"
    h1.libido = 100
    h1.energie = 100
    r1 = sim.ajouter_composant(h1)
    print("h1 added successfully:", r1)
    
    h2 = sim.creer_composant(type_id, 3, 4)
    h2.sexe = "F"
    h2.libido = 100
    h2.energie = 100
    r2 = sim.ajouter_composant(h2)
    print("h2 added successfully:", r2)
    
    h1.relations[h2.id] = 100
    h2.relations[h1.id] = 100
    
    print("Testing gerer_reproduction...")
    import random
    
    old_random = random.random
    random.random = lambda: 0.1 # Forces child birth
    
    try:
        success = h1.gerer_reproduction(sim)
        print("gerer_reproduction result:", success)
        print(f"h1 state after reproduction: {h1.dernier_etat}, libido: {h1.libido}, energie: {h1.energie}")
        print(f"h2 state after reproduction: {h2.dernier_etat}, libido: {h2.libido}, energie: {h2.energie}")
        print("Total components in simulation:", len(sim.composants))
        for cid, c in sim.composants.items():
            print(f" - Component {c.id[:4]}: position ({c.x}, {c.y}), type_id: {c.type_id}, sexe: {getattr(c, 'sexe', 'N/A')}, vivant: {c.vivant}")
    except Exception as e:
        import traceback
        traceback.print_exc()
    finally:
        random.random = old_random

if __name__ == "__main__":
    test()
