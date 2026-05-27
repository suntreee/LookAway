from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
PNG_PATH = RESOURCES / "AppIcon.png"


def draw_icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def box(x0, y0, x1, y1):
        return tuple(round(v * scale) for v in (x0, y0, x1, y1))

    def width(value):
        return max(1, round(value * scale))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(box(128, 136, 896, 904), radius=round(190 * scale), fill=(22, 30, 34, 54))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=round(24 * scale)))
    image.alpha_composite(shadow)

    draw.rounded_rectangle(box(128, 112, 896, 880), radius=round(190 * scale), fill=(248, 249, 246, 255))

    draw.arc(box(278, 448, 746, 856), start=206, end=334, fill=(37, 67, 69, 255), width=width(92))

    return image


def save_iconset() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)

    master = draw_icon(1024)
    master.save(PNG_PATH)

    sizes = [
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
    ]
    for filename, output_size in sizes:
        resized = master.resize((output_size, output_size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)


if __name__ == "__main__":
    save_iconset()
