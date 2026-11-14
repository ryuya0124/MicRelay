#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
set -eu
cd "$(dirname "$0")/.."
icon_tool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
mkdir -p store/icon-previews
for appearance in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  "$icon_tool" MicRelay/Resources/AppIcon.icon --export-image \
    --output-file "store/icon-previews/$appearance.png" --platform iOS \
    --rendition "$appearance" --width 1024 --height 1024 --scale 1 --design-generation 27
done
