from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent
iconset = root / "Resources" / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)

size = 1024
image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((42, 42, 982, 982), radius=220, fill=(238, 64, 82, 255))

white = (255, 255, 255, 255)
red = (238, 64, 82, 255)


def bezier(start, control1, control2, end, steps=80):
    points = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * start[0] + 3 * u**2 * t * control1[0] + 3 * u * t**2 * control2[0] + t**3 * end[0]
        y = u**3 * start[1] + 3 * u**2 * t * control1[1] + 3 * u * t**2 * control2[1] + t**3 * end[1]
        points.append((x, y))
    return points


def feather(start, control1, control2, end, inner_start, inner_control1, inner_control2):
    outer = bezier(start, control1, control2, end)
    inner = bezier(inner_start, inner_control1, inner_control2, end)
    return outer + list(reversed(inner))


# Two filled, tapered feather shapes instead of stroked lines.
first = feather(
    (430, 585), (345, 455), (245, 505), (155, 245),
    (405, 635), (310, 540), (220, 500)
)
second = feather(
    (450, 610), (360, 520), (265, 650), (190, 800),
    (420, 665), (330, 580), (235, 680)
)
draw.polygon(first, fill=white)
draw.polygon(second, fill=white)

# Simple body and head.
draw.ellipse((355, 405, 700, 710), fill=white)
draw.ellipse((570, 275, 750, 455), fill=white)

# A single curved wing inside the body.
draw.arc((410, 435, 645, 655), start=195, end=335, fill=red, width=30)

draw.polygon([(730, 350), (850, 390), (733, 420)], fill=white)
draw.ellipse((672, 340, 692, 360), fill=red)

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
