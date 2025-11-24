extends RefCounted
class_name GlobalConstants

## ============================================================================
## GLOBAL CONSTANTS FOR GODOT 2.5D TILE PLACER
## ============================================================================
## This file centralizes all key numbers, shared values, and configuration

# ==============================================================================
#region GRID SIZE AND POSITIONING CONSTANTS
# ==============================================================================

## Grid alignment offset - Centers tiles on grid coordinates
## Used in: tile_placement_manager.gd, tile_model_3d.gd, tile_preview_3d.gd
##
## This offset centers tile quads at grid coordinates:
## - Grid position (0, 0, 0) → Tile centered at (0.5, 0.5, 0.5) world units
## - Grid position (1, 2, 3) → Tile centered at (1.5, 2.5, 3.5) world units
##
##  SYNC POINT: This value MUST be identical in placement, rebuild, and preview or preview won't align with placed tiles!
##
## Default: Vector3(0.5, 0.5, 0.5)
## Alternative: Vector3.ZERO for corner alignment
const GRID_ALIGNMENT_OFFSET: Vector3 = Vector3(0.5, 0.5, 0.5)

## Default grid size (distance between grid cells in world units)
## Used as default value for @export var grid_size in multiple files
## This is the spacing between grid lines and default tile size
## Default: 1.0
const DEFAULT_GRID_SIZE: float = 1.0

## Default grid snap size (fractional grid positioning resolution)
## Used as default value for grid_snap_size property
## Default: 1.0 (full grid cell snapping)
## Also available as DEFAULT_GRID_SNAP for consistency
const DEFAULT_GRID_SNAP_SIZE: float = 1.0
const DEFAULT_GRID_SNAP: float = DEFAULT_GRID_SNAP_SIZE

## Maximum canvas distance from cursor (in grid cells)
## Used in: tile_placement_manager.gd line 242
## The cursor plane acts as a bounded "canvas" for placement.
## This limits how far from the cursor you can place tiles on the active plane.
## Why this exists:
## - Prevents accidental placement thousands of units away
## - Creates intuitive "painting canvas" area around cursor
## Default: 20.0 (can place tiles 20 grid cells away from cursor)
const MAX_CANVAS_DISTANCE: float = 20.0

#endregion
# ==============================================================================
#region GRID and 3D CURSOR VISUALS: GRID, PLANE OVERLAY and AXIS CONTANTS
# ==============================================================================

## Default cursor step size (grid cells moved per WASD keypress)
## Used in: tile_cursor_3d.gd line 30
## Controls how far cursor moves with keyboard:
## - 1.0 = move 1 full grid cell per keypress
## Default: 0.5 (half-grid movement for precision)
const DEFAULT_CURSOR_STEP_SIZE: float = 1.0

## 3D cursor center cube size (width, height, depth in world units)
## Used in: tile_cursor_3d.gd line 63
const CURSOR_CENTER_CUBE_SIZE: Vector3 = Vector3(0.2, 0.2, 0.2)

## Cursor axis line thickness (cross-section size of axis lines)
## Used in: tile_cursor_3d.gd lines 92, 94, 96
## Thickness of the thin box mesh used for axis lines
const CURSOR_AXIS_LINE_THICKNESS: float = 0.05

## Default cursor start position (grid coordinates)
## Default: Vector3(0.5, 0.5, 0.5)
const DEFAULT_CURSOR_START_POSITION: Vector3 = Vector3.ZERO
#const DEFAULT_CURSOR_START_POSITION: Vector3 = Vector3(0.5, 0.5, 0.5)

## X-axis line color (Red)
## Used in: tile_cursor_3d.gd line 78
## Default: Color(1, 0, 0, 0.6) - Red with 60% opacity
const CURSOR_X_AXIS_COLOR: Color = Color(1, 0, 0, 0.6)

## Y-axis line color (Green)
## Used in: tile_cursor_3d.gd line 80
## Default: Color(0, 1, 0, 0.6) - Green with 60% opacity
const CURSOR_Y_AXIS_COLOR: Color = Color(0, 1, 0, 0.6)

## Z-axis line color (Blue)
## Used in: tile_cursor_3d.gd line 80
## Default: Color(0, 0, 1, 0.6) - Blue with 60% opacity
const CURSOR_Z_AXIS_COLOR: Color = Color(0, 0, 1, 0.6)

## Cursor center cube color
## Used in: tile_cursor_3d.gd line 68
## Default: Color.WHITE with alpha 0.8
const CURSOR_CENTER_COLOR: Color = Color(1, 1, 1, 0.8)

## Default cursor crosshair length (distance from center in each direction)
## Used in: tile_cursor_3d.gd line 19
const DEFAULT_CROSSHAIR_LENGTH: float = 20.0

## YZ plane overlay base color (Red)
## Used in: cursor_plane_visualizer.gd line 93, 262
## Plane perpendicular to X-axis
## Default: Color(1, 0, 0, 0.0) - Red (alpha set dynamically)
const YZ_PLANE_COLOR: Color = Color(1, 0, 0, 0.0)

## XZ plane overlay base color (Green)
## Used in: cursor_plane_visualizer.gd line 99, 269
const XZ_PLANE_COLOR: Color = Color(0, 1, 0, 0.0)

## XY plane overlay base color (Blue)
## Used in: cursor_plane_visualizer.gd line 105, 276
const XY_PLANE_COLOR: Color = Color(0, 0, 1, 0.0)

## Default grid extent (number of grid lines in each direction)
## Used in: cursor_plane_visualizer.gd line 14
## Default: 10  = show 10 lines in each direction (20 total lines)
const DEFAULT_GRID_EXTENT: int = 20

## Default grid line color
## Used in: cursor_plane_visualizer.gd line 19, tile_cursor_3d.gd line 116
## Default: Color(0.5, 0.5, 0.5, 1.0) - Gray
const DEFAULT_GRID_LINE_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)

## Active plane overlay alpha (opacity when plane is active)
## Used in: cursor_plane_visualizer.gd line 30
## Default: 0.025 (very subtle hint)
const ACTIVE_OVERLAY_ALPHA: float = 0.01

## Active plane grid line alpha
## Used in: cursor_plane_visualizer.gd line 31
## Opacity of grid lines on the active plane
## Default: 0.5 (50% opacity)
const ACTIVE_GRID_LINE_ALPHA: float = 0.5

## Plane overlay push-back distance (prevents Z-fighting with tiles)
## Used in: cursor_plane_visualizer.gd line 90
## Moves overlay slightly behind its plane to prevent visual flickering
const PLANE_OVERLAY_PUSH_BACK: float = -0.01

## Dotted line dash length (grid visualization)
## Used in: cursor_plane_visualizer.gd line 187, 195
## Length of each dash in the dotted grid lines
## Default: 0.25 * grid_size
## Note: This is a multiplier, actual value = DOTTED_LINE_DASH_LENGTH * grid_size
const DOTTED_LINE_DASH_LENGTH: float = 0.25

## Visual grid line offset (purely cosmetic - does NOT affect logic)
## Used in: cursor_plane_visualizer.gd
## Offsets ONLY the visual grid lines to create "grid cell" appearance
## This is independent of cursor axis, raycasting, and placement logic
## - Vector3(0.5, 0.5, 0.5) = grid lines appear centered in cells
## - Vector3.ZERO = grid lines align with cursor axis
## Default: Vector3(0.5, 0.5, 0.5)
const VISUAL_GRID_LINES_OFFSET: Vector3 = Vector3.ZERO #Vector3(0.5, 0.5, 0.5)

## Visual grid depth push-back per axis (prevents Z-fighting with cursor axis and tiles)
## Used in: cursor_plane_visualizer.gd
## Moves grid lines slightly behind their plane so they appear "beneath" other elements
## Different values per axis because camera angle affects required depth offset
## - X: Push-back for YZ plane (perpendicular to X-axis)
## - Y: Push-back for XZ plane (perpendicular to Y-axis)
## - Z: Push-back for XY plane (perpendicular to Z-axis)
## Default: Vector3(-0.52, -0.52, -0.02) - less push-back on Z for front/back views
const VISUAL_GRID_LINES_PUSH_BACK: Vector3 = Vector3(-0.1, -0.1, 0.1)

#endregion
# ==============================================================================
#region TILE PREVIEW CONSTANTS
# ==============================================================================

## Preview grid indicator size (small yellow cube at grid position)
## Used in: tile_preview_3d.gd line 51
## The bright cube that shows exact grid position during preview
## Default: Vector3(0.15, 0.15, 0.15)
const PREVIEW_GRID_INDICATOR_SIZE: Vector3 = Vector3(0.15, 0.15, 0.15)

## Preview grid indicator color
## Used in: tile_preview_3d.gd line 56
## Bright yellow/orange for high visibility
## Default: Color(1.0, 0.8, 0.0, 0.9) - Yellow-orange with 90% opacity
const PREVIEW_GRID_INDICATOR_COLOR: Color = Color(1.0, 0.8, 0.0, 0.9)

## Default preview color/transparency
## Used in: tile_preview_3d.gd line 14
## Default: Color(1, 1, 1, 0.7) - White with 70% opacity
const DEFAULT_PREVIEW_COLOR: Color = Color(1, 1, 1, 0.7)

## Maximum preview instances for multi-tile selection
## Used in: tile_preview_3d.gd for preview pool size
## Should match MAX_SELECTION_SIZE in tileset_panel.gd
## Default: 48 (maximum tiles that can be selected at once)
const PREVIEW_POOL_SIZE: int = 48

##Area ERASE of more than 500 tiles is taking a long, long time. This was an attempt to control that.
const PREVIEW_UPDATE_INTERVAL: float = 0.033 

##  Movement threshold to reduce preview updates (5-10x fewer updates)
const PREVIEW_MIN_MOVEMENT: float = 1.0  # Minimum pixels to trigger preview update
const PREVIEW_MIN_GRID_MOVEMENT: float = 1.0  # Minimum grid units to trigger preview update

#endregion
# ==============================================================================
#region PAINTING MODE CONSTANTS
# ==============================================================================

## Paint mode update interval (time between paint operations while dragging)
## Used in: TileMapLayer3D_plugin.gd for paint stroke throttling
## Controls how frequently tiles are placed during click-and-drag painting
## Lower = faster painting but more CPU usage
## Higher = slower painting but better performance
## Default: 0.050 (~20 tiles per second)
## Compare to PREVIEW_UPDATE_INTERVAL (0.033 = ~30fps for cursor preview)
const PAINT_UPDATE_INTERVAL: float = 0.050

## Minimum grid distance to consider positions different during painting
## Used in: TileMapLayer3D_plugin.gd for duplicate prevention
## If new position is within this distance of last painted position, skip it
## Prevents placing multiple tiles at the same grid cell during fast mouse drags
## Default: 0.01 (1% of grid cell = effectively same position)
const MIN_PAINT_GRID_DISTANCE: float = 0.01

#endregion
# ==============================================================================
#region RAYCAST CONSTANTS
# ==============================================================================

## Raycast maximum distance (how far ray travels from camera)
## Used in: tile_placement_manager.gd line 171
## When raycasting from camera to find placement position,
const RAYCAST_MAX_DISTANCE: float = 1000.0

## Parallel plane threshold (minimum dot product for valid plane intersection)
## Used in: tile_placement_manager.gd line 219
## When raycasting to cursor planes, if ray is nearly parallel to plane
## (abs(denom) < threshold), intersection is invalid.
## Default: 0.0001
const PARALLEL_PLANE_THRESHOLD: float = 0.0001

#endregion
# ==============================================================================
#region ORIENTATION ROTATION ANGLES (in radians)
# ==============================================================================
## These constants define rotation angles for tile orientations.
## Used in: tile_placement_manager.gd lines 349-379, tile_preview_3d.gd lines 181-199
##  SYNC POINT: Orientation logic MUST match between placement and preview!

## PI constant (180 degrees in radians)
## Used for 180° rotations (ceiling orientation)
const ROTATION_180_DEG: float = PI

## 90 degrees in radians (PI/2)
## Used for wall orientations
const ROTATION_90_DEG: float = PI / 2.0

## -90 degrees in radians (-PI/2)
## Used for wall orientations
const ROTATION_NEG_90_DEG: float = -PI / 2.0

#endregion
# ==============================================================================
#region TILE ROTATION & SCALING SYSTEM (45° Tilt Support)
# ==============================================================================
## Constants for the 18-state orientation system (6 base + 12 tilted variants)
## Used in: global_util.gd, tile_placement_manager.gd
##  These constants enable ramps, roofs, and slanted walls

## 45° tilt angle for all angled tile orientations
## Used in: global_util.gd get_orientation_basis() for tilted orientations
## Default: 45.0 degrees
const TILT_ANGLE_DEG: float = 45.0

## 45° tilt angle in radians
## Pre-calculated for performance (avoid deg_to_rad() calls)
const TILT_ANGLE_RAD: float = 0.785398163397  # PI / 4.0


## This constant is kept for backward compatibility but should NOT be used
const TILT_POSITION_OFFSET_FACTOR: float = 0.5


##   Non-uniform scale factor for 45° rotated tiles to eliminate gaps
## Applied to ONE axis (X or Z) depending on rotation plane
## When a tile rotates 45°, we scale the perpendicular axis UP by √2
## Used in: tile_placement_manager.gd _get_scale_for_orientation()
##
## Scaling by axis:
##   - Floor/Ceiling tilts (X-axis rotation): Scale Z (depth) by √2
##   - Wall N/S tilts (Y-axis rotation): Scale X (width) by √2
##   - Wall E/W tilts (X-axis rotation): Scale Z (depth) by √2
##
## Mathematical proof: 1.0m tile scaled to 1.414m, then rotated 45°
##   → projected dimension = 1.414 × cos(45°) ≈ 1.0m (perfect grid fit)
const DIAGONAL_SCALE_FACTOR: float = 1.41421356237  # sqrt(2.0)

#endregion
# ==============================================================================
#region TILE DEFAULT VALUES and UI OPTIONS (UI & Configuration)
# ==============================================================================

## Default tile size for tileset panel (pixels in atlas texture)
## Used in: tileset_panel.gd line 53
## This is the size of tiles in the TEXTURE ATLAS, not world size
const DEFAULT_TILE_SIZE: Vector2i = Vector2i(32, 32)

## Cursor step size options for dropdown
## Used in: tileset_panel.gd line 234
const CURSOR_STEP_OPTIONS: Array[float] = [0.25, 0.5, 1.0, 2.0]

## Grid snap size options for dropdown
## Used in: tileset_panel.gd line 240
## Available options in the grid snapping dropdown
const GRID_SNAP_OPTIONS: Array[float] = [1.0, 0.5, 0.25, 0.125]

## Texture filter mode options for dropdown
## Maps to Godot's BaseMaterial3D.TextureFilter enum
## Used in: tileset_panel.gd, tile_placement_manager.gd
const TEXTURE_FILTER_OPTIONS: Array[String] = [
	"Nearest",           # 0 - TEXTURE_FILTER_NEAREST
	"Nearest Mipmap",    # 1 - TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	"Linear",            # 2 - TEXTURE_FILTER_LINEAR
	"Linear Mipmap"      # 3 - TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
]

## Default texture filter (Nearest for pixel-perfect rendering)
const DEFAULT_TEXTURE_FILTER: int = 0  # BaseMaterial3D.TEXTURE_FILTER_NEAREST

#endregion
# ==============================================================================
#region TILE KEY FORMATTING
# ==============================================================================

## Precision for fractional grid positions in tile keys
## Used in: tile_placement_manager.gd line 44
## Tile keys use format "x,y,z,orientation" with this precision
## - 3 decimal places = 0.001 grid unit precision
const TILE_KEY_PRECISION: int = 3

# ## DEPRECATED: String tile key format (kept for backward compatibility only)
# ## Modern code uses integer keys via TileKeySystem.make_tile_key_int()
# ## This format is only used for:
# ## - Migrating old scenes with string keys to integer keys
# ## - Debug output (TileKeySystem.key_to_string())
# const TILE_KEY_FORMAT: String = "%.3f,%.3f,%.3f,%d"

#endregion
# ==============================================================================
#region MULTIMESH CHUNK SYSTEM
# ==============================================================================

## Maximum tiles per MultiMesh chunk
## Used in: tile_model_3d.gd (TileChunk class)
const CHUNK_MAX_TILES: int = 1000

## Custom AABB for MultiMesh chunks (ensures tiles are always visible)
## Used in: tile_model_3d.gd line 172
## Default: AABB(Vector3(-500, -10, -500), Vector3(1000, 20, 1000))
const CHUNK_CUSTOM_AABB: AABB = AABB(Vector3(-500, -10, -500), Vector3(1000, 20, 1000))

const DEFAULT_RENDER_PRIORITY: int = 0

##Controls what type of Mesh are placing in the TileMapLayers
enum MeshMode {
    MESH_SQUARE = 0,
    MESH_TRIANGLE = 1
}

const DEFAULT_MESH_MODE: int = 0  # Start with square mode

#endregion
# ==============================================================================
#region COLLISION SYSTEM
# ==============================================================================

## Default collision layer for generated collision shapes
## Bit 1 = layer 1 (default physics layer)
## Used in: tile_model_3d.gd
const DEFAULT_COLLISION_LAYER: int = 1

## Default collision mask for generated collision shapes
## Bit 1 = layer 1 (collides with default physics layer)
## Used in: tile_model_3d.gd
const DEFAULT_COLLISION_MASK: int = 1

## Default alpha threshold for sprite collision detection
## Pixels with alpha > this value are considered solid
## Range: 0.0 (all transparent) to 1.0 (only fully opaque)
## Used in: tile_model_3d.gd, sprite_collision_generator.gd
const DEFAULT_ALPHA_THRESHOLD: float = 0.5

## Thickness of collision boxes for flat tiles
## DEPRECATED: Now using flat geometry (no thickness)
## Kept for backward compatibility, set to 0.0
## Used in: sprite_collision_generator.gd (legacy)
const COLLISION_BOX_THICKNESS: float = 0.0

## Maximum number of cached collision shapes
## Prevents memory bloat from too many unique tile textures
## Used in: sprite_collision_generator.gd (future enhancement)
const COLLISION_SHAPE_CACHE_MAX: int = 256

#endregion
# ==============================================================================
#region TILESET PANEL ZOOM CONSTANTS
# ==============================================================================

## Zoom step multiplier for mouse wheel scrolling
## Each scroll event multiplies/divides zoom by this factor
## Used in: tileset_panel.gd for zoom-in/out
## Default: 1.1 (10% zoom per scroll = smooth incremental zoom)
const TILESET_ZOOM_STEP: float = 1.1

## Minimum zoom level (percentage of original texture size)
## Prevents zooming out too far and losing detail
## Used in: tileset_panel.gd for zoom limits
## Default: 0.25 (25% = 4x zoom out)
const TILESET_MIN_ZOOM: float = 0.25

## Maximum zoom level (percentage of original texture size)
## Prevents zooming in too far (pixelation limit)
## Used in: tileset_panel.gd for zoom limits
## Default: 4.0 (400% = 4x zoom in)
const TILESET_MAX_ZOOM: float = 4.0

## Default zoom level (100% = original texture size)
## Used when loading tileset or resetting zoom
## Used in: tileset_panel.gd for initial zoom state
## Default: 1.0 (100%)
const TILESET_DEFAULT_ZOOM: float = 1.0

#endregion
# ==============================================================================
#region HELPER FUNCTIONS
# ==============================================================================

## NOTE: Tile key formatting is now handled by TilePlacementManager.make_tile_key()
## This centralizes all placement logic in one location while respecting TILE_KEY_PRECISION constant

## Creates the custom AABB with current grid_size scaling
## Useful if you need to adjust AABB based on actual grid_size
## Usage:
static func get_scaled_aabb(grid_size: float) -> AABB:
	return AABB(
		CHUNK_CUSTOM_AABB.position * grid_size,
		CHUNK_CUSTOM_AABB.size * grid_size
	)

## Returns dotted line dash length scaled by grid_size
## Usage:
##   var dash_len = GlobalConstants.get_dash_length(grid_size)
static func get_dash_length(grid_size: float) -> float:
	return DOTTED_LINE_DASH_LENGTH * grid_size

## Returns plane overlay push-back distance scaled by grid_size
## Usage:
##   var push_back = GlobalConstants.get_plane_pushback(grid_size)
static func get_plane_pushback(grid_size: float) -> float:
	return PLANE_OVERLAY_PUSH_BACK * grid_size

## Returns visual grid offset scaled by grid_size
## This is PURELY VISUAL and does NOT affect any placement logic
## Usage:
##   var offset = GlobalConstants.get_visual_grid_offset(grid_size)
static func get_visual_grid_offset(grid_size: float) -> Vector3:
	return VISUAL_GRID_LINES_OFFSET * grid_size

## Returns visual grid push-back distance scaled by grid_size
## Pushes grid lines slightly behind their plane to prevent Z-fighting
## Returns Vector3 with per-axis push-back values
## Usage:
##   var push_back = GlobalConstants.get_visual_grid_pushback(grid_size)
##   depth_offset = Vector3.RIGHT * push_back.x  # For YZ plane
static func get_visual_grid_pushback(grid_size: float) -> Vector3:
	return VISUAL_GRID_LINES_PUSH_BACK * grid_size

#endregion

# ==============================================================================
#region AUTO-FLIP SYSTEM CONSTANTS
# ==============================================================================

## Default auto-flip setting for new projects
## When enabled, tile faces automatically flip based on camera-facing direction
const DEFAULT_ENABLE_AUTO_FLIP: bool = true

#endregion
# ==============================================================================
#region TILE HIGHLIGHT OVERLAY CONSTANTS
# ==============================================================================

## Maximum number of tiles that can be highlighted simultaneously
## Used in: tilemap_layer_3d.gd for highlight overlay MultiMesh instance count
## Limits the highlight overlay pool size for performance
## Increased to 1000 for large area erase operations
## Note: If selection exceeds this, tiles are still erased but not all highlighted
const MAX_HIGHLIGHTED_TILES: int = 2500

## Tile highlight overlay color (semi-transparent yellow)
## Used in: tilemap_layer_3d.gd for highlight MultiMesh material
## Shows which existing tiles will be replaced during placement
## Default: Color(1.0, 0.9, 0.0, 0.5) - Yellow with 50% opacity
const TILE_HIGHLIGHT_COLOR: Color = Color(1.0, 0.9, 0.0, 0.05)

#endregion
# ==============================================================================
#region AREA FILL SELECTION CONSTANTS
# ==============================================================================

## Area fill selection box color (semi-transparent cyan)
## Used in: AreaFillSelector3D for visual feedback during Shift+Drag
## Shows the rectangular area being selected for fill/erase
## Default: Color(0.0, 0.8, 1.0, 0.3) - Cyan with 30% opacity
const AREA_FILL_BOX_COLOR: Color = Color(0.0, 0.8, 1.0, 0.3)

## Area fill grid line color (brighter cyan)
## Used in: AreaFillSelector3D for grid visualization within selection area
## Shows individual grid cells that will be filled
## Default: Color(0.0, 0.8, 1.0, 0.6) - Cyan with 40% opacity
const AREA_FILL_GRID_LINE_COLOR: Color = Color(0.0, 0.8, 1.0, 0.4)

## Area fill box outline thickness
## Used in: AreaFillSelector3D for edge rendering
## Controls visual weight of selection boundary
## Default: 0.05 (thin outline)
const AREA_FILL_BOX_THICKNESS: float = 0.05

## Minimum area fill size (prevents accidental tiny selections)
## Used in: AreaFillSelector3D to validate selection size
## Must drag at least this distance to register as area fill
## Default: Vector3(0.1, 0.1, 0.1) - 1/10th of a grid cell
const MIN_AREA_FILL_SIZE: Vector3 = Vector3(0.1, 0.1, 0.1)

## Maximum tiles in single area fill operation
## Prevents performance issues and accidental massive fills
## Used in: TilePlacementManager.fill_area_with_undo()
## Default: 10000 (100x100 area max)
const MAX_AREA_FILL_TILES: int = 10000

## Confirmation threshold for large area fills
## Prompts user before filling areas larger than this
## Used in: Plugin area fill confirmation dialog
## Prevents accidental large operations
## Default: 500 tiles
const AREA_FILL_CONFIRM_THRESHOLD: int = 500

## Area erase selection tolerance across the same plane
## Expands area erase selection box in all directions in the plane
## Higher values = more forgiving selection (easier to catch tiles near edges)
## Applied as percentage +/- tolerance to bounding box min/max corners
const AREA_ERASE_SURFACE_TOLERANCE: float = 0.5

## Depth tolerance for area erase (in grid units) on "depth" axis (ONLY on depth axis (perpendicular to orientation plane))
##   Must be > 0 to handle floating point precision issues
## Small value catches tiles at same depth despite float rounding
## Too large causes cross-layer bleed (catches tiles above/below intended layer) (recommend between 0.5 and 2.0)
const AREA_ERASE_DEPTH_TOLERANCE: float = 0.5

#  Spatial indexing bucket size (in grid units)
# Larger values = fewer buckets but more tiles per bucket check
# Smaller values = more buckets but faster queries
const SPATIAL_INDEX_BUCKET_SIZE: float = 10.0

# ==============================================================================
# DEBUG FLAGS
# ==============================================================================
#region DEBUG FLAGS
# ==============================================================================
# Debug flags for performance monitoring and troubleshooting
# Set to false for production builds to eliminate debug overhead
# ==============================================================================

## Enable chunk management debug output
const DEBUG_CHUNK_MANAGEMENT: bool = false

## Enable batch update debug output
const DEBUG_BATCH_UPDATES: bool = false

## Enable area operation performance logging
const DEBUG_AREA_OPERATIONS: bool = false

## Enable data integrity validation
const DEBUG_DATA_INTEGRITY: bool = false

## Enable spatial index performance logging
const DEBUG_SPATIAL_INDEX: bool = false

#endregion

