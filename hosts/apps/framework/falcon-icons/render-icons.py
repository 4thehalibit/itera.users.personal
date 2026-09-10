import os
W = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(W, "final")

# Falcon head, left-facing: angular skull, beak wedge, knocked-out eye. Chosen
# over four earlier attempts because it is the only one that still reads as a
# bird head at 22px (a brow ridge, a malar stripe and a hooked beak all turn to
# mush at that size, and a wings-out flight mark collapses into a cross).
HEAD = ('M19.4 11.2 17.2 4.8 11.4 2.8 8.2 5.4 8.0 8.0 1.8 9.4 7.2 12.6 '
        '8.4 17.2 13.0 19.2 17.4 17.4 18.6 13.4z')
EYE = (13.4, 7.6, 1.85)

# Colour AND glyph both change per state: the flake author's reasoning holds —
# the state must not depend on telling green from amber. Colours are the Astros
# palette's semantic set rather than the flake's darker defaults, which sit
# poorly on the navy bar.
STATES = {
    "protected": ("#3FA96B", '<path d="M12.4 17.6 14.4 19.5 18.6 14.8"/>'),
    "degraded":  ("#F5B335", '<path d="M15.6 13.2 V17.0"/><path d="M15.6 19.2 V19.3"/>'),
    "inactive":  ("#EF4D5E", '<path d="M13.0 14.2 18.2 19.0"/><path d="M18.2 14.2 13.0 19.0"/>'),
    "unknown":   ("#6E8CB0", '<path d="M12.8 16.6 H18.4"/>'),
}

def svg(colour, glyph):
    cx, cy, r = EYE
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">
  <path d="{HEAD}" fill="{colour}"/>
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="#0b1220"/>
  <g fill="none" stroke="#0b1220" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round">{glyph}</g>
  <g fill="none" stroke="#ffffff" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{glyph}</g>
</svg>
'''

for state, (colour, glyph) in STATES.items():
    open(f"{OUT}/falcon-sensor-{state}.svg", "w").write(svg(colour, glyph))
print("wrote", len(STATES), "state svgs to", OUT)
