from pathlib import Path

img_path = Path("custom_components/extracted/cellule_653e9869/icon.png")
if img_path.exists():
    print(f"File size: {img_path.stat().st_size} bytes")
    # Read first 16 bytes
    with open(img_path, "rb") as f:
        head = f.read(16)
        print(f"Header bytes: {head}")
        if head.startswith(b"\x89PNG\r\n\x1a\n"):
            print("Valid PNG signature detected!")
        else:
            print("Invalid PNG signature!")
else:
    print("File not found")
