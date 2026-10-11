#!/bin/sh
# Builds App Store upload sets from framed/: flattened JPEGs (no alpha channel,
# which App Store Connect rejects with a misleading "invalid dimensions" error)
# at 6.9" (1320x2868), 6.5" (1284x2778) and 6.3" (1206x2622).
set -e
cd "$(dirname "$0")"
swift compose.swift
rm -rf upload && mkdir -p upload/6.9-inch upload/6.5-inch upload/6.3-inch
for f in framed/*.png; do
  n=$(basename "$f" .png)
  sips -s format jpeg -s formatOptions 95 "$f" --out "upload/6.9-inch/$n.jpg" >/dev/null
  sips -z 2790 1284 "$f" --out "upload/6.5-inch/$n.png" >/dev/null
  sips -c 2778 1284 "upload/6.5-inch/$n.png" >/dev/null
  sips -s format jpeg -s formatOptions 95 "upload/6.5-inch/$n.png" --out "upload/6.5-inch/$n.jpg" >/dev/null
  rm "upload/6.5-inch/$n.png"
  sips -z 2622 1206 "$f" --out "upload/6.3-inch/$n.png" >/dev/null
  sips -s format jpeg -s formatOptions 95 "upload/6.3-inch/$n.png" --out "upload/6.3-inch/$n.jpg" >/dev/null
  rm "upload/6.3-inch/$n.png"
done
