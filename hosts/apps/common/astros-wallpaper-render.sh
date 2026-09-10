#!/usr/bin/env bash
# Astros "arc on navy" wallpaper — see hosts/apps/common/ in itera.users.personal
# for where the output lands. Renders 3840x2160, 8-bit.
#
# Composition is built for FILL-crop across three very different screens:
#   3840x2160  home 4K            (no crop)
#   5120x1440  work 32:9          keeps only y 540..1620
#   2560x1600  laptop 16:10       keeps only x 192..3648
# So the arc is flattened to cross the vertical centre band, and both light and
# base layers are faded at the left/right edges: nothing bright may sit where
# another aspect ratio slices it off mid-gradient.
set -euo pipefail
out="${1:?output png path}"
W=3840; H=2160

NAVY="#000E1E"        # base field
NAVY_LIFT="#04162B"   # the soft lift, screened over the base
GLOW="#5A2506"        # dim orange: screening a bright colour washes to cream
HALO="#B8541A"
CORE="#EB6E1F"

# Quadratic bezier: enters lower-left, peaks at y~1088 (dead centre), exits right
# at y=1250. Peak stays inside the 32:9 crop band.
ARC="M -300,1700 Q 1900,700 4140,1250"

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

# Edge fade: 1.0 across the middle, falling to 0 in the outer ~10% each side.
magick -size ${W}x${H} xc:black \
  -fill white -draw "rectangle $((W*10/100)),0 $((W*90/100)),${H}" \
  -blur 0x0 -morphology Distance Euclidean:1 -auto-level \
  -blur 0x220 "$t/fade.png"

# 1. Base field: flat navy, with one broad off-centre lift so the gradient has a
#    direction without leaving a visible blob in the middle of the screen.
magick -size ${W}x${H} xc:"${NAVY}" \
  \( -size ${W}x${H} xc:black -fill "${NAVY_LIFT}" \
     -draw "ellipse 1200,1650 1500,900 0,360" -blur 0x260 \) \
  -compose screen -composite "$t/base.png"

# 2-4. Three light passes along the same arc: diffuse bloom, tighter halo, core.
magick -size ${W}x${H} xc:black \
  -stroke "${GLOW}" -strokewidth 300 -fill none -draw "path '${ARC}'" \
  -blur 0x150 "$t/glow.png"
magick -size ${W}x${H} xc:black \
  -stroke "${HALO}" -strokewidth 110 -fill none -draw "path '${ARC}'" \
  -blur 0x50 "$t/halo.png"
magick -size ${W}x${H} xc:black \
  -stroke "${CORE}" -strokewidth 14 -fill none -draw "path '${ARC}'" \
  -blur 0x3 "$t/core.png"

# Fade every light pass at the left/right edges before it is screened on.
for l in glow halo core; do
  magick "$t/$l.png" "$t/fade.png" -compose multiply -composite "$t/$l.f.png"
done

# 5. Screen the light over the base, then a gentle corner vignette.
magick "$t/base.png" \
  "$t/glow.f.png" -compose screen -composite \
  "$t/halo.f.png" -compose screen -composite \
  "$t/core.f.png" -compose screen -composite \
  \( -size ${W}x${H} radial-gradient:white-"#9E9E9E" \) -compose multiply -composite \
  -depth 8 -strip "$out"

magick identify "$out"
