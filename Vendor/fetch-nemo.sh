#!/bin/zsh
# Downloads FluidAudio's NeMo text-normalisation xcframework (not committed: 100+ MB of static libs).
set -euo pipefail
cd "$(dirname "$0")"
[ -d NemoTextProcessing/NemoTextProcessing.xcframework ] && { echo "NemoTextProcessing present"; exit 0; }
URL=https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.0/NemoTextProcessing.xcframework.zip
SHA=76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f
curl -sS -L --max-time 600 -o nemo.zip "$URL"
echo "$SHA  nemo.zip" | shasum -a 256 -c - >/dev/null
mkdir -p NemoTextProcessing && unzip -q -o nemo.zip -d NemoTextProcessing && rm nemo.zip
echo "NemoTextProcessing fetched"
