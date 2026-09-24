#!/bin/sh
# SketchyBar colours from tint. Source this from sketchybarrc.
# SketchyBar takes 0xAARRGGBB.

export BAR_COLOR=0xee{background.strip}
export ITEM_BG_COLOR=0xff{color8.strip}
export ACCENT_COLOR=0xff{color4.strip}
export LABEL_COLOR=0xff{foreground.strip}
export ICON_COLOR=0xff{color6.strip}
export WARNING_COLOR=0xff{color3.strip}
export ERROR_COLOR=0xff{color1.strip}

# Shell functions need literal braces: {{ }}
bar_color() {{ printf '%s\n' "$BAR_COLOR"; }}
