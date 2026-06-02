import os
import zipfile
import shutil
from pathlib import Path

# Paths
workspace_dir = Path("c:/Users/barre/Workspace/AI_game_of_life")
sssub_path = workspace_dir / "custom_components" / "humain_19e7.sssub"
draft_path = workspace_dir / "draft.py"
temp_dir = workspace_dir / "scratch" / "temp_sssub"

if not sssub_path.exists():
    print(f"Error: {sssub_path} does not exist!")
    exit(1)

# Ensure temp_dir is clean
if temp_dir.exists():
    shutil.rmtree(temp_dir)
os.makedirs(temp_dir)

print(f"Extracting {sssub_path} to {temp_dir}...")
with zipfile.ZipFile(sssub_path, 'r') as zip_ref:
    zip_ref.extractall(temp_dir)

# Read draft.py contents
with open(draft_path, "r", encoding="utf-8") as f:
    draft_code = f.read()

# Replace logic.py in temp_dir
logic_path = temp_dir / "logic.py"
print(f"Replacing logic.py...")
with open(logic_path, "w", encoding="utf-8") as f:
    f.write(draft_code)

# Re-zip temp_dir into humain_19e7.sssub
print(f"Repackaging into {sssub_path}...")
# Backup the original first
backup_path = sssub_path.with_suffix(".sssub.bak")
shutil.copyfile(sssub_path, backup_path)
print(f"Backup created at {backup_path}")

try:
    with zipfile.ZipFile(sssub_path, 'w', zipfile.ZIP_DEFLATED) as zip_out:
        for root, dirs, files in os.walk(temp_dir):
            for file in files:
                file_path = Path(root) / file
                archive_name = file_path.relative_to(temp_dir)
                zip_out.write(file_path, archive_name)
    print("Repackaging complete successfully!")
except Exception as e:
    print(f"Error during repackaging: {e}")
    # Restore from backup
    shutil.copyfile(backup_path, sssub_path)
finally:
    # Cleanup temp_dir
    shutil.rmtree(temp_dir)
