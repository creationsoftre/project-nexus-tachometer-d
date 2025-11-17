# Project Nexus Tachometer HUD

> Initial D–inspired tachometer HUD for **Assetto Corsa** using **Custom Shaders Patch (CSP) Lua**.  
> Designed first in HTML/CSS, then converted 1:1 into a pure Lua implementation.

---

## ✨ Features

- 🎯 **Accurate CSS → Lua Conversion**  
  Layout is derived from a browser mock (`index.html` + `style.css`) and ported into Lua math:
  - Same dial sweep
  - Same tick / number positions
  - Same overall card proportions

- 📟 **Custom Tachometer**
  - 0–8 x1000 rpm scale
  - Major + minor ticks with warn/hot coloring
  - Inner/outer rings and highlight arc
  - Two-layer glowing needle
  - Center hub with shading
  - `RPM` / `x1000` labels

- 🎛 **Left Cluster**
  - Gear display with gold gradient (N / 1–6)
  - `MT` label
  - Big speed display
  - Live **km/h ↔ mph** toggle

- 🖱 **Draggable HUD**
  - Circular handle above the tach
  - Click + drag to reposition
  - Position is clamped inside the window

- 🎨 **Theme & Layout Config**
  - All key sizes & colors centralized
  - Simple tuning via constants (`SCALE`, margins, theme table, dial params)

---

## 📦 Repository Layout

```text
Project-Nexus-Tachometer/
├─ lua/
│  └─ projectnexus_tach.lua   # main CSP Lua script (this repo’s core)
├─ ui/                        # optional: design reference
│  ├─ index.html              # browser mock of the HUD
│  └─ style.css               # styling used for layout derivation
└─ README.md
