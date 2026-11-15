# Theme wallpapers

| Preset | PNG | Editable SVG |
| --- | --- | --- |
| Berrit (default) | [berrit.png](berrit.png) | [berrit.svg](berrit.svg) |
| Navy | [navy.png](navy.png) | [navy.svg](navy.svg) |

Both images are 5120 × 2160. Berrit retains the original Orbital Lesson artwork
from commit `6c2d20f0` unchanged. Navy preserves its exact characters, geometry
and spacing while adapting the colors to navy, muted red, soft blue and ochre.
Both SVGs have fully resolved colors and open in ordinary viewers.

Set `cb.theme = "navy";` in a host module to choose Navy, or omit it for Berrit.
Stylix selects the preset's PNG; personal Home Manager profiles expose it at
`~/Pictures/Wallpapers/current.png`. On macOS the wallpaper agent checks at login
and every 30 seconds, changing only visible Spaces whose image differs. It does
not edit Apple's wallpaper database. Hyprland uses the native Stylix hyprpaper
target. Standalone public modules do not choose a wallpaper or install the agent.

Override `stylix.image` to select a different image. Changing application colors
does not recolor these static images. Regenerate a PNG after editing its SVG:

```sh
rsvg-convert --width 5120 --height 2160 home/wallpapers/navy.svg \
  --output home/wallpapers/navy.png
```
