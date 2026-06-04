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
        
    print("Creating three humans (Killer, Accomplice, Victim)...")
    # Killer (h1) at (3, 3)
    h1 = sim.creer_composant(type_id, 3, 3)
    h1.sexe = "M"
    h1.colere = 100
    h1.energie = 100
    sim.ajouter_composant(h1)
    
    # Accomplice (h2) at (3, 4)
    h2 = sim.creer_composant(type_id, 3, 4)
    h2.sexe = "F"
    h2.colere = 80
    h2.energie = 100
    sim.ajouter_composant(h2)
    
    # Victim (h3) at (4, 3)
    h3 = sim.creer_composant(type_id, 4, 3)
    h3.sexe = "M"
    h3.colere = 0
    h3.energie = 100
    sim.ajouter_composant(h3)
    
    # Configure relations (both conspirators hate the victim)
    h1.relations[h3.id] = 10  # hates h3
    h2.relations[h3.id] = 20  # hates h3
    
    # Accomplice and Killer have initial neutral relationship (50)
    h1.relations[h2.id] = 50
    h2.relations[h1.id] = 50
    
    print("Initial state:")
    print(f" - Killer: position ({h1.x}, {h1.y}), colere: {h1.colere}, relation with victim: {h1.relations.get(h3.id)}")
    print(f" - Accomplice: position ({h2.x}, {h2.y}), colere: {h2.colere}, relation with victim: {h2.relations.get(h3.id)}")
    print(f" - Victim: position ({h3.x}, {h3.y}), vivant: {h3.vivant}")
    print("Total components in simulation:", len(sim.composants))
    
    print("\nExecuting gerer_meurtre from Killer (h1)...")
    success = h1.gerer_meurtre(sim)
    print("gerer_meurtre result:", success)
    
    print("\nState after murder:")
    print(f" - Victim vivant: {h3.vivant}")
    print(f" - Killer colere: {h1.colere} (expected: 0)")
    print(f" - Killer energy: {h1.energie} (expected: 85)")
    print(f" - Killer dernier_etat: {h1.dernier_etat}")
    print(f" - Accomplice colere: {h2.colere} (expected: 0)")
    print(f" - Accomplice energy: {h2.energie} (expected: 85)")
    print(f" - Accomplice dernier_etat: {h2.dernier_etat}")
    print(f" - Relation Accomplice -> Killer: {h2.relations.get(h1.id)} (expected: 80)")
    print(f" - Relation Killer -> Accomplice: {h1.relations.get(h2.id)} (expected: 80)")
    print(f" - Total murders on island: {getattr(sim, 'total_meurtres', 0)} (expected: 1)")
    print("Total components in simulation (excluding grid cleaner, which hasn't run):", len(sim.composants))
    
    # Assertions
    assert success is True, "Murder should be successful"
    assert h3.vivant is False, "Victim should be dead"
    assert h1.colere == 0, "Killer colere should be 0"
    assert h2.colere == 0, "Accomplice colere should be 0"
    assert h1.energie == 85, "Killer energy should be 85"
    assert h2.energie == 85, "Accomplice energy should be 85"
    assert h2.relations.get(h1.id) == 80, "Relation Accomplice -> Killer should be 80"
    assert h1.relations.get(h2.id) == 80, "Relation Killer -> Accomplice should be 80"
    assert getattr(sim, 'total_meurtres', 0) == 1, "total_meurtres should be 1"
    
    print("\nAll assertions PASSED successfully!")

if __name__ == "__main__":
    test()
