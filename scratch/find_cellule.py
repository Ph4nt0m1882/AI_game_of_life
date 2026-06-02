import json

log_path = r"C:\Users\barre\.gemini\antigravity\brain\b48e0314-855d-4b67-ad18-4dd3f0226e2c\.system_generated\logs\transcript.jsonl"

with open(log_path, "r", encoding="utf-8") as f:
    for line in f:
        try:
            data = json.loads(line)
            content = data.get("content", "")
            if not content:
                continue
            if "class Cellule" in content or "Cellule(Composant)" in content:
                print(f"--- MATCH IN STEP {data.get('step_index')} ---")
                print(content[:2000]) # Print first 2000 chars of matching content
                print("-------------------------------------")
        except Exception as e:
            pass
