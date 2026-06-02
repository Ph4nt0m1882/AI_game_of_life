from PIL import Image
import numpy as np
from scipy.ndimage import label, find_objects

# Load the image
img = Image.open("frontend/assets/bubble.png").convert("RGBA")
width, height = img.size
data = np.array(img)

# Background is white or transparent
is_bg = (data[:, :, 0] > 240) & (data[:, :, 1] > 240) & (data[:, :, 2] > 240) | (data[:, :, 3] < 15)

non_bg = ~is_bg
labeled_array, num_features = label(non_bg)
objects = find_objects(labeled_array)

print("Large elements found:")
for i, obj in enumerate(objects):
    y_start, y_end = obj[0].start, obj[0].stop
    x_start, x_end = obj[1].start, obj[1].stop
    w = x_end - x_start
    h = y_end - y_start
    if w > 20 or h > 20:
        print(f"Element {i+1}: X=[{x_start} to {x_end}] (width={w}), Y=[{y_start} to {y_end}] (height={h})")
