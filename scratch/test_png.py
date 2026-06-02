import struct

file_path = r"C:\Users\barre\Workspace\AI_game_of_life\frontend\assets\fond.png"

with open(file_path, "rb") as f:
    header = f.read(24)
    if header.startswith(b'\x89PNG\r\n\x1a\n'):
        print("Valid PNG signature")
        # Width and height are at offsets 16 and 20 (4 bytes each)
        width, height = struct.unpack(">II", header[16:24])
        print(f"Dimensions: {width}x{height}")
    else:
        print("Not a valid PNG signature or not a PNG file")
