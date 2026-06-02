import os
from google import genai
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("API_KEY")

client = genai.Client(api_key=api_key)

modele = client.models.list()
print(modele.page)
