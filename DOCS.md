DOCUMENTATION IS A WORK IN PROGRESS. FOR NOW SEE BELOW THE HIGHLIGHT OF EACH RELEASE. 
PROPER DOCUMENTATION WILL BE DONE AT SOME POINT.

## **Version 0.9.0** - New Mode - Vertex Editing
### Vertex Edit Mode Overview:
- Convert any FLAT_SQUARE tile into a vertex-editable tile with 4 draggable RED corner handles (No other Mesh Modes are supported, so you can only edit vertex of FLAT_SQUARES)
- Drag corners freely in 3D to create deformed surfaces, and organic shapes
- All corner positions snap to half-grid (grid_size / 2) for precise placement
- Backfaces render as RED so you can always see which side is the front face
- Full undo/redo support for convert, delete, and every corner drag

### How to use Vertex Edit Mode:
1. Switch to **Vertex Edit** mode in the main toolbar
2. Click tiles to highlight them (cyan glow) — multiple tiles can be selected
3. Click the **Convert** button in the context toolbar to convert highlighted tiles
4. Click a converted tile to select it for editing — RED corner handles appear
5. Drag any corner handle to reshape the tile in 3D
6. Press DELETE to remove selected vertex tiles

## **Version 0.8.0** - New Features - Sculpt Mode and Smart Fill Mode
Version 0.8.0 Summary
- New Sculpt Mode for brush-based terrain painting with volume generation
- New Smart Fill sub-mode with Ramp Fill operation (with optional side fill)
- Restructured Smart Select into a new Smart Operations mode with sub-modes
  
### New Feature: Sculpt Mode
- A new Sculpt Mode that lets you paint terrain using brushes and quickly raise or lower height to create 3D volumes of tiles. 
- Tiles are auto-resolved to match the desired shape, making it much easier to build large terrains.
- For now, the Sculpt Mode only works on the Y Axis (Floor), as that is the common axis for Terrain Generation.

How to use the Sculpt Mode:
- Select a Tile in the TileSetPanel. Ensure the Camera/Editor is looking at the Floor Plane (Facing Y Axis)
- Draw — Click and drag to paint the brush pattern onto the floor grid
- Confirm — Release to lock the pattern in place
- Set Height — Click on the pattern and drag up/down to raise or lower the volume

Sculpt Mode - Generation Options:
- Brush Size — Adjustable radius for all brush shapes
- Draw Top — Toggle top (ceiling) tile generation on/off (default: on)
- Draw Base — Toggle bottom (floor) tile generation on/off (default: off)
- Flip Sides — Flip face orientation for wall tiles
- Flip Top — Flip face orientation for top tiles
- Flip Bottom — Flip face orientation for bottom tiles

Sculpt Brush Shapes:
- Diamond (default) — Creates organic volumes with triangle tiles at the boundaries
- Square — Creates rectangular grid volumes

### New Feature: Smart Operations Mode
- The previous Smart Select mode has been restructured into a new Smart Operations mode with two sub-modes:

Smart Select (updated)
- Pick individual tiles, flood-fill by matching UV, or flood-fill all connected neighbours
- Now correctly picks up tiles with custom transforms (e.g., tiles placed by Smart Fill Ramp)

Smart Fill Mode (new)
- A new sub-mode for quickly filling areas with tiles and creating connections and ramps between two points.
- Currently includes one operation: Smart Fill — Ramp Fill: Creates ramps that connect any two tiles by generating a tilted surface between them. 
- Allow to change the Width of created Ramps and also to fill sides to create "Prism-Like" Ramps.

How to use the Smart Fill Mode:
- Ensure you have a UV/Tile selected in the TileSet panel
- 1st Click - Set the start tile — the tile where the ramp begins
- 2nd Click - set the end tile — the tile where the ramp ends
- The ramp is automatically generated with a live preview shown between clicks

Fill Ramp Options:
- Fill Width — Control how many tiles wide the ramp is (1 = single column, 2+ = multi-column)
- Growth Direction — Symmetric, anchor left (grow right), or anchor right (grow left)
- Flip Face — Reverse tile face orientation
- Ramp Sides — Automatically generate ramp side walls to enclose the ramp

## **Version 0.7.0** - New Feature - ANIMATED TILES

- This feature works with the concept of an Animation Frame. A frame is not a single tile; it is a region of your tileset that can span multiple tiles. You select the entire area of your animation in the tileset, then tell the plugin how to subdivide it into frames using Rows and Columns.

- For example, if your tileset has a 2×2 waterfall texture that animates across 4 steps laid out horizontally, you would select the full 8×2 tile region and set: Columns = 4, Rows = 1, Frames = 4. Each frame will be a 2×2 block of tiles. The animation cycles through these frames automatically.

- How to use it:
1. Switch to Animated Tiles mode in the top toolbar
2. Select the full tile region in the tileset that contains all animation frames
3. Set Rows / Columns to define how the region is subdivided into frames
4. Set total frames to play (can be less than Rows × Columns to skip trailing slots)
5. Set Speed — playback rate
6. Click "New" to save the animation definition
7. Select it from the list and paint in the 3D viewport. Tiles animate immediately

## **Version 0.6.0** - Multiple important updates and refactors.

UI Updates:
- Revamped UI: Left Toolbar is now the main toolbar; Bottom Toolbar becomes a Context Panel showing controls relevant to each mode
- TilePlacer Panel moved to the lower editor area for more texture display space
- New Zoom and Pan controls in the Tile Selection screen
- Mode switching now via Main Toolbar buttons on the left
<img width="480" height="200" alt="image" src="https://github.com/user-attachments/assets/200fd05a-5cdb-4e22-a7ff-7fc09926d9a0" />


New mode: Smart Select: Raycast-based tile selection that finds regular, rotated, and tilted tiles with precision. Includes three selection modes:
- Single Pick - Select individual tiles (additive — clicking more tiles adds to the selection)
- Connected UV - Selects all tiles on the same Grid Plane that share identical UV/texture
- Connected Neighbor - Selects all tiles on the same Grid Plane regardless of texture

Smart Select Operations:
- Delete - Remove/Delete all tiles in selection
- Replace UV/Texture - Replace selected tiles' texture with the current TileSet panel selection


## **Version 0.5.0** - New UI, Toolbar and Data model (If you use versions before 0.4, this will break old scenes). Migrate to 0.4 first then to 0.5

## **Version 0.4.0** - Major update with 3D mesh modes, SpriteMesh integration, and optimized storage.

# Setting Up Auto_tile

## Step 1: Ensure you have a Texture loaded via the Manual Mode first
<img width="480" height="240" alt="image" src="https://github.com/user-attachments/assets/ac54144f-1030-48e9-9114-610b98e87c67" />

- You must have at a minimum a TileSet Texture that fits the recommended Auto-tile Terrain Templates 
- For TileMapLayer3D, you need a full 47 Tiles template with the 3x3 Format
- <img width="480" height="160" alt="image" src="https://github.com/user-attachments/assets/63e5e44e-fa73-4403-b5a3-9c51149aaa47" />
- The best explanation for Auto-Tile Terrain creation is still in the Godot 3.4 docs (but works perfectly with 4.7+)
See: https://docs.godotengine.org/en/3.4/tutorials/2d/using_tilemaps.html 

## Step 2: Change to Auto-Tile mode and create a new TileSet Resource
<img width="480" height="160" alt="image" src="https://github.com/user-attachments/assets/0cb29931-50f2-47b1-b6ce-c767ab2e1556" />

- Click the button "Create New" this will Link the Loaded Texture on Manual Mode to the Auto-Tile

## Step 3: Add Some Terrains (based on your Loaded Texture and TileSet)
<img width="480" height="160" alt="image" src="https://github.com/user-attachments/assets/05d4cb3e-81fc-42dd-922c-d268476d5aa0" />

- Just add a Name and choose a Colour. These Terrains will be what you use to "paint" your terrain.

## Step 4: Click "TileSet Terrain Editor" button - This will move you to a new Tab at the bottom panels in the Editor
<img width="480" height="200" alt="image" src="https://github.com/user-attachments/assets/c6d16e8f-d5e7-420e-84e9-30fe9e74fa43" />

- Make sure you choose "Paint" (Paint Properties) Option, then the following options:
- Paint Properties = "Terrains"
- Terrain set = "Terrain Set 0"
- Terrain = Select the Terrain you want to set up for Auto-Tile.

## Step 5: Now you need to activate all base tiles that are part of that Terrain by clicking on them
<img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/c3fece39-bbc5-4d6f-9efd-362fd500430f" />

## Step 6: Next step is to select what areas in your Tiles represent the terrain. You do that by painting the Terrain Color over the Texture Tiles, following the pre-determined Godot Auto-tile Terrain Templates 
<img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/1a20c0c1-dbe6-4551-be15-d51f7dde2c42" />

- For TileMapLayer3D, you need a full 47 Tiles template with the 3x3 Format
- You can watch this video that explains how to Define the correct Terrain Tiles for Auto-Tile and Paint Terrain Properties: See from minute 3:00 - https://youtu.be/LrsfgDyOAJs?si=vWavZWXs3REXc87E&t=181 
- <img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/63e5e44e-fa73-4403-b5a3-9c51149aaa47" />
- The best explanation for Auto-Tile Terrain creation is still in the Godot 3.4 docs (but works perfectly with 4.7+)
See: https://docs.godotengine.org/en/3.4/tutorials/2d/using_tilemaps.html


- Make sure you SAVE everything.

## After the Auto-Tile Terrain is created, you can go back to the TileMapLayer3D panel
<img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/73a9b78b-5eb5-4385-8d94-019e7235742d" />

- Select the Terrain in the List 
- Start painting with it.



