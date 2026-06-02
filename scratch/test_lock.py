import os
import sys

file_path = r"C:\Users\barre\Workspace\AI_game_of_life\frontend\assets\fond.png"

print(f"Checking {file_path}")
print("Exists:", os.path.exists(file_path))

try:
    with open(file_path, "rb") as f:
        print("Opened for reading successfully")
except Exception as e:
    print("Failed to open for reading:", e)

try:
    # Try renaming it to see if it's locked by another process
    temp_name = file_path + ".tmp"
    os.rename(file_path, temp_name)
    os.rename(temp_name, file_path)
    print("Renamed and restored successfully (no locks)")
except Exception as e:
    print("Failed to rename (possibly locked):", e)
