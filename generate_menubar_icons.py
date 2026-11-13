import json
import shutil
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent
size = 128
scale = size / 1024


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


def scaled(points):
    return [(x * scale, y * scale) for x, y in points]


def box(values):
    return tuple(round(value * scale) for value in values)


first = feather(
    (430, 585), (345, 455), (245, 505), (155, 245),
    (405, 635), (310, 540), (220, 500)
)
second = feather(
    (450, 610), (360, 520), (265, 650), (190, 800),
    (420, 665), (330, 580), (235, 680)
)
wing_angles = [(195, 335), (155, 295), (125, 265), (155, 295)]
frames = []

for frame, (start, end) in enumerate(wing_angles):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    black = (0, 0, 0, 255)

    draw.polygon(scaled(first), fill=black)
    draw.polygon(scaled(second), fill=black)
    draw.ellipse(box((355, 405, 700, 710)), fill=black)
    draw.ellipse(box((570, 275, 750, 455)), fill=black)
    draw.polygon(scaled([(730, 350), (850, 390), (733, 420)]), fill=black)

    draw.arc(box((410, 435, 645, 655)), start=start, end=end, fill=(0, 0, 0, 0), width=max(2, round(40 * scale)))
    draw.ellipse(box((672, 340, 692, 360)), fill=(0, 0, 0, 0))

    image.save(root / "Resources" / f"MenuBarBird{frame}.png")
    frames.append(image)

assets = root / "Resources" / "Assets.xcassets"
assets.mkdir(exist_ok=True)
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
for frame, image in enumerate(frames):
    imageset = assets / f"MenuBarBird{frame}.imageset"
    imageset.mkdir(exist_ok=True)
    filename = f"MenuBarBird{frame}.png"
    shutil.copy2(root / "Resources" / filename, imageset / filename)
    (imageset / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": filename, "idiom": "mac", "scale": "1x"},
            {"idiom": "mac", "scale": "2x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }))

preview = Image.new("RGBA", (size * 4, size), (255, 255, 255, 255))
for frame, image in enumerate(frames):
    preview.alpha_composite(image, (frame * size, 0))
preview.save(root / "diagnostics" / "menubar-bird-frames.png")
