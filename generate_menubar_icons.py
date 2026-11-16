import json
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

root = Path(__file__).resolve().parent
source_size = 1024
canvas_size = (256, 208)
content_size = (240, 192)
fixed_crop = (145, 240, 915, 855)


def bird_frame(frame):
    image = Image.new("L", (source_size, source_size), 0)
    draw = ImageDraw.Draw(image)
    white = 255

    draw.polygon([(420, 565), (320, 435), (185, 250), (255, 470), (160, 400), (350, 620)], fill=white)
    draw.polygon([(405, 620), (300, 690), (195, 835), (350, 745), (475, 665)], fill=white)
    draw.polygon([(350, 535), (535, 405), (730, 500), (755, 640), (610, 745),
                  (440, 715), (340, 625)], fill=white)
    draw.polygon([(585, 440), (600, 300), (720, 265), (790, 355), (745, 465)], fill=white)
    draw.polygon([(765, 340), (895, 395), (760, 430)], fill=white)

    if frame == 0:
        draw.polygon([(440, 565), (585, 475), (680, 590), (535, 650)], fill=0)
    elif frame in (1, 3):
        draw.polygon([(445, 555), (575, 435), (685, 565), (555, 615)], fill=0)
    else:
        draw.polygon([(450, 550), (565, 370), (680, 530), (570, 565)], fill=0)
        draw.polygon([(505, 515), (585, 385), (635, 525)], fill=white)
    draw.polygon([(704, 330), (724, 340), (711, 357), (695, 347)], fill=0)

    # A fixed crop keeps the body stationary throughout the animation.
    cropped = image.crop(fixed_crop)
    contained = ImageOps.contain(cropped, content_size, Image.Resampling.LANCZOS)
    mask = Image.new("L", canvas_size, 0)
    mask.paste(contained, ((canvas_size[0]-contained.width)//2, (canvas_size[1]-contained.height)//2))
    result = Image.new("RGBA", canvas_size, (0, 0, 0, 255))
    result.putalpha(mask)
    return result


frames = [bird_frame(frame) for frame in range(4)]
for frame, image in enumerate(frames):
    image.save(root / "Resources" / f"MenuBarBird{frame}.png")

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

preview = Image.new("RGBA", (canvas_size[0] * 4, canvas_size[1]), (255, 255, 255, 255))
for frame, image in enumerate(frames):
    preview.alpha_composite(image, (frame * canvas_size[0], 0))
preview.save(root / "diagnostics" / "menubar-bird-frames.png")
