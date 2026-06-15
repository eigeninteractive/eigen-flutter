#!/bin/bash
# Regenerates the engine's bundled Inter weights (declared under `fonts:` in
# pubspec.yaml). Run from the engine repo root. The google_fonts-style per-weight
# static files are fetched from gstatic by hash (Google Fonts' site download is a
# single variable font).
DIR="fonts"
BASE="https://fonts.gstatic.com/s/a"

download() {
  curl -fsSL "$BASE/$1.ttf" -o "$DIR/$2.ttf"
}

download "19eb90a3227963d8c124046ae8af15e44fecb8736a27b4ab7092e81251addb6a" "Inter-Thin"
download "590cd28bff41a00881b08db47d628291d96c50084f2710c9400c57c39cd2e4eb" "Inter-ExtraLight"
download "2e9b3d490cbe065fcdc783c1c6220b6f2ce5f1b1c5b81b0c8a9f8b4f27519257" "Inter-Light"
download "ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982" "Inter-Regular"
download "492dec3bc33255f9d81bd5fb18704ad72f96f9b9318e4171bc9f9be9dd4bf44b" "Inter-Medium"
download "d7ba633bab7f40576e539a7e934a1301d7618dceea59c743de477c2c493462fc" "Inter-SemiBold"
download "b7e339223d56e8c4210c86f1ba87b3d43d6c47e03956ea56f0a7a938ae61b2a3" "Inter-Bold"
download "06fb8b97ad04af6b7fa9f2fb17d3763d28f6694f777f33dcf147e84c55a4e81a" "Inter-ExtraBold"
download "7485a755eabadd6c1b38664e848793fd919674ab8d09c25e9347e93bea9a7177" "Inter-Black"
