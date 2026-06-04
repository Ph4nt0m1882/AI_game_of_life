FROM python:3.10-slim

WORKDIR /app

# Installer les outils de build minimaux
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copier et installer les dépendances Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier le reste du code
COPY . .

EXPOSE 5000

# Lancement du serveur FastAPI
CMD ["python", "app.py"]
