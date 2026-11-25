"""Membuat ikon aplikasi POS Apotek (Android) — kapsul putih/mint di atas teal.

Jalankan: python3 tool/generate_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

TEAL = (15, 118, 110)
TEAL_DARK = (17, 94, 89)
MINT = (153, 246, 228)
WHITE = (255, 255, 255)
ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
S = 1024 * 4  # digambar besar lalu diperkecil agar halus


def capsule(size: int, scale: float, mono: bool = False) -> Image.Image:
    """Kapsul miring + tanda plus, transparan, di tengah kanvas."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    w, h = int(size * 0.56 * scale), int(size * 0.24 * scale)
    pill = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(pill)
    left = WHITE
    right = WHITE if mono else MINT
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=right)
    # setengah kiri putih
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=255)
    half = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(half).rectangle((0, 0, w // 2, h), fill=left)
    clipped = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    clipped.paste(half, (0, 0), mask)
    pill = Image.alpha_composite(pill, clipped)
    if not mono:
        # garis sambungan kapsul
        ImageDraw.Draw(pill).line((w // 2, 0, w // 2, h), fill=TEAL_DARK + (90,), width=max(2, h // 28))
    pill = pill.rotate(40, resample=Image.BICUBIC, expand=True)

    if not mono:
        shadow = Image.new("RGBA", pill.size, (0, 0, 0, 0))
        shadow.putalpha(pill.getchannel("A").point(lambda a: a * 0.35))
        shadow = shadow.filter(ImageFilter.GaussianBlur(size // 90))
        layer.alpha_composite(shadow, ((size - pill.width) // 2 + size // 80, (size - pill.height) // 2 + size // 50))
    layer.alpha_composite(pill, ((size - pill.width) // 2, (size - pill.height) // 2))

    # tanda plus kecil di kiri atas (area kosong)
    d = ImageDraw.Draw(layer)
    c = (int(size * (0.5 - 0.2 * scale)), int(size * (0.5 - 0.2 * scale)))
    arm, thick = int(size * 0.075 * scale), int(size * 0.032 * scale)
    d.rounded_rectangle((c[0] - arm, c[1] - thick, c[0] + arm, c[1] + thick), radius=thick, fill=WHITE)
    d.rounded_rectangle((c[0] - thick, c[1] - arm, c[0] + thick, c[1] + arm), radius=thick, fill=WHITE)
    return layer


def background(size: int) -> Image.Image:
    bg = Image.new("RGBA", (size, size), TEAL + (255,))
    # cahaya lembut di kiri atas
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-size * 0.3, -size * 0.3, size * 0.8, size * 0.8), fill=(255, 255, 255, 28))
    return Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(size // 10)))


def legacy() -> Image.Image:
    """Ikon persegi membulat untuk Android lama & toko aplikasi."""
    img = Image.alpha_composite(background(S), capsule(S, 1.0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main() -> None:
    master = legacy().resize((1024, 1024), Image.LANCZOS)
    master.save(ROOT / "assets/branding/icon.png")
    # Adaptive: gambar di zona aman (≈ 61% tengah dari 108dp)
    fg = capsule(S, 0.78).resize((1024, 1024), Image.LANCZOS)
    mono = capsule(S, 0.78, mono=True).resize((1024, 1024), Image.LANCZOS)
    fg.save(ROOT / "assets/branding/icon_foreground.png")

    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, f in densities.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(exist_ok=True)
        master.resize((int(48 * f),) * 2, Image.LANCZOS).save(folder / "ic_launcher.png")
        fg.resize((int(108 * f),) * 2, Image.LANCZOS).save(folder / "ic_launcher_foreground.png")
        mono.resize((int(108 * f),) * 2, Image.LANCZOS).save(folder / "ic_launcher_monochrome.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )
    (RES / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#0F766E</color>\n</resources>\n'
    )


if __name__ == "__main__":
    main()
