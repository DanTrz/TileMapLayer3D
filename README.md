# Godot 2.5D TilePlacer 🧩

A fast, intuitive Godot 4.4+ editor plugin for building 3D tile-based levels from 2D tilesheetslike CROCOTILE, but built directly into Godot. Paint entire dungeons, castles, or worlds in minutes. Save them directly to your scene.

![Godot 4.4+](https://img.shields.io/badge/Godot-4.4%2B-blue) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## 🎯 What Problem Does This Solve?

You're building a 2.5D game. You have a beautiful tileset. Now what?

**The old way:** Manually place MeshInstance3D nodes one by one. Tedious. Slow. Error-prone. Scale a level and you've lost 3 hours.

**With 2.5D TilePlacer:** Load your tileset → Select tiles → Click to paint → Done. Full undo/redo, saves to scene, renders 10,000+ tiles with ease.

Perfect for dungeon crawlers, tile-based RPGs, puzzle games, and any 2.5D level design where speed matters.

---

## ✨ What You Can Do

- ✅ **Paint 3D levels from 2D tilesheetsinstantly** — Import any tilesheet, select tiles, click to place
- ✅ **Multi-tile selection** — Select up to 48 tiles and place them as a group
- ✅ **Flexible placement** — Paint on floor, walls, ceiling (6 orientations)
- ✅ **Transform on the fly** — Rotate (Q/E), tilt (R), flip (F), reset (T)
- ✅ **Area painting & erasing** — SHIFT+drag to paint/erase entire regions
- ✅ **Full undo/redo** — Every action reversible
- ✅ **Collision support** — Generate collision geometry automatically
- ✅ **Export your level** — Bake tiles into a single mesh, extract without scripts
- ✅ **Saves to scene** — Close and reopen, tiles are still there

---

## 🚀 Quick Start (5 Minutes)

### Step 1: Open the Plugin
1. Open your Godot 4.4+ project
2. Navigate to `Project → Project Settings → Plugins`
3. Find **"Godot 2.5D TilePlacer"** and enable it
4. The **TilePlacer panel** appears in the left dock

### Step 2: Load Your Tileset
1. In the **TilePlacer panel**, click **"Load Tileset"**
2. Select your tilesheet image (32×32 tiles recommended)
3. Set **Tile Size** (e.g., 32 pixels)
4. You'll see a grid overlay on your tileset

### Step 3: Create a Level Node
1. Create a new 3D scene with a **Node3D** root
2. Add a **TileMapLayer3D** child node
3. The plugin automatically detects it

### Step 4: Select a Tile
1. In the **TilePlacer panel**, **click on a tile** in your tileset
2. It highlights blue (selected)

### Step 5: Enable Tiling (Important!)
1. **Click the "Enable Tiling" button** at the top of the 3D viewport
2. You'll now see a **3D grid cursor** with three colored axes (X, Y, Z) appear in the 3D view
3. This cursor controls the **placement plane position** — where tiles will be painted in 3D space
4. The colored axes show you: Red=X, Green=Y, Blue=Z

### Step 6: Position the 3D Cursor with WASD
This is how you move around in 3D space (like CROCOTILE):

1. **W** — Move forward (away from camera, camera-relative)
2. **A** — Move left (camera-relative)
3. **S** — Move backward (toward camera, camera-relative)
4. **D** — Move right (camera-relative)
5. **Shift + WASD** — Move faster
6. **Ctrl + WASD** — Move slower (precise positioning)

The cursor always feels the same because movement is **relative to your camera angle**, not the world.

### Step 7: Paint Your Level
1. **Left-click in the 3D viewport** to place tiles at the cursor position
2. **Watch them appear** instantly on the current plane
3. **Move the cursor with WASD** to paint on different walls/planes
4. **Continue clicking** to paint your entire level
5. **Change orientation** with `1-6` keys to paint floor/walls/ceiling

That's it! Your tiles are automatically saved to the scene.

---

## 🎮 Complete Keyboard Shortcut Reference

### 3D Cursor Movement (Camera-Relative Navigation)

| Action | Key | Description |
|--------|-----|-------------|
| **Move Forward** | `W` | Move cursor away from camera (camera-relative) |
| **Move Left** | `A` | Move cursor left (camera-relative) |
| **Move Backward** | `S` | Move cursor toward camera (camera-relative) |
| **Move Right** | `D` | Move cursor right (camera-relative) |
| **Move Faster** | SHIFT + WASD | Increase cursor movement speed |
| **Move Slower** | CTRL + WASD | Decrease cursor movement speed (precise positioning) |

**Why This Matters:** The 3D cursor controls which plane/wall you're painting on. WASD moves it relative to your camera view, so it always feels natural regardless of camera angle (like CROCOTILE).

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
| **Rotate Tile** | `Q` | Rotate tile 90° counter-clockwise |
| **Rotate Tile** | `E` | Rotate tile 90° clockwise |
| **Tilt Tile** | `R` | Tilt the tile (angles it for slopes, roofs, diagonal placement) |
| **Flip Face** | `F` | Flip/mirror the tile face |
| **Reset to Normal** | `T` | Reset orientation and tilt back to default |
| **Change Orientation** | `1` - `6` | Place on floor, walls, or ceiling (6 ways) |

### Tileset Panel Controls (Tile Selection)

| Action | Key/Control | Description |
|--------|-------------|-------------|
| **Zoom In Tileset** | Mouse Wheel Up or `+` | Get a closer look at tiles for precise selection |
| **Zoom Out Tileset** | Mouse Wheel Down or `-` | See more tiles at once |
| **Scroll/Pan Tileset** | Right Click + Drag | Move around large tilesets |
| **Select Single Tile** | Left Click | Pick one tile (highlights blue) |
| **Select Multiple Tiles** | Click + Drag | Select a rectangular block of tiles (up to 48) |
| **Deselect All** | Right Click on Empty Area | Clear your selection |

### 3D Viewport Navigation

| Action | Control | Description |
|--------|---------|-------------|
| **Pan Camera** | Right Mouse Drag | Move camera around your level |
| **Zoom Camera** | Mouse Wheel | Zoom in/out to see your work |
| **Grid Snap** | Toggle in Settings | Align tiles to a grid (on by default) |

---

## 📖 Workflow Examples

### Example 1: Paint a Simple Dungeon with Walls

```
1. Load a dungeon tileset (stone floor + walls)
2. Click a stone floor tile → it highlights blue
3. Enable Tiling button → see the 3D cursor with colored axes
4. Click once to paint a floor tile
5. Press W a few times to move cursor forward (WASD = camera-relative movement)
6. Press 2 to change to WALL orientation (1=floor, 2-5=walls, 6=ceiling)
7. Click to paint wall tiles in a line
8. Press A to move cursor left, continue painting walls
9. Press 6 to change to ceiling, paint ceiling tiles
10. If you need to reposition, use SHIFT+WASD for faster movement
11. Save scene (Ctrl+S) → tiles persist!
```

**Key:** The 3D cursor (with X/Y/Z axes) moves with WASD. Where the cursor is determines where tiles paint. Change orientation (1-6) to paint on different planes.

### Example 2: Paint a Sloped Roof

```
1. Select roof tile from tileset
2. Enable Tiling → see grid cursor
3. Click to place first roof tile
4. Press R to tilt it (angles it 45°)
5. Click next to it → another angled tile
6. Continue painting tilted tiles across the roof
7. Press T if you need to reset tilt back to flat
```

### Example 3: Erase and Fix Mistakes

```
1. Painted wrong tile? No problem.
2. Middle-click on the bad tile → it disappears
3. Or SHIFT + middle-click and drag to erase an entire area
4. Pressed a wrong key? Ctrl+Z → full undo works
5. Everything is reversible!
```

### Example 4: Multi-Tile Painting (Fast Batch Placement)

```
1. In tileset panel, click and drag to select 4 tiles in a 2×2 block
2. Enable Tiling → grid cursor updates to show the selection
3. Left-click once → all 4 tiles paint together!
4. Press Q or E to rotate the entire group
5. Fast way to paint large areas
```

### Example 5: Create Collisions for Your Level

```
1. Select tiles you've placed
2. Click "Create Collision" button in TilePlacer panel
3. Collision geometry is automatically generated
4. Your game can now detect where players can walk
```

### Example 6: Export Your Level as a Single Mesh

```
1. Finished your level? Time to optimize!
2. Click "Bake to Scene" → tiles combine into one mesh
3. Click "Bake" → export as a standalone mesh file
4. Use it in your game without any editor plugin code
5. Perfect for shipping final levels
```

---

## 🔧 Settings & Configuration

### Per-Level Settings

Each **TileMapLayer3D** node has its own settings (saved in your scene):

- **Tileset Texture** — Which image to use for tiles
- **Tile Size** — How big each tile is (e.g., 32 pixels)
- **Grid Size** — World unit size (affects snapping)
- **Grid Snap** — Align tiles to grid automatically
- **Texture Filter** — How tiles look (sharp or blurry)
- **Enable Collisions** — Generate collision geometry
- **Collision Layer/Mask** — Physics settings

### Plugin Settings

Plugin-wide preferences (same across all projects):

- **Show Plane Grids** — Visualize grid in viewport
- **Show Debug Info** — Display tile count and performance stats
- **Auto-Save** — Save after placing tiles

---

## 🎨 Understanding the 3D Cursor (Like CROCOTILE)

The **3D grid cursor** is the heart of TilePlacer. It's a virtual 3D position marker that controls where your tiles paint.

### The Colored Axes
- **Red axis** = X direction (left/right)
- **Green axis** = Y direction (up/down)
- **Blue axis** = Z direction (forward/backward)

### Camera-Relative Movement
When you press WASD, the cursor moves **relative to your camera**, not the world. This means:
- No matter which direction you're looking, **W always moves away** from you
- **A always moves left**, **D always moves right**, **S always moves toward you**
- This matches your camera angle automatically (CROCOTILE-style)

### How It Works in Practice
```
Your camera is facing north, you press W → cursor moves north (away from camera)
You rotate camera to face south, you press W → cursor moves south (still away from camera)
Same button, different world direction, but ALWAYS feels natural
```

### Pro Tips for Cursor Movement
- **Normal speed (WASD)** — For general painting
- **Fast speed (SHIFT+WASD)** — Jump across large distances quickly
- **Precise speed (CTRL+WASD)** — Fine-tune cursor position for detailed work
- **Rotate camera** with right-mouse to change perspective, then WASD adapts automatically

---

## 🎨 Pro Tips for Faster Workflow

### Tip 1: Master the 3D Cursor Movement
The WASD controls feel natural because they're camera-relative. Rotate your camera view with the right mouse button, then WASD will automatically adapt to move relative to your new view angle. This is the key to fast painting.

### Tip 2: Use Multi-Tile Selection for Speed
Instead of placing one tile at a time, select a 4×4 block and paint entire regions. Much faster!

### Tip 3: Master Area Painting (SHIFT+Drag)
SHIFT + left-click and drag = paint entire rectangles instantly. SHIFT + middle-click = erase entire regions.

### Tip 4: Use Hotkeys for Transforms
- **R** = tilt (great for angled walls and roofs)
- **F** = flip (mirror tiles for symmetry)
- **Q/E** = rotate (perfect for walls facing different directions)
- **T** = reset everything (safety net when you mess up transforms)

### Tip 5: Undo is Your Friend
Pressed the wrong key? `Ctrl+Z` → full undo. `Ctrl+Y` → redo. No risk in experimenting!

### Tip 6: Layer Your Levels
Create multiple **TileMapLayer3D** nodes:
- One for floor tiles
- One for wall tiles
- One for props/decorations
Each can use different tilesets and settings independently.

### Tip 7: Bake When Finished
Once your level is final, export it with "Bake to Scene" → "Bake". This creates a single optimized mesh without editor dependencies.

---

## ⚙️ Common Setup Questions

### Q: "Enable Tiling button doesn't appear?"
**A:** Make sure you've selected a **TileMapLayer3D** node in your scene first. The button appears in the viewport toolbar when a node is active.

### Q: "I can't see the grid cursor in 3D"
**A:** 
1. Did you click **Enable Tiling** button? (This is required!)
2. Have you selected a tile from the tileset?
3. Is the 3D viewport active? (Click on it first)

### Q: "Tiles are saving but in wrong positions"
**A:** Check your **Grid Size** and **Tile Size** settings match your tileset. If tile size is 32 pixels but you set it to 16, positions will be off.

### Q: "How do I undo placing 50 tiles?"
**A:** `Ctrl+Z` → undoes your last action. Keep pressing `Ctrl+Z` to go back further.

### Q: "Can I use different tilesets in the same level?"
**A:** Yes! Create separate **TileMapLayer3D** nodes, each with its own tileset. Layer them together.

### Q: "How do I share this level with a programmer?"
**A:** Click **"Bake"** to export as a mesh file. This removes all editor-specific code and gives them just the geometry.

---

## 🐛 Troubleshooting

### Plugin doesn't load
1. `Project → Project Settings → Plugins`
2. Find "Godot 2.5D TilePlacer"
3. Click checkbox to enable ✓
4. Restart Godot

### Tiles appear in wrong places
- Check `Grid Size` in settings matches your world scale
- Verify `Tile Size` matches your tileset dimensions
- Enable `Grid Snap` for precise alignment

### Area painting isn't working
- Make sure you're holding `SHIFT` while dragging
- Left-click + SHIFT + drag = paint
- Middle-click + SHIFT + drag = erase

### Bake isn't creating a file
- Make sure you clicked "Bake" (not just "Bake to Scene")
- Check the export folder in your project directory
- Verify you have write permissions

### Performance is slow with many tiles
- Click "Show Debug Info" to see tile count
- If over 10,000 tiles, consider splitting into multiple scene files
- Bake completed levels to reduce live tile count

---

## 📦 What Gets Saved?

When you save your scene:
- ✅ **Tile positions** — Where each tile is placed
- ✅ **Tile rotations** — Q/E rotations and R tilts
- ✅ **Tile selections** — Which tiles you used from tileset
- ✅ **Collision data** — Generated collision shapes
- ✅ **Settings** — Grid size, tile size, etc.

Everything persists. Close and reopen your scene, all your tiles are there.

---

## 🎁 Export Options

### "Bake to Scene"
Combines all tiles into one mesh inside your scene. Keeps the editor functionality intact for further editing.

### "Bake"
Exports the final mesh as a standalone file. Perfect for:
- Sharing levels with other team members
- Using in shipped games (no editor code)
- Optimizing for performance
- Archiving finished levels

---

## 📚 Getting Help

- **GitHub Issues:** [Report bugs or request features](https://github.com/DanTrz/godot-2.5d-tileplacer/issues)
- **Discussions:** [Ask questions, share your work](https://github.com/DanTrz/godot-2.5d-tileplacer/discussions)

---

## 📄 License

MIT License — Use freely in commercial projects, modify, and redistribute.

---

**Ready to build?** Start with Step 1 of the Quick Start and you'll have your first level painted in 5 minutes. 🚀
