# TileMapLayer3D How-To Guide

TileMapLayer3D is a Godot editor plugin for building 3D, grid-based levels from 2D tilesheets and Godot `TileSet` resources. It is inspired by Crocotile-style tile painting, but it works directly inside the Godot 3D editor.

Use it to create entire levels, or to block out rooms, floors, walls, slopes, ramps, platforms, terrain, pixel-art 3D environments, or runtime-interactive tile worlds without leaving Godot.

> Note: If you are migrating to a version earlier than v1.0, you may encounter corrupted data. Make sure you have a backup of your project. Ideally, from version 1.0, you should start with a clean scene and recreate your levels in v1.0+ if possible. There is an auto-migration in place, but it might not handle all edge cases of your scene. PLEASE READ the section "Migrating Existing Scenes" for more details. [Go to Migration Guide](#18-migrating-existing-scenes)

## 1. TileMapLayer3D Basic concepts

You select one tile, or a group of tiles, then you paint those tiles into the 3D viewport. It is like the Godot TileMapLayer (2D version), but in 3D. 

Key elements:

| Object/Element | Where it appears | What you use it for |
| --- | --- | --- |
| `TileMapLayer3D` node | Scene tree | Main node that governs all Plugin operations and Tile Placement. You can use multiple `TileMapLayer3D` nodes to create different "Layers" or Zones in your levels |
| Main toolbar | Left side of the 3D viewport | Allows you to turn the "Tiling / Painting" on and select the  mode |
| Context toolbar | Bottom of the 3D viewport | Shows controls for the current selected mode |
| TileMapLayer3D bottom panel | Bottom editor panel | This displays additional details for each selected mode and allows you to complete the operations, such as selecting a tile to paint or configure auto-tiling terrains, etc.|

<img width="480" height="360" alt="Main toolbar modes" src="https://github.com/user-attachments/assets/200fd05a-5cdb-4e22-a7ff-7fc09926d9a0" />

## 2. Basic Setup

### Enable the plugin

1. Install the plugin from Godot Asset Lib or download the Zip File from Github. Ensure the Addon folder is in the Godot res://addons folder.
2. Enable `TileMapLayer3D` addon via`Project -> Project Settings -> Plugins`.
3. Add a `TileMapLayer3D` node under a `Node3D` in your scene.
4. Select the `TileMapLayer3D` node and complete the basic setup (see details below)
5. The main toolbar has an `On` toggle at the top. Enable it before painting.

When the node is selected, the TileMapLayer3D UI appears on Godot Viewport (see screenshot on section 1)

## 3. Main Menus And Navigation

### Main toolbar modes

The main toolbar lives on the left of the 3D viewport. Only one mode is active at a time.

| Mode | Use it for |
| --- | --- |
| Manual | Paint selected tiles directly in 3D |
| AutoTile | Paint terrain that automatically chooses the right atlas tile from Godot terrain data |
| Smart Operations | Select, replace, delete, or generate ramps from existing tiles |
| Animated Tiles | Define and paint shader-driven animated tile regions |
| Sculpt | Brush-paint terrain volumes and raise or lower them |
| Vertex Edit | Convert flat square tiles into editable quads with draggable corners |
| Settings | Show settings and utility panels |

Changing modes clears the current tile selection and resets mode-specific state. This is intentional: each mode has its own workflow and context.

## 4. Getting Started In Manual Mode

Manual mode allows for free tiling but also is where you setup your Texture, TileSet and Tile Size for basic configuration.

### Load a texture or TileSet

1. Select your `TileMapLayer3D` node.
2. Click Manual mode in the main toolbar.
3. Open the bottom `TileMapLayer3D` panel.
4. Click `Load Texture` to choose an image.
5. Set `Tile Set Size` to the atlas cell size, for example `32 x 32`.
6. Set `picker_tile_size` if you want the picker grid to differ from the TileSet cell size.
7. Click a tile in the texture preview.
8. Turn `On` in the main toolbar (Top Toggle on the Vertical Menu bar on the left).
9. Move the mouse in the 3D viewport and left-click to paint.

`Load Texture` creates a TileSet wrapper around the image. `Load TileSet` loads an existing `.tres` or `.res` TileSet. `Save TileSet` saves the current TileSet as a reusable resource.

### Texture size settings

There are two size controls that sound similar but do different jobs:

| Setting | Meaning |
| --- | --- |
| `Tile Set Size` | The real Godot TileSet atlas cell size |
| `picker_tile_size` | The picker grid size used when selecting from the texture |

Usually they should match. Keep them different only when you intentionally want to select freeform regions or larger visual chunks without changing the registered TileSet cell size.

### Paint and erase controls

| Action | Result |
| --- | --- |
| Left click | Paint one tile |
| Left click and drag | Paint a stroke |
| Right click | Erase one tile |
| Right click and drag | Erase a stroke |
| Shift + left drag | Fill a rectangular area |
| Shift + right drag | Erase a rectangular area |
| Esc during area selection | Cancel the area operation |

Area fill has a safety limit of 10,000 tiles.

### Navigating the 3D grid and virtual cursor for tile placement

TileMapLayer3D uses a 3D cursor and an active placement plane. Think of the cursor as the point you are working from, and the active plane as the floor, wall, or ceiling-facing grid that your mouse is currently painting on.

<img width="640" height="360" alt="3dGrid" src="https://github.com/user-attachments/assets/98d8eacd-d211-4d4b-bca5-5e91d8016f6c" />

The editor camera is part of this workflow. In Plane placement mode, TileMapLayer3D looks at the direction of the editor camera and chooses the grid plane that best matches your view. If you look down at the scene, you work on the floor-style grid. If you rotate the camera toward a wall, placement shifts to that wall-style grid. This lets you paint floors, vertical walls, and other sides of the grid without changing a separate wall/floor button.

Use WASD to move the 3D cursor around the grid relative to the current editor camera view.

| Key | Result |
| --- | --- |
| W | Move the cursor forward relative to the editor camera |
| A | Move the cursor left relative to the editor camera |
| S | Move the cursor backward relative to the editor camera |
| D | Move the cursor right relative to the editor camera |
| Shift + W | Move the cursor up relative to the editor camera |
| Shift + S | Move the cursor down relative to the editor camera |

The movement snaps to the nearest world/grid axis, so the cursor stays aligned to the TileMapLayer3D grid instead of drifting freely. 

Use this pattern when building in 3D:

1. Rotate the editor camera down towards what would be the floor, wall, or ceiling-facing grid you want is the one under your view.
2. Move the cursor with WASD or Shift + W/S until it is on the area you want to work from.
3. Paint, erase, fill, sculpt, or select depending on your current mode.

You can also change the cursor step size there; supported cursor steps are `0.5`, `1.0`, and `2.0`.

> Note: The tool was designed and tested primarily with **full-grid (1.0) snapping**. Half-grid (0.5) snapping is experimental and may break some modes. Use full-grid snapping for production work.

### Manual Mode -  Context Menu Options

Some options are only available to specifi Mesh Types. 

| Option | What it does |
| --- | --- |
| Rotate counter-clockwise | Rotates the tile 90 degrees to the left. Shortcut: Q. |
| Rotate clockwise | Rotates the tile 90 degrees to the right. Shortcut: E. |
| Freeze UV | Keeps the selected texture direction fixed while you rotate the tile. |
| Tilt | Cycles the tile through supported tilt angles. Shortcut: R, or Shift + R to cycle backward. Useful to create 45 degree Tilt of the tile |
| Reset orientation | Returns the tile to its flat default orientation. Shortcut: T. |
| Flip face | Flips which side of the tile face is shown. Shortcut: F. |
| Status readout | Shows the current rotation, tilt marker, and flip marker for the tile you are about to paint. |
| Mesh Type | Chooses the 3D shape used when placing new tiles. |
| Arc | Adjusts the arch radius for arch mesh types; it only appears when an arch mesh is selected. (Experimental and only available if enabled via Global Settings) |
| Depth | Sets how deep Box and Prism tiles extend; it only appears for Box and Prism mesh types. |
| Texture Repeat | Repeats the texture across all Box/Prism faces instead of stretching or using the default face mapping. |
| Depth Inwards | Makes Box/Prism depth grow inward instead of outward from the painted face. |
| World position | Shows the current mouse target in world coordinates. |
| Grid position | Shows the current mouse target in TileMapLayer3D grid coordinates. |


## 5. Differemt Tile Mesh Types

In Manual and Auto-tile mode you can choose different Mesh types for your tiles.

| Mesh type | Use it for | Modes |
| --- | --- | --- |
| `FLAT_SQUARE` | A normal flat square tile for floors, walls, and most simple painting | Manual & Auto_tile |
| `FLAT_TRIANGULE` | A flat triangle tile for diagonal cuts and triangular surface pieces | Manual & Auto_tile |
| `BOX_MESH` | A box-shaped tile with depth, useful for blocks, ledges, and thick wall pieces | Manual & Auto_tile |
| `PRISM_MESH` | A prism-shaped tile with depth, useful for sloped or wedge-like pieces | Manual & Auto_tile |
| `FLAT_ARCH - and it's variants` | A flat arched tile using the Arc setting (Experimental - Do not use in production yet) | Manual only |

Arch mesh types are hidden unless `Enable Arched Tiles` is turned on in the bottom panel. This Arched tiles mesh type is experimental and will have multiple breaking changes in the near future. 

## 6. Setting up the TileSet Resource

TileMapLayer3D now uses one unified Godot `TileSet`. This is the same used by Godot's built-in TileMapLayer node (2D version).
Check the Godot documentation for working with TileSets, not all options are applicable for our plugin, but Terrain Configuration, Auto-Tiling setup and CustomData workflows are exactly the same. https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html 

That means the same TileSet can provide:

- AutoTile terrain data. (Via the AutoTile Mode bottom panel)
- Runtime `TileData` lookups to retrive the Godot built in TileSet Data and Atlas https://docs.godotengine.org/en/stable/classes/class_tilesetatlassource.html.
- Configure and add custom data for pre-built custom-data channels `VariantTile`, `CollectionTiles`, and `Collision` custom data.

Custom Data is extra information you attach to tiles inside the Godot `TileSet` for each individual tile. We use Godot's built in classes for it, so Godot docs is the right source of info. Below a summary of what we use in our Plugin:

- A `TileSet` can define custom data layers, which are named fields such as `VariantTile`, `CollectionTiles`, or `Collision`.
- A `TileSetAtlasSource` is the atlas image source inside the TileSet. Each atlas tile can store its own values for those custom data layers.
- TileMapLayer3D reads those values from the placed tile's atlas coordinate, so the same painted tile can carry gameplay meaning at runtime.
- You edit these values in Godot's native TileSet editor, then TileMapLayer3D can use them while painting, querying, swapping, or generating collision.

TileMapLayer3D pre-creates these custom data layers for managed TileSets:

| Custom data layer | Type | What it is used for |
| --- | --- | --- |
| `VariantTile` | `Vector2i` | Stores the atlas coordinate of this tile's alternate version, such as a closed door tile pointing to its open door tile. |
| `CollectionTiles` | `PackedVector2Array` | Stores a list of atlas coordinates that belong to the same multi-tile object, such as a door, bridge, switch, or destructible group. These are all tiles that together form the same object |
| `Collision` | `bool` | Marks whether this tile should be treated as collidable by TileMapLayer3D collision workflows. |

Example: using `VariantTile`, `CollectionTiles`, and `Collision` for a door:

- In the TileSet editor, define each closed door tile's `VariantTile` as the atlas coordinate of its open door version.
- For every tile that belongs to the same door, set `CollectionTiles` to include the atlas coordinates that make up that door object.
- When the player interacts with one tile in the door, use a raycast to find that placed tile in the 3D world.
- Call `tilemaplayer3dNode.runtime_api.swap_tile_collection_texture(tile_info, true, max_collection_step, step_time)` on that tile.
- TileMapLayer3D then uses `CollectionTiles` to find the other placed tiles that belong to the same object, and uses each tile's `VariantTile` value to swap it to its alternate version.
- If the open and closed door tiles use different `Collision` values, rebuild collision for the affected region after the swap.

### Open the native TileSet editor

Click `Tileset Editor` to open Godot's built-in TileSet editor. Use it to configure:

- Terrains and peering bits for AutoTile.
- Custom data values.
- Collision, physics, occlusion, and other native TileSet data if your project needs it.

Save your TileSet resource when you are done.

## 7. AutoTile Mode

AutoTile mode paints terrain instead of individual selected UVs. It uses Godot's native TileSet terrain system and then places the resolved tile in 3D.

### Set up AutoTile terrain

1. In `Manual mode`, load a texture or TileSet first.
2. Change to the `AutoTile Mode`
3. Create some empty `Terrains` by giving it a name and a identifying color.
3. Open the TileSet editor clicking on `TileSet Editor` button from the bottom panel.
4. Create and paint your terrain data using Godot built in Auto-Tile and Terrain tools in the `TileSet Editor`
> Note: For full terrain coverage, use a complete Godot terrain layout such as a 47-tile 3x3 terrain template. This is exactly the same process as setting up auto-tile in Godot built-in Tilemaplayer (2d node) - Therefore any tutorial about Auto-tiling and TileSet setup and the Godot docs are your best friend.

AutoTile recalculates neighboring tiles after placement and erase.

For more details see: [SETTING_UP_AUTOTILE.md](SETTING_UP_AUTOTILE.md)

## 8. Smart Operations Mode

Smart Operations works on tiles already placed in the 3D scene.
It has two main sub-modes:

- Smart Select.
- Smart Fill.

Choose the sub-mode in the context toolbar.

### Smart Select

Smart Select lets you pick and operate on existing tiles. It's an easy way to have the plugin detect and select a tile from the mouse click, and have it highlighted for changes. 

| Smart Select mode | What it selects |
| --- | --- |
| Single Pick | Adds or removes one clicked tile from the selection |
| Connected UV | Selects connected neighbors on the same plane that use the same texture/UV |
| Connected Neighbor | Selects connected neighbors on the same plane regardless of texture |

Use it like this:

1. Switch to Smart Operations.
2. Choose `SMART SELECT`.
3. Choose a selection mode.
4. Left-click a tile in the viewport.
5. Use the operation buttons:
   - Replace swaps selected tiles to the currently selected tile from the TileSet panel.
   - Delete removes selected tiles.
   - Clear clears the selection without changing tiles.
6. Right-click in Smart Select to clear the current selection.


#### Smart Select - Context Menu Options

| Option | What it does |
| --- | --- |
| Smart Ops Main Mode | Switches between Smart Select and Smart Fill. |
| Single Pick | Selects one clicked tile. |
| Connected UV | Selects connected tiles that use the same tile texture/UV. |
| Connected Neighbor | Selects connected neighboring tiles as a group. |
| Replace selected | Swaps the selected tiles to the currently selected TileSet tile. |
| Delete selected | Deletes all tiles in the current Smart Select selection. |
| Clear selection | Clears the Smart Select selection without changing tiles. |

### Smart Fill

Smart Fill currently implements Ramp Fill only (others will come in the future)

Ramp Fill can create Ramps and also creates a surface between two existing tiles.

Use it like this:
1. Choose `SMART FILL` on context menu.
2. Select a source tile/UV in the TileSet panel.
3. Set `Width`.
4. Select the `Start position` by clicking on an existing tile.
5. Drag the mouse to preview the ramp and `click to place it`. 
4. Right-click to cancel.

#### Smart Fill Context Menu Options

| Option | What it does |
| --- | --- |
| Fill Ramp | Creates ramp tiles from the selected start point. |
| Width | Sets how wide the generated Smart Fill result should be. |
| Alignment: Center | Builds the fill centered on the starting tile. |
| Alignment: Left | Builds the fill to the left side of the starting tile. |
| Alignment: Right | Builds the fill to the right side of the starting tile. |
| Flip Ramp Face | Flips the visible face direction of generated ramp tiles. |
| Fill Sides | Adds staircase-like side wall tiles along the generated ramp. |

## 9. Sculpt Mode

Sculpt mode is for quickly building terrain volumes. It works on the floor plane only.

The workflow is:

1. Select the Tile you want
2. Select the Brush and Brush settings
3. Left Click (1st Click) -> To start to draw over an area. 
4. Left Click and hold (2nd  Click) to set the height. Click and drag up or down to raise or lower the volume.
5. Right-click to cancel/reset the current sculpt operation.

### Sculpt - Context Menu Options

| Option | What it does |
| --- | --- |
| Brush Type: | Defines what base shape you want |
| Brush Size | Changes the brush radius |
| Draw Top | Adds top tiles to the generated volume |
| Draw Base | Adds bottom/base tiles |
| Flip Sides | Flips generated wall side faces |
| Flip Top | Flips top tile faces |
| Flip Base | Flips bottom/base tile faces |

## 10. Animated Tiles

Animated Tiles are shader-driven UV animations. Animation plays only on `FLAT_SQUARE` mesh tiles. 

- This feature works with the concept of an `Animation Frame`. A `frame` is not a single tile; it is a region of your tileset that can span multiple tiles. You select the entire area of your animation in the tileset, then tell the plugin how to subdivide it into frames using Rows and Columns.

- For example, if your tileset has multiple 4×4 tree textures that animates across 6 frames organized into 3 columns and 2 rows. 

<img width="600" height="300" alt="image" src="https://github.com/user-attachments/assets/391a0da4-357b-43f9-8aad-70a0992d7f1d" />

The setting would be => Columns = 3, Rows = 2, Frames = 6. Each frame will be a 4×4 block of tiles. The animation cycles through these frames automatically.

- How to use it:
1. Select the full tile region in the tileset that contains all animation frames
2. Set `Row` and `Col` to define how the region is subdivided into frames
3.  Set `Frames` to the number of frames to play and the  `Speed`.
4. Add a `display name` and Click `New` to save the animation definition
5. Select it from the list and paint in the 3D viewport.

Deleting an animation definition removes it from the saved list, but already placed tiles keep their baked animation data.

## 11. Vertex Edit Mode

Vertex Edit converts flat square tiles into individually editable mesh tiles. Use it when you want a tile to become an organic, custom-shaped quad.
Only `FLAT_SQUARE` tiles can be converted. 

Use Vertex Edit like this:

1. Paint one or more `FLAT_SQUARE` tiles.
2. Switch to Vertex Edit mode.
3. Left-click tiles to highlight them.
4. Click Convert in the context toolbar.
5. Click a converted tile to select it for editing.
6. Drag the red corner handles in the 3D viewport.
7. Release the mouse to commit the corner move.
8. Use Delete or the Delete button to remove selected vertex tiles.
9. Right-click to clear highlights and deselect the active vertex tile.

Corner movement snaps to half-grid positions. Converted vertex tiles are stored separately from normal columnar tiles and render as their own mesh instances. They are much more expensive to render, so use them for special shapes rather than thousands of repeated tiles.

<img width="600" height="300" alt="image" src="https://github.com/user-attachments/assets/e3dd0fd2-cc6d-40a9-bdc7-5fefc8951dff" />



## 12. Custom Data Layers in the TileSet

TileMapLayer3D will auto-create some custom data layers on managed TileSets:

| Layer | Type | Default | Used for |
| --- | --- | --- | --- |
| `Animated` | `bool` | `false` | Marks tiles related to animation workflows |
| `VariantTile` | `Vector2i` | `Vector2i(-1, -1)` | Runtime tile swap target |
| `CollectionTiles` | `PackedVector2Array` | empty | Runtime grouped tile swaps |
| `Collision` | `bool` | `true` | Per-tile collision intent |

### VariantTile

Set `VariantTile` to the atlas coordinates of the tile this tile should swap into. Consider this as the "Alternate Version" of a given Tile, like the original tile is "Door Closed" and the `VariantTile` will be the coordinates in the atlas that represent the "Door Open". 

At runtime, call `swap_tile_texture(tile_info)` to use the default `VariantTile` target. See the `Runtime API` section for details.

### CollectionTiles

Set `CollectionTiles` to a list of atlas coordinates that form a related group. The runtime collection swap uses the atlas coordinate offsets to find the matching placed tiles in the world. This can tell the plugin that a Tile is a member of a larger collection of tiles. 

Each tile in the collection should also have a valid `VariantTile` if it needs to change.

### Collision

Use `Collision = false` for tiles that should be ignored by collision workflows that respect TileSet custom collision data.

## 13. Collision, Baking, And Export Utilities

The **Main Menu** (vertical toolbar on the left of the 3D viewport) is the primary navigation. Its last option is **Global Settings** mode — selecting it shows the collision, baking, and utility controls in the bottom panel.

| Tool | What it does |
| --- | --- |
| Create Collision | Generates region-based collision shapes from placed tiles |
| Clear Collisions | Removes generated collision shapes |
| Save Collision Externally | Saves generated collision shapes as external resources |
| Alpha Collision | Uses alpha-aware collision generation |
| Backface Collision | Includes backfaces in generated collision |
| Bake Mesh | Merges tiles into baked mesh output |
| Bake Alpha | Uses alpha-aware mesh baking |
| Clear All Tiles | Removes all placed tile data |
| Show Debug Info | Prints/debugs current TileMapLayer3D state |

### Alpha-Aware option (for transparent textures)

`Alpha Collision` and `Bake Alpha` enable **alpha-aware** generation. Use them when your tiles have transparent regions (cut-out pixel art, foliage, fences, decals):

- With Alpha-Aware **off**, the full tile quad is treated as solid — collision and baked geometry include the transparent corners.
- With Alpha-Aware **on**, the generator inspects the texture's alpha channel and skips fully transparent areas. This produces tighter collision shapes and cleaner baked meshes for cut-out tiles.

Alpha-Aware costs more time during bake.

### Tile Visibility, Oclusion and Regional Terrain Chunks

TileMapLayer3D splits the world into **30-unit cubic regions** (`CHUNK_REGION_SIZE`). Tiles are partitioned into these regions, and each region owns its own MultiMesh chunks plus its own collision shape:

- **Tile positioning** — tiles are rendered through per-region MultiMesh chunks (up to 1,000 tiles per chunk), so adding or erasing one tile only re-uploads instance data for that region's chunks, not the whole map.
- **Tile visibility** — each region's chunks are culled independently. Godot can hide or show entire regions based on the camera frustum, so off-screen regions don't contribute to draw calls.
- **Collision** — `Create Collision` generates one `RegionCollisionShape` per region. When you edit tiles at runtime, `set_collision_for_region(tile_info, ...)` only rebuilds the affected region's shape instead of the whole map.

This is why large maps stay responsive: edits, collision rebuilds, and bake operations all scope to the region under the change.

## 14. Runtime API

Via the Runtime API, you can make calls to the Plugin at Runtime for some operations. First there are some key Data Objects you need to know.

- `PlacedTileInfo` is a TileMapLayer3D object. It describes the placed tile in the 3D world: its unique `tile_key`, grid/world position, orientation, mesh type, UV rectangle, atlas source id, atlas coordinates, animation data, and other placement details. This is Plugin provided data wrapper with some key tile info. 
- `TileData` is Godot's built-in object from the `TileSet` resource. It describes the source atlas tile itself: terrain data, custom data layers, collision/physics/occlusion data, and other TileSet information configured in Godot's TileSet editor.

Use `PlacedTileInfo` when you need to work with the placed tile in the world. Use `TileData` when you need to read the TileSet data attached to that tile's atlas coordinate. 

Every `TileMapLayer3D` node exposes:

```gdscript
tile_map_node.runtime_api
```

Use it from gameplay scripts when you want to place, erase, query, highlight, swap, or refresh collision at runtime.

Key API methods:

| Method | Use |
| --- | --- |
| `place_tile(world_pos, uv_rect, orientation)` | Place one tile at a world position and plugin orientation (Wall, Floor, Ceiling, etc). The UV_Rect represents the coordinates to the new Tile |
| `erase_tile(world_pos, orientation)` | Erase one tile |
| `place_area(anchor_world, orientation, size, uv_rect, options)` | Place a rectangular area with the same tile texture |
| `erase_area(anchor_world, orientation, size, options)` | Erase a rectangular area |
| `find_tile(world_pos, orientation = ANY_ORIENTATION, tolerance_cells = 0)` | Find a tile near a world point - returns a `PlacedTileInfo` object with all Plugin Info about a tile. `orientation` is optional. |
| `get_first_tile_from_raycast(ray_origin, ray_dir, max_distance)` | Pick the first tile hit by a ray and returns a `PlacedTileInfo` object with all Plugin Info about a tile.|
| `world_to_grid_snapped(world_pos, orientation = ANY_ORIENTATION)` | Convert world position to snapped grid position. `orientation` is optional. |
| `grid_to_world_snapped(snapped_grid_pos, orientation = ANY_ORIENTATION)` | Convert snapped grid position back to world position. `orientation` is optional. |
| `set_collision_for_region(tile_info, alpha_aware, backface_collision)` | Rebuild collision for the affected region |
| `get_tile_data_from_key(tile_key)` | Read Godot `TileData` for a placed tile. To get a Key, you first need to find a tile with `find_tile()` or `get_first_tile_from_raycast()`. and then use `tile_info.tile_key`|
| `get_tileset()` | Get the unified TileSet for the TileMapLayer3D node|
| `atlas_coord_to_uv_rect(atlas_coords, source_id)` | Convert the TileSet atlas coords to a paintable UV rect that the Plugin can understand |
| `swap_tile_texture(tile_info, use_default_data_variant = true, custom_atlas_coords = Vector2i(-1, -1))` | Swap one tile. Defaults swap to the tile's `VariantTile`. Pass `use_default_data_variant = false` with `custom_atlas_coords` to swap to any atlas coord. |
| `swap_tile_collection_texture(tile_info, follow_chain, max_chain_steps, step_change_time)` | Swap a group using `CollectionTiles` default params will replace the tiles with their `VariantTile`tile coordinates  |
| `get_variant_tile_data(tile_key)` | Read `VariantTile` from the TileSet Custom Data channel |
| `get_collection_tile_data(tile_key)` | Read `CollectionTiles` from the TileSet Custom Data channel |
| `get_debug_info(world_pos)` | Get runtime diagnostics |

### Example 1 - Runtime query - Getting the info for a tile and getting custom data example

```gdscript
var tile_info := tile_map.runtime_api.get_first_tile_from_raycast(
	player.global_position,
	Vector3.DOWN,
	1.0
)

if tile_info:
	var tile_data := tile_map.runtime_api.get_tile_data_from_key(tile_info.tile_key)
	if tile_data:
		var variant := tile_map.runtime_api.get_variant_tile_data(tile_info.tile_key)
		var collection := tile_map.runtime_api.get_collection_tile_data(tile_info.tile_key)
		print("Variant: ", variant, " Collection: ", collection)
```

### Example 2 - Runtime swap and collision refresh

```gdscript
var tile_info := tile_map.runtime_api.get_first_tile_from_raycast(ray_origin, ray_dir, 5.5)

if tile_info:
	await tile_map.runtime_api.swap_tile_collection_texture(tile_info, true, 2, 0.15)
	await tile_map.runtime_api.set_collision_for_region(tile_info, true, true)
```

## 15. Key Settings Reference

### Global plugin settings

Global settings live in Godot `EditorSettings` under `addons/TileMapLayer3D/`.

| Setting | Meaning |
| --- | --- |
| Show Plane Grids | Shows or hides placement plane grids |
| Default Placement Mode | Plane, Point, or Surface for new sessions |
| Default Tile Size | Tile size used for new nodes |
| Default Grid Size | Grid size used for new nodes |
| Default Texture Filter | Nearest, nearest mipmap, linear, or linear mipmap |
| Default Enable Collision | Whether new nodes start with collision enabled |
| Default Alpha Threshold | Alpha threshold for collision |
| Enable Auto Flip | Automatically flips faces based on camera-facing direction |

## 16. Limits And Performance Notes

| Limit or behavior | Value |
| --- | --- |
| Recommended max tiles per node | 50,000 |
| Warning threshold | 95 percent of recommended max |
| Multi-tile selection preview cap | 48 tiles |
| Max area fill operation | 10,000 tiles |
| Minimum supported grid snap | 0.5 |
| Coordinate precision | 0.1 grid units |
| Practical coordinate range | About +/- 2500 grid units |
| Hard coordinate range | +/- 3276.7 grid units (16-bit fixed-point limit) |
| Tiles per MultiMesh chunk | 1,000 |
| Spatial region size | 30 world units |

For large maps, split work across multiple `TileMapLayer3D` nodes. This keeps editor interaction, culling, collision, and runtime updates easier to manage.

## 17. Troubleshooting

### I do not see the TileMapLayer3D UI

Select a `TileMapLayer3D` node in the scene tree. The viewport toolbars and bottom panel are shown only for the active selected node.

### I cannot paint

Check:

1. The main toolbar `On` toggle is enabled.
2. You are in a paint-capable mode.
3. A TileSet or texture is loaded.
4. A tile, terrain, or animation is selected.
5. You are not in Animated Tiles mode without an active animated tile.
6. Your placement position is within the supported coordinate range.

### AutoTile paints the wrong tiles

Check the TileSet terrain setup:

1. The correct terrain is selected.
2. Terrain peering bits are painted in Godot's TileSet editor.
3. The TileSet is saved.
4. Your atlas layout contains all required terrain cases.

### Vertex Convert does nothing

Only `FLAT_SQUARE` tiles can be converted. Select a placed flat square tile in Vertex Edit mode, then press Convert.

### Textures bleed at tile edges

Increase `pixel_inset_value` slightly (found in **Global Settings** mode → bottom panel, default `0.25`), use Nearest filtering for pixel art, and make sure the TileSet cell size matches the tilesheet.


## 18. Migrating Existing Scenes

Recent versions changed how `TileMapLayer3D` stores tile and chunk data.

Persistent tile data now lives in `TileMapLayerData`, which is a Resource owned by the `TileMapLayer3D` node. This resource stores the source `TileSet` plus the columnar tile data: positions, UV rectangles, atlas bindings, flags, transforms, animation data, and other per-tile save data.

Runtime chunks are no longer saved through flat exported arrays such as:

```gdscript
_quad_chunks
_triangle_chunks
_box_chunks
_box_repeat_chunks
_arch_corner_chunks
```

Those old chunk arrays were render/runtime cache data. They could make older `.tscn` files very large because Godot serialized references to chunk nodes. Current versions rebuild chunks from `TileMapLayerData` when the scene loads, then store the live chunks in runtime registries such as `_chunk_registry_quad`, `_chunk_registry_triangle`, `_chunk_registry_box`, and the other mesh-type registries.

### One-time resave for old scenes

When opening an older scene for the first time, Godot may print errors like:

```text
Failed to get property '_quad_chunks' from node 'TileMapLayer3D_Base'.
Failed to get property '_triangle_chunks' from node 'TileMapLayer3D_Base'.
Failed to get property '_box_chunks' from node 'TileMapLayer3D_Base'.
```

This means the old scene file still contains saved references to chunk-array properties that no longer exist. The tile data itself should rebuild from `TileMapLayerData` / columnar storage.

The practical migration is:

1. Open the old scene.
2. Make any small change so Godot marks the scene dirty. For example, place one tile, erase one tile, move a node slightly and move it back, or change any harmless setting.
3. Save the scene.
4. Reload the scene.
5. The stale chunk-array references should be gone from the scene file.
6. Runtime chunks will rebuild from `TileMapLayerData` and the runtime chunk registries.

After this resave, the old `_quad_chunks`, `_box_chunks`, and similar serialized references should not come back.

### What to preserve

Preserve your `TileMapLayer3D` node, its `TileMapLayerData` resource, and its `TileMapLayerSettings` resource. `TileMapLayerData` owns the placed tile data and the source `TileSet`; `TileMapLayerSettings` owns user/editor/render settings such as grid size, texture filter, collision settings, and placement mode. If these resources are saved externally, keep those `.tres` / `.res` files with the scene.

Do not try to preserve old chunk arrays or old chunk node references manually. Chunks are runtime cache objects now. The authoritative saved data is the tile data resource, and the chunk registries are rebuilt from it.

Before migrating large production scenes, make a project backup or duplicate the scene file.
