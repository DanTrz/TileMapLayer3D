## TileMapLayer3D 🧩

Godot 4.5+ editor plugin for building 3D tile-based levels from 2D tilesheets. This is heavily inspired by Crocotile but built directly into Godot. 

![Godot 4.5+](https://img.shields.io/badge/Godot-4.5%2B-blue) ![License MIT](https://img.shields.io/badge/license-MIT-green)

If you like this project, and want to buy me coffee: [Sponsor DanTrz](https://github.com/sponsors/DanTrz)

## Basic Navigation Video Tutorial

[![TileMap3DLayer Intro](http://img.youtube.com/vi/Ogpy8xgyBeY/0.jpg)](https://www.youtube.com/watch?v=Ogpy8xgyBeY)

## Collision and Mesh export Video Tutorial
[![Collision and Mesh Baking Generation Tutorial](http://img.youtube.com/vi/SdWBvPexwTk/0.jpg)](https://www.youtube.com/watch?v=SdWBvPexwTk)
---

## 🎯 Why I created this?

To help with creating old-school 3D Pixel art style games, or to leverage 2D tiles for fast level prototyping. 
You can create entire levels, or you can create reusable objects and assets using a Grid-based structure that offers perfect tiling. 

---

## ✨ What You Can Do

- ✅ **Paint 3D levels from 2D tilesheets** — Import any tilesheet, select tiles, click to place
- ✅ **Multi-tile selection** — Select up to 48 tiles and place them as a group
- ✅ **Flexible placement** — Paint on floor, walls, ceiling (6 orientations)
- ✅ **Transform on the fly** — Rotate (Q/E), tilt (R), flip (F), reset (T)
- ✅ **Area painting & erasing** — to paint/erase entire regions
- ✅ **Full undo/redo** — Every action reversible using Godot Editor features
- ✅ **Collision support** — Generate collision geometry automatically
- ✅ **Export your level or assets** — Bake tiles into a single mesh, extract without scripts
- ✅ **Saves to scene** — Close and reopen, tiles are still there

---

## 🚀 Quick Start

### Step 1: Open the Plugin
1. Open your Godot 4.4+ project
2. Navigate to `Project → Project Settings → Plugins`
3. Find **"TileMapLayer3D"** and enable it
4. The **TilePlacer panel** appears in the left dock

### Step 2: Base 3D Scene Setup
1. Create a new 3D scene with a **Node3D** root
2. Add a **TileMapLayer3D** node
3. Click on the **TileMapLayer3D** (**TileMapLayer3D** must be selected for Plugin to work)

### Step 3: Load Your Tileset
1. With the TileMapLayer3D selected, In the **TilePlacer panel**, click **"Load Tileset"**
2. Select your tilesheet image (Best support for 48x48 tiles or below), but all should work
3. Set **Tile Size** (e.g., 32 pixels)
4. Recommended to start with all other settings usind default options

### Step 4: Select your Tile
1. In the **TilePlacer panel**, **click on a tile** in your tileset
2. It highlights it with a Yellow square (means that tile is selected)

### Step 5: Paint your tiles
1. **Click the "Enable Tiling" button** at the top of the 3D viewport (Godot 3D Scene Editor)
2. You'll now see a **3D grid with a "virtual Gyzmo"**. This is the 3D Plane Cursor
3. This cursor controls which "plane/wall" is in focus and the **placement position** — where tiles will be painted in 3D space
4. The colored axes are referred to as "Planes" and they show you: Red=X, Green=Y, Blue=Z
5. By moving the Editor Camera, you should automatically focus on a different Axis Plane

### Step 6: Position the 3D Plane Cursor with WASD (Virtual Gyzmo with Red/Green/Blue axis lines)
This is how you move around in 3D space and move the GRID position. (Should be easy if you come from CROCOTILE):

1. **W** — Move forward (away from camera, camera-relative)
2. **A** — Move left (camera-relative)
3. **S** — Move backward (toward camera, camera-relative)
4. **D** — Move right (camera-relative)
5. **Shift + W** — Move Up
6.**Shift + S**— Move Down

The cursor always feels the same because movement is **relative to your camera angle**, not the world.

### Step 7: Paint Your Level
1. **Left-click in any of the Virtual Planes** to place tiles at the cursor position
2. **Move the cursor with WASD** to paint on different walls/planes
5. **Change orientation** by changing the Camera Position

---

## 🎮 Complete Keyboard Shortcut Reference

### 3D Cursor Movement (Camera-Relative Navigation)

| Action | Key | Description |
|--------|-----|-------------|
| **Move Forward** | `W` | Move cursor away from camera (camera-relative) |
| **Move Left** | `A` | Move cursor left (camera-relative) |
| **Move Backward** | `S` | Move cursor toward camera (camera-relative) |
| **Move Right** | `D` | Move cursor right (camera-relative) |
| **Move Up** | SHIFT + W | Move cursor UP (camera-relative) |
| **Move Down** | CTRL + S | Move cursor DOWN (camera-relative) |

**IMPORTANT:** The 3D Plane cursor controls which plane/wall you're painting on. WASD moves it relative to your camera view, so it always feels natural regardless of camera angle (like CROCOTILE).

### Placing & Erasing Tiles

| Action | Key | Description |
|--------|-----|-------------|
| **Place Tile** | Left Mouse Click | Place selected tile at cursor (requires Enable Tiling) |
| **Area Paint** | SHIFT + Left Click & Drag | Paint multiple tiles in a rectangular area |
| **Erase Tile** | Middle Mouse Click | Delete single tile at cursor |
| **Area Erase** | SHIFT + Middle Click & Drag | Delete multiple tiles in a rectangular area |
| **Enable/Disable Tiling** | Button in Viewport | Toggle grid cursor visibility (MUST enable to see preview!) |

### Tile Transformation (While Painting)

| Action | Key | Description |
|--------|-----|-------------|
| **Rotate Tile** | `Q` | Spin tile 90° counter-clockwise |
| **Rotate Tile** | `E` | Spin tile 90° clockwise |
| **Tilt Tile** | `R` | Tilt the tile (See section below - THIS IS EXPERIMENTAL and has minnor bugs) |
| **Flip Face** | `F` | Flip/mirror the tile face - You will see a "Red" square when you have backface |
| **Reset to Normal** | `T` | Reset orientation and tilt back to default |

### Tile Tilt and Rotation (Operations done with Key "R" shortcut)
The Tilt and Rotation angles are limited on each Plane and Axis. This was done originally to ensure perfect Grid Alignment some bugs I could not fix.
In the next version I plan to allow full tilt and rotation on all axis. 

Current behaviour
| Plane (Axis) | Description |
|--------|-------------|
| **Green Plane (Y Axis)** | "R" will tilt the tiles "Up and down" to create Slopes and Ramps |
| **Red Plane (X Axis)** | "R" will tilt the tiles "Up and down" to create Lateral Ramps and Slopes |
| **Blue Plane (Z Axis)** | "R" will tilt the tiles "Left and Right" to create "curves" and different directions|

You MUST change the 3D Plane Cursor position to ensure the Tilted items align with the Grid. 
---

## ⚙️ Common Setup Questions

### Q: "I can't see the grid cursor in 3D"
**A:** 
1. Did you click **Enable Tiling** button? (This is required!)
2. Have you selected the TileMapLayer3D node and selected a tile from the tileset?

### Q: "Can I use different tilesets in the same level?"
**A:** Yes! Create separate **TileMapLayer3D** nodes, each with its own tileset. Layer them together.

---

## 🎁 Export and Collision Options via "ExportAndDataTab"

### "Bake to Scene"
Combines all tiles into one mesh inside your scene.

### "Create Collision"
Create a Collision for your TileMapLayer3D node

### "Clear all Tiles"
Reset all saved data and clear all tiles

## 📄 License
MIT License — Use freely in commercial projects, modify, and redistribute.


## 📍ROADMAP PRIORITIES 
1. New Feature: AUTO-TILING - This will be the focus for a new major release. 
2. New Feature: Option to Bake as Object => New Button or UI Action to “Bake as Object” and allow sections or assets to be reused. 
3. New Feature: “MeshMerger Advanced” =>  More controls for merging meshes and new Class and Node to allow for flexible merging to happen. 
4. New Feature: Full support for Decal Mode => Allow to place transparent tiles on top of other TileMapLayer3D nodes (this is possible today but very manual)
5. New Feature: Generate Primitives (Wedge, etc). Have pre-built primitives with UV maps for each side. Allow rounded shapes and more complex shapes. 
6. New Feature: Foliage and Object Scattering System
7. New Feature: Texture to 3D Object with depth =>  Allow Tile (Texture) to be created as a new “Object” with 3D depth => based on SpriteMesh.
8. New Feature: New Tilt System (allows rotation on all possible variations from ANY Axis). Change how we handle Rotation and Tilt (Key R and Shift R - Keep others as is).

