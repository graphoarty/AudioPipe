"""Writes the AudioPipe app icon SVGs on Apple's 1024 px macOS icon grid.

- AppIcon.svg: the full artwork, used for 64 px and up.
- AppIcon-small.svg: bolder and simpler (3 bars, bigger plug), used for 16 and
  32 px, where thin bars blur together.

The tile is the macOS icon shape (824 px, centred, approximated with a
superellipse, n = 5) with the standard drop shadow. After editing, run
Scripts/make-app-icon.sh to render the asset catalog PNGs.
"""
import math, pathlib

C, A, N = 512.0, 412.0, 5.0  # centre, half-size, superellipse exponent

VARIANTS = {
    "AppIcon.svg": dict(
        cable=(60, 482, 230, 60),          # x, y, w, h
        body=(270, 424, 176, 176, 10),     # x, y, w, h, corner radius
        tip=(446, 462, 70, 100, 8),
        slot=(462, 503, 38, 18, 9),
        bars=dict(x0=570, w=38, gap=26, heights=[130, 280, 440, 270, 140]),
        shadow=12,
    ),
    "AppIcon-small.svg": dict(
        cable=(60, 474, 160, 76),
        body=(200, 412, 190, 200, 12),
        tip=(390, 456, 70, 112, 10),
        slot=None,
        bars=dict(x0=515, w=78, gap=40, heights=[240, 460, 280]),
        shadow=0,
    ),
}


def tile_path():
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        x = C + A * math.copysign(abs(c) ** (2 / N), c)
        y = C + A * math.copysign(abs(s) ** (2 / N), s)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"


def svg(v):
    tile = tile_path()
    cx, cy, cw, ch = v["cable"]
    bx, by, bw, bh, br = v["body"]
    tx, ty, tw, th, tr = v["tip"]
    b = v["bars"]
    bars = "\n    ".join(
        f'<rect x="{b["x0"] + i * (b["w"] + b["gap"])}" y="{C - h / 2:.0f}" width="{b["w"]}" height="{h}" fill="url(#wave)"/>'
        for i, h in enumerate(b["heights"])
    )
    slot = ""
    if v["slot"]:
        sx, sy, sw, sh, sr = v["slot"]
        slot = f'<rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="{sr}" fill="#1D2A8F" opacity="0.55"/>'
    shadow_filter = ""
    shadow_attr = ""
    if v["shadow"]:
        shadow_attr = ' filter="url(#shadow)"'
        shadow_filter = f'''<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="{v["shadow"]}"/>
      <feOffset dy="{v["shadow"]}"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>'''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>AudioPipe</title>
  <defs>
    <linearGradient id="bg" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#5A7BFF"/>
      <stop offset="1" stop-color="#1D2A8F"/>
    </linearGradient>
    <linearGradient id="wave" x1="0" y1="282" x2="0" y2="742" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#5BF0B6"/>
      <stop offset="1" stop-color="#22C487"/>
    </linearGradient>
    <linearGradient id="plug" x1="0" y1="{by}" x2="0" y2="{by + bh}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E4E9FF"/>
    </linearGradient>
    {shadow_filter}
    <clipPath id="tile"><path d="{tile}"/></clipPath>
  </defs>

  <!-- Tile -->
  <path d="{tile}" fill="url(#bg)"{shadow_attr}/>

  <g clip-path="url(#tile)">
    <!-- Cable, running in from the left edge -->
    <rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" fill="#FFFFFF" opacity="0.92"/>
    <!-- USB-C plug: body, metal tip, slot -->
    <rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="{br}" fill="url(#plug)"/>
    <rect x="{tx}" y="{ty}" width="{tw}" height="{th}" rx="{tr}" fill="#B8C4FF"/>
    {slot}
    <!-- Sound, as level-meter bars -->
    {bars}
  </g>

  <!-- Hairline edge -->
  <path d="{tile}" fill="none" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="2"/>
</svg>
'''


here = pathlib.Path(__file__).parent
for name, v in VARIANTS.items():
    (here / name).write_text(svg(v))
    print("wrote", name)
