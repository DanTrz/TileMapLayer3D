## TileMapLayer3D 🧩
Godot 4.5+ editor plugin for building 3D tile-based levels from 2D tilesheets. Heavily inspired by Crocotile3D but built directly into Godot.

![Godot 4.5+](https://img.shields.io/badge/Godot-4.5%2B-blue)

### Join the Discord Server for more info: https://discord.gg/WKnxwrcJcn
### Full user guide: [HOW_TO_GUIDE.md](HOW_TO_GUIDE.MD)
### Latest Video and Features - Video Overview:
[![Version 0.8.0 Release](http://img.youtube.com/vi/BN21uePeWHA/0.jpg)](https://www.youtube.com/watch?v=BN21uePeWHA)

## Want to support me?
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/dantrz)
or via GitHub: [Sponsor DanTrz](https://github.com/sponsors/DanTrz)

---

## Tutorial and Auto-Tiling Setup Video
[![TileMapLayer3D - Tutorial Auto tiling overview](http://img.youtube.com/vi/ZmxgWqF22-A/0.jpg)](https://www.youtube.com/watch?v=ZmxgWqF22-A)

## 🎯 Why I created this?

To help with creating old-school 3D pixel-art games, or to leverage 2D tiles for fast level prototyping. You can build entire levels or reusable grid-based objects with perfect tile alignment.

---

## ✨ What it does

- **Paint 3D levels from 2D tilesheets** — load any tilesheet or Godot `TileSet`, select tiles, paint floors, walls, ceilings, and tilted ramps in the 3D viewport.
- **Multiple mesh types** — `FLAT_SQUARE`, `FLAT_TRIANGULE`, `BOX_MESH`, `PRISM_MESH`, plus experimental arch variants — for everything from flat floors to thick walls and angled slopes.
- **Unified Godot TileSet** — manual painting, AutoTile, custom data, animation, and runtime queries all use a single `TileSet` resource.

### Workflow modes that go beyond a paint brush

- 🧠 **AutoTile** — paint terrain and let Godot's native terrain peering bits pick the right tile for you. Roads, walls, and grass borders just *work*.
- 🎞️ **Animated Tiles** — turn a strip of frames into a shader-driven animated tile. Drop a waterfall, lava, or torch and it animates in-engine runnning on GPU via shader.
- 🪄 **Smart Operations** — click one tile to select connected regions, replace them with a different texture in one shot, or generate full ramps between two points with `Smart Fill → Fill Ramp`.
- ⛰️ **Sculpt Mode** — brush-paint volumes: draw a footprint with the diamond, square, or arched brush, then drag up to extrude a building, hill, or platform in seconds.
- 🔷 **Vertex Edit** — convert any flat tile into a free-form quad and drag its four corners in 3D for custom shapes, sloped roofs, or organic terrain.

### Built for real projects

- **Regional collision and mesh baking** — alpha-aware options for cut-out textures, per-region rebuilds, exportable baked meshes.
- **Runtime API** — place, erase, query, swap, and refresh collision from gameplay scripts
- **Full undo/redo** — every action reversible via the Godot editor.

For details on every mode, shortcut, and setting, see the [HOW_TO_GUIDE.md](HOW_TO_GUIDE.MD).

---

## 🚀 Quick Start

1. Open your Godot 4.5+ project.
2. Go to `Project → Project Settings → Plugins` and enable **TileMapLayer3D**.
3. Create a 3D scene and add a **TileMapLayer3D** node under a `Node3D`.
4. Select the **TileMapLayer3D** node — the left vertical toolbar, the bottom context toolbar, and the **TileMapLayer3D** bottom panel will appear.
5. Pick **Manual mode** from the left toolbar.
6. In the bottom panel, click **Load Texture** (or **Load TileSet**), set your tile size, and select a tile.
7. Toggle **On** in the left toolbar.
8. Use **WASD** to move the 3D cursor and **left-click** to paint.

<img width="480" height="360" alt="Main toolbar modes" src="https://github.com/user-attachments/assets/200fd05a-5cdb-4e22-a7ff-7fc09926d9a0" />

The left vertical toolbar is the primary navigation. The last option is **Global Settings** mode, which exposes collision, baking, and utility controls in the bottom panel.

---

## 🎮 Key Shortcuts

| Key | Action |
|-----|--------|
| `W` / `A` / `S` / `D` | Move cursor (camera-relative) |
| `Shift + W` / `Shift + S` | Move cursor up / down |
| Left click / drag | Paint tile / stroke |
| Right click / drag | Erase tile / stroke |
| `Shift + Left drag` | Area paint |
| `Shift + Right drag` | Area erase |
| `Q` / `E` | Rotate 90° CCW / CW |
| `R` / `Shift + R` | Cycle tilt forward / backward |
| `T` | Reset to flat orientation |
| `F` | Flip tile face |
| `Esc` | Cancel area selection |

Full shortcut and control reference: [HOW_TO_GUIDE.md](HOW_TO_GUIDE.MD).


![alt text](image.png)


## Credits

* **[SpriteMesh](https://github.com/98teg/SpriteMesh)** by [98teg](https://github.com/98teg) — Godot plugin for creating 3D meshes from 2D sprites. MIT License.

## 📄 License

MIT
