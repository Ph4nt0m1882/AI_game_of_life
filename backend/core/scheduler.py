class Scheduler:
    def __init__(self):
        self.tick_count = 0

    def tick(self, simulation):
        """
        Fait avancer le temps d'un cran.
        Parcourt tous les composants de la simulation et met à jour leur ATB.
        Si l'ATB est plein, le composant effectue son action.
        """
        self.tick_count += 1
        
        # On fait une copie de la liste pour éviter les problèmes si un composant en détruit/crée un autre
        composants = list(simulation.composants.values())
        
        for comp in composants:
            if comp.vivant:
                if comp.update_atb():
                    comp.action(simulation)
                    
        # Nettoyage des morts à la fin du tick
        simulation.nettoyer_morts()
