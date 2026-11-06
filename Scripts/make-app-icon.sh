#!/bin/sh
# Renders the app icon from Design/*.svg into the asset catalog.
# Needs rsvg-convert (brew install librsvg). Edit the artwork in
# Design/make_icon_svg.py, then run this script.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG_FULL="$ROOT/Design/AppIcon.svg"
SVG_SMALL="$ROOT/Design/AppIcon-small.svg"   # bolder art for 16 and 32 px
SET="$ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset"

python3 "$ROOT/Design/make_icon_svg.py"
mkdir -p "$SET"

render() {  # file, pixels, svg
  rsvg-convert -w "$2" -h "$2" "$3" -o "$SET/$1"
}

render icon_16x16.png        16 "$SVG_SMALL"
render icon_16x16@2x.png     32 "$SVG_SMALL"
render icon_32x32.png        32 "$SVG_SMALL"
render icon_32x32@2x.png     64 "$SVG_FULL"
render icon_128x128.png     128 "$SVG_FULL"
render icon_128x128@2x.png  256 "$SVG_FULL"
render icon_256x256.png     256 "$SVG_FULL"
render icon_256x256@2x.png  512 "$SVG_FULL"
render icon_512x512.png     512 "$SVG_FULL"
render icon_512x512@2x.png 1024 "$SVG_FULL"

cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

cat > "$ROOT/App/Resources/Assets.xcassets/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Rendered app icon into $SET"
