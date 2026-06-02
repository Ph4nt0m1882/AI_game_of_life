import sys
import random
from sklearn.tree import DecisionTreeClassifier

class ModelTester:
    _model = None

    @classmethod
    def _initialiser_model(cls):
        if cls._model is not None:
            return
            
        X = []
        y = []
        
        # Features: [energie, distance_eau, distance_herbe, dans_l_eau]
        # Classes:
        # 0: "marcher"
        # 1: "nager" (se reposer dans l'eau)
        # 2: "se_reposer" (se reposer sur terre)
        
        for energy in range(0, 101, 5):
            for dist_water in range(0, 16):
                for dist_grass in range(0, 16):
                    for in_water in [0, 1]:
                        if energy <= 20:
                            if dist_water <= 3:
                                label = 1 # nager
                            else:
                                label = 2 # se_reposer
                        elif energy <= 60:
                            if dist_water <= 5:
                                label = 1 # nager
                            else:
                                label = 2 # se_reposer
                        else:
                            label = 0 # marcher
                            
                        X.append([energy, dist_water, dist_grass, in_water])
                        y.append(label)
                        
        cls._model = DecisionTreeClassifier(max_depth=4, random_state=42)
        cls._model.fit(X, y)
        print("Modèle entraîné avec succès !")
        print("Nombre d'exemples d'entraînement :", len(X))

    @classmethod
    def predict(cls, energy, dist_water, dist_grass, in_water):
        cls._initialiser_model()
        pred = cls._model.predict([[energy, dist_water, dist_grass, in_water]])
        mapping = {0: "marcher", 1: "nager", 2: "se_reposer"}
        return mapping[int(pred[0])]

# Test predictions
ModelTester._initialiser_model()
tests = [
    # (energy, dist_water, dist_grass, in_water)
    (10, 1, 0, 1),   # Low energy, water is very close -> nager
    (10, 8, 1, 0),   # Low energy, water is far, land is close -> se_reposer
    (50, 2, 4, 0),   # Medium energy, water is close -> nager
    (50, 10, 0, 0),  # Medium energy, water is far -> se_reposer
    (85, 2, 4, 0),   # High energy -> marcher
]

for t in tests:
    res = ModelTester.predict(*t)
    print(f"Features {t} => Prediction: {res}")
