from PIL import Image

src_path = r"C:\Users\barre\Workspace\AI_game_of_life\scratch\fond_bak.png"
dest_path = r"C:\Users\barre\Workspace\AI_game_of_life\frontend\assets\fond.png"

print("Loading image...")
img = Image.open(src_path)
print("Original size:", img.size)

# Calculate new size maintaining aspect ratio
new_width = 1920
new_height = int(img.height * (new_width / img.width))
print(f"Resizing to: {new_width}x{new_height}")

resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
print("Saving resized image...")
resized.save(dest_path, "PNG", optimize=True)

import os
original_size = os.path.getsize(src_path)
new_size = os.path.getsize(dest_path)
print(f"Original size: {original_size / 1024 / 1024:.2f} MB")
print(f"New size: {new_size / 1024 / 1024:.2f} MB")
print("Done!")
