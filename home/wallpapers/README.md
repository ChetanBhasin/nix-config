# Berrit wallpaper

[berrit.png](berrit.png) and [berrit.svg](berrit.svg) retain the original Orbital
Lesson artwork unchanged. The PNG is 5120 × 2160; the SVG is an editable source
with fully resolved colors.

Berrit selects this PNG through `stylix.image`. Personal Home Manager profiles
expose the selected wallpaper at `~/Pictures/Wallpapers/current.png`. On macOS
the wallpaper agent checks at login and every 30 seconds, changing only visible
Spaces whose image differs. It does not edit Apple's wallpaper database.
Hyprland uses the native Stylix hyprpaper target. Standalone public modules do
not choose a wallpaper or install the agent.

Override `stylix.image` to select a different image. Changing the application
palette does not recolor this static artwork.
