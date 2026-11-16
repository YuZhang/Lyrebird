from pathlib import Path
from PIL import Image, ImageDraw
import subprocess

root = Path(__file__).resolve().parent
iconset = root / "Resources" / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)

size = 1024
red = (238, 64, 82, 255)
white = (255, 255, 255, 255)
image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((42, 42, 982, 982), radius=220, fill=red)

# Two broad, simple tail feathers.
draw.polygon([(420, 565), (320, 435), (185, 250), (255, 470), (160, 400), (350, 620)], fill=white)
draw.polygon([(405, 620), (300, 690), (195, 835), (350, 745), (475, 665)], fill=white)

# Faceted body, head and beak.
draw.polygon([(350, 535), (535, 405), (730, 500), (755, 640), (610, 745),
              (440, 715), (340, 625)], fill=white)
draw.polygon([(585, 440), (600, 300), (720, 265), (790, 355), (745, 465)], fill=white)
draw.polygon([(765, 340), (895, 395), (760, 430)], fill=white)

# Large polygonal wing opening and diamond eye remain legible at small sizes.
draw.polygon([(440, 565), (585, 475), (680, 590), (535, 650)], fill=red)
draw.polygon([(704, 330), (724, 340), (711, 357), (695, 347)], fill=red)

image.save(root / "Resources" / "IconPreview.png")

for name, pixels in [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]:
    resized = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
    resized.save(iconset / name)

subprocess.run([
    "iconutil", "-c", "icns", str(iconset),
    "-o", str(root / "Resources" / "AppIcon.icns")
], check=True)
