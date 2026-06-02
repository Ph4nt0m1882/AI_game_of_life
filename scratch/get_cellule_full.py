import json

log_path = r"C:\Users\barre\.gemini\antigravity\brain\b48e0314-855d-4b67-ad18-4dd3f0226e2c\.system_generated\logs\transcript.jsonl"

with open(log_path, "r", encoding="utf-8") as f:
    for line in f:
        try:
            data = json.loads(line)
            content = data.get("content", "")
            if "cellule_653e9869/logic.py" in content and "class Cellule" in content:
                # Let's check if the full file is printed in this step
                if "Total Lines:" in content or "from core.composant import Composant" in content:
                    print(f"=== FULL MATCH IN STEP {data.get('step_index')} ===")
                    print(content)
                    print("=========================================")
        except Exception as e:
            pass
