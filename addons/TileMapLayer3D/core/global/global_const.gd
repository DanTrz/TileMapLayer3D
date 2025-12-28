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

# ==============================================================================
#region COORDINATE SYSTEM LIMITS
# ==============================================================================
## These constants define the hard limits of the tile coordinate encoding system.
## See TileKeySystem for implementation details.
##
## The system uses 64-bit integer keys to encode tile positions for O(1) lookups.
## Each axis uses 16-bit signed integers, with COORD_SCALE=10.0 for fixed-point encoding.

## Maximum grid coordinate range from origin (0,0,0)
## Tiles can be placed from -3276.7 to +3276.7 on any axis
## Beyond this range, coordinates will be clamped causing placement errors
## For extra safety, use ±2500.0 as practical limit
const MAX_GRID_RANGE: float = 2500.0 # 3276.7

## Minimum supported grid snap size
## The coordinate system precision (0.1) supports half-grid (0.5) positioning
## Smaller snap sizes (0.25, 0.125) are NOT supported
const MIN_SNAP_SIZE: float = 0.5

## Grid coordinate precision (smallest representable difference)
## Derived from TileKeySystem.COORD_SCALE = 10.0
## Positions are rounded to this precision during encoding
const GRID_PRECISION: float = 0.1

## Maximum recommended tiles per TileMapLayer3D node (performance limit)
## Beyond this, consider using multiple TileMapLayer3D nodes for better performance
## This is a soft limit - the system will still work but may degrade
const MAX_RECOMMENDED_TILES: int = 50000

## Warning threshold percentage for tile count
## When tile count reaches this percentage of MAX_RECOMMENDED_TILES, a warning is shown
## Default: 0.95 (95%) - warns before hitting the limit
const TILE_COUNT_WARNING_THRESHOLD: float = 0.95

## Chunk capacity warning threshold (percentage)
## When a chunk reaches this percentage of capacity, a warning is shown in debug info
## Default: 90.0 (90% full triggers warning)
const CHUNK_WARNING_THRESHOLD: float = 90.0

## Multiplier for converting ratio to percentage
const PERCENT_MULTIPLIER: float = 100.0

#endregion
# ==============================================================================

## Maximum canvas distance from cursor (in grid cells)
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
## Controls how far cursor moves with keyboard:
## - 1.0 = move 1 full grid cell per keypress
## Default: 0.5 (half-grid movement for precision)
const DEFAULT_CURSOR_STEP_SIZE: float = 1.0

## 3D cursor center cube size (width, height, depth in world units)
const CURSOR_CENTER_CUBE_SIZE: Vector3 = Vector3(0.2, 0.2, 0.2)

## Cursor axis line thickness (cross-section size of axis lines)
## Thickness of the thin box mesh used for axis lines
const CURSOR_AXIS_LINE_THICKNESS: float = 0.05

## Default cursor start position (grid coordinates)
## Default: Vector3(0.5, 0.5, 0.5)
const DEFAULT_CURSOR_START_POSITION: Vector3 = Vector3.ZERO
#const DEFAULT_CURSOR_START_POSITION: Vector3 = Vector3(0.5, 0.5, 0.5)

## X-axis line color (Red)
## Default: Color(1, 0, 0, 0.6) - Red with 60% opacity
const CURSOR_X_AXIS_COLOR: Color = Color(1, 0, 0, 0.6)

## Y-axis line color (Green)
## Default: Color(0, 1, 0, 0.6) - Green with 60% opacity
const CURSOR_Y_AXIS_COLOR: Color = Color(0, 1, 0, 0.6)

## Z-axis line color (Blue)
## Default: Color(0, 0, 1, 0.6) - Blue with 60% opacity
const CURSOR_Z_AXIS_COLOR: Color = Color(0, 0, 1, 0.6)

## Cursor center cube color
## Default: Color.WHITE with alpha 0.8
const CURSOR_CENTER_COLOR: Color = Color(1, 1, 1, 0.8)

## Default cursor crosshair length (distance from center in each direction)
const DEFAULT_CROSSHAIR_LENGTH: float = 20.0

## YZ plane overlay base color (Red)
## Plane perpendicular to X-axis
## Default: Color(1, 0, 0, 0.0) - Red (alpha set dynamically)
const YZ_PLANE_COLOR: Color = Color(1, 0, 0, 0.0)

## XZ plane overlay base color (Green)
const XZ_PLANE_COLOR: Color = Color(0, 1, 0, 0.0)

## XY plane overlay base color (Blue)
const XY_PLANE_COLOR: Color = Color(0, 0, 1, 0.0)

## Default grid extent (number of grid lines in each direction)
## Default: 10  = show 10 lines in each direction (20 total lines)
const DEFAULT_GRID_EXTENT: int = 20

## Default grid line color
## Default: Color(0.5, 0.5, 0.5, 1.0) - Gray
const DEFAULT_GRID_LINE_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)

## Active plane overlay alpha (opacity when plane is active)
## Default: 0.025 (very subtle hint)
const ACTIVE_OVERLAY_ALPHA: float = 0.01

## Active plane grid line alpha
## Opacity of grid lines on the active plane
## Default: 0.5 (50% opacity)
const ACTIVE_GRID_LINE_ALPHA: float = 0.5

## Plane overlay push-back distance (prevents Z-fighting with tiles)
## Moves overlay slightly behind its plane to prevent visual flickering
const PLANE_OVERLAY_PUSH_BACK: float = -0.01

## Dotted line dash length (grid visualization)
## Length of each dash in the dotted grid lines
## Default: 0.25 * grid_size
## Note: This is a multiplier, actual value = DOTTED_LINE_DASH_LENGTH * grid_size
const DOTTED_LINE_DASH_LENGTH: float = 0.25

## Visual grid line offset (purely cosmetic - does NOT affect logic)
## Offsets ONLY the visual grid lines to create "grid cell" appearance
## This is independent of cursor axis, raycasting, and placement logic
## - Vector3(0.5, 0.5, 0.5) = grid lines appear centered in cells
## - Vector3.ZERO = grid lines align with cursor axis
## Default: Vector3(0.5, 0.5, 0.5)
const VISUAL_GRID_LINES_OFFSET: Vector3 = Vector3.ZERO #Vector3(0.5, 0.5, 0.5)

## Visual grid depth push-back per axis (prevents Z-fighting with cursor axis and tiles)
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
## The bright cube that shows exact grid position during preview
## Default: Vector3(0.15, 0.15, 0.15)
const PREVIEW_GRID_INDICATOR_SIZE: Vector3 = Vector3(0.15, 0.15, 0.15)

## Preview grid indicator color
## Bright yellow/orange for high visibility
## Default: Color(1.0, 0.8, 0.0, 0.9) - Yellow-orange with 90% opacity
const PREVIEW_GRID_INDICATOR_COLOR: Color = Color(1.0, 0.8, 0.0, 0.9)

## Default preview color/transparency
## Default: Color(1, 1, 1, 0.7) - White with 70% opacity
const DEFAULT_PREVIEW_COLOR: Color = Color(1, 1, 1, 0.7)

## Maximum preview instances for multi-tile selection
## Default: 48 (maximum tiles that can be selected at once)
const PREVIEW_POOL_SIZE: int = 48

##Area ERASE of more than 500 tiles is taking a long, long time. This was an attempt to control that.
const PREVIEW_UPDATE_INTERVAL: float = 0.033 

##  Movement threshold to reduce preview updates (5-10x fewer updates)
const PREVIEW_MIN_MOVEMENT: float = 1.0  # Minimum pixels to trigger preview update

## Preview update grid movement threshold multiplier
## Multiplied by current snap size to determine minimum grid movement
## Example: With 0.5 snap, threshold = 0.5 × 1.0 = 0.5 grid units
## Example: With 1.0 snap, threshold = 1.0 × 1.0 = 1.0 grid units (same as before)
## Default: 1.0 (ensures perfect backward compatibility with existing 1.0 snap behavior)
const PREVIEW_GRID_MOVEMENT_MULTIPLIER: float = 1.0

# =============================================================================
# PLACEMENT MODE NAMES (Debug/UI Display)
# =============================================================================
## Human-readable names for placement modes (PlacementMode enum indices)
## Used for debug output and UI display throughout the plugin
## Maps to: 0 = CURSOR_PLANE, 1 = CURSOR, 2 = RAYCAST
const PLACEMENT_MODE_NAMES: Array[String] = ["CURSOR_PLANE", "CURSOR", "RAYCAST"]

#endregion
# ==============================================================================
#region PAINTING MODE CONSTANTS
# ==============================================================================

## Paint mode update interval (time between paint operations while dragging)
## Controls how frequently tiles are placed during click-and-drag painting
## Lower = faster painting but more CPU usage
## Higher = slower painting but better performance
## Default: 0.050 (~20 tiles per second)
## Compare to PREVIEW_UPDATE_INTERVAL (0.033 = ~30fps for cursor preview)
const PAINT_UPDATE_INTERVAL: float = 0.050

## Minimum grid distance to consider positions different during painting
## If new position is within this distance of last painted position, skip it
## Prevents placing multiple tiles at the same grid cell during fast mouse drags
## Default: 0.01 (1% of grid cell = effectively same position)
const MIN_PAINT_GRID_DISTANCE: float = 0.01

#endregion
# ==============================================================================
#region RAYCAST CONSTANTS
# ==============================================================================

## Raycast maximum distance (how far ray travels from camera)
## When raycasting from camera to find placement position,
const RAYCAST_MAX_DISTANCE: float = 1000.0

## Parallel plane threshold (minimum dot product for valid plane intersection)
## When raycasting to cursor planes, if ray is nearly parallel to plane
## (abs(denom) < threshold), intersection is invalid.
## Default: 0.0001
const PARALLEL_PLANE_THRESHOLD: float = 0.0001

#endregion
# ==============================================================================
#region SPIN ORIENTATION ROTATION ANGLES (in radians)
# ==============================================================================
## These constants define rotation angles for tile SPIN orientations (rotation on the same axis).

## Default tile "SPIN" rotation degrees in radians 
## Used for wall spin orientations )opearations done with Q and E keys)
const SPIN_ANGLE_RAD: float =  PI/2  # 90 degrees = PI/2 (: float = PI / 2.0)

##Defines the maximum rotation steps for tiles (4 = 90 degree increments, 8 = 45 degree increments)
const MAX_SPIN_ROTATION_STEPS = 4 # TODO: Change this to 8 for 45 degree support (Also need to change apply_mesh_rotation)

#endregion
# ==============================================================================
#region TILE TILT ROTATION & SCALING SYSTEM (45° Tilt Support)
# ==============================================================================
## Constants for the 18-state orientation system (6 base + 12 tilted variants)
##  These constants enable ramps, roofs, and slanted walls


## 45° tilt angle for all angled tile orientations
## Used for operations done with R and F keys (tilt up/down or left/right)
## Pre-calculated for performance (avoid deg_to_rad() calls)
const TILT_ANGLE_RAD: float = PI / 4.0  # PI / 4.0 (OR 0.785398163397)


## This constant is kept for backward compatibility but should NOT be used
const TILT_POSITION_OFFSET_FACTOR: float = 0.5


##   Non-uniform scale factor for 45° rotated tiles to eliminate gaps
## Applied to ONE axis (X or Z) depending on rotation plane
## When a tile rotates 45°, we scale the perpendicular axis UP by √2
##
## Scaling by axis:
##   - Floor/Ceiling tilts (X-axis rotation): Scale Z (depth) by √2
##   - Wall N/S tilts (Y-axis rotation): Scale X (width) by √2
##   - Wall E/W tilts (X-axis rotation): Scale Z (depth) by √2
##
## Mathematical proof: 1.0m tile scaled to 1.414m, then rotated 45°
##   → projected dimension = 1.414 × cos(45°) ≈ 1.0m (perfect grid fit)
const DIAGONAL_SCALE_FACTOR: float = 1.41421356237  # sqrt(2.0)

## Default orientation offset: Applied to ALL flat tiles based on orientation
## Pushes each tile slightly along its surface normal to prevent Z-fighting
## when opposite-facing tiles occupy the same grid position.
## Value in world units - extremely small (0.1mm) to be imperceptible
## Only applies to FLAT_SQUARE and FLAT_TRIANGULE mesh types
const FLAT_TILE_ORIENTATION_OFFSET: float = 0.0001

#endregion
# ==============================================================================
#region TILE DEFAULT VALUES and UI OPTIONS (UI & Configuration)
# ==============================================================================

## Default tile size for tileset panel (pixels in atlas texture)
## This is the size of tiles in the TEXTURE ATLAS, not world size
const DEFAULT_TILE_SIZE: Vector2i = Vector2i(32, 32)

## Cursor step size options for dropdown
## NOTE: Minimum 0.5 due to coordinate system precision (COORD_SCALE=10.0)
## See TileKeySystem for coordinate encoding limits
const CURSOR_STEP_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

## Grid snap size options for dropdown
## Available options in the grid snapping dropdown
## NOTE: Minimum 0.5 (half-grid) due to coordinate system precision (COORD_SCALE=10.0)
## Smaller values (0.25, 0.125) are NOT supported - see TileKeySystem
const GRID_SNAP_OPTIONS: Array[float] = [1.0, 0.5]

## Texture filter mode options for dropdown
## Maps to Godot's BaseMaterial3D.TextureFilter enum
const TEXTURE_FILTER_OPTIONS: Array[String] = [
	"Nearest",           # 0 - TEXTURE_FILTER_NEAREST
	"Nearest Mipmap",    # 1 - TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	"Linear",            # 2 - TEXTURE_FILTER_LINEAR
	"Linear Mipmap"      # 3 - TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
]

## Default texture filter (Nearest for pixel-perfect rendering)
const DEFAULT_TEXTURE_FILTER: int = 0  # BaseMaterial3D.TEXTURE_FILTER_NEAREST

## Maximum valid texture filter mode index
## Used for validation in TilePlacementManager and UI
const MAX_TEXTURE_FILTER_MODE: int = 3

## Total count of texture filter options
## Used for array sizing and iteration
const TEXTURE_FILTER_COUNT: int = 4

#endregion
# ==============================================================================
#region TILE KEY FORMATTING
# ==============================================================================

## Precision for fractional grid positions in tile keys
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
const CHUNK_MAX_TILES: int = 1000

## Custom AABB for MultiMesh chunks (ensures tiles are always visible)
## Default: AABB(Vector3(-500, -10, -500), Vector3(1000, 20, 1000))
const CHUNK_CUSTOM_AABB: AABB = AABB(Vector3(-500, -10, -500), Vector3(1000, 20, 1000))

# =============================================================================
# RENDER PRIORITY CONSTANTS - SINGLE SOURCE OF TRUTH
# =============================================================================
# Render priority controls draw order for overlapping transparent objects.
# Higher values render ON TOP of lower values (drawn later in the render queue).
#
# IMPORTANT: These are the CANONICAL definitions. All files creating materials
# for visual feedback should reference these constants instead of hardcoding values.
#
# Used by:
#   - GlobalUtil material factory functions
#   - AreaFillSelector3D (selection box overlay)
#   - CursorPlaneVisualizer (grid plane overlays)
#   - TilePreview3D (ghost preview tiles)
#   - TileMapLayer3D (highlight overlays)
#
# Priority hierarchy (lowest to highest):
#   0  = Standard tiles (base layer)
#   5  = Tile preview (ghost showing where tile will be placed)
#   10 = Highlights and overlays (selection, area fill, hover feedback)
# =============================================================================

## Standard tiles - base render priority (no special treatment)
const DEFAULT_RENDER_PRIORITY: int = 0

## Tile preview - slightly above tiles so ghost is visible
const PREVIEW_RENDER_PRIORITY: int = 5

## Tile highlights - above tiles and previews for visibility
const HIGHLIGHT_RENDER_PRIORITY: int = 10

## Area fill selection box - same level as highlights
const AREA_FILL_RENDER_PRIORITY: int = 10

## Grid plane overlays - same level as highlights
const GRID_OVERLAY_RENDER_PRIORITY: int = 10

#endregion
# ==============================================================================
#region MESH MODE SYSTEM
# ==============================================================================

##Controls what type of Mesh are placing in the TileMapLayers
enum MeshMode {
	FLAT_SQUARE = 0,
	FLAT_TRIANGULE = 1,
	BOX_MESH = 2,
	PRISM_MESH = 3
}

const DEFAULT_MESH_MODE: int = 0  # Start with square mode

## Box/Prism mesh thickness as fraction of grid_size
## Used by BOX_MESH and PRISM_MESH modes
const MESH_THICKNESS_RATIO: float = 1.0

## Width of edge stripe for BOX/PRISM side faces (as fraction of tile UV 0-1)
## Side faces sample a thin column/row from the edge of the front texture
## 0.1 = 10% of tile texture width/height
const MESH_SIDE_UV_STRIPE_RATIO: float = 0.1

## Controls UV mapping mode for BOX_MESH and PRISM_MESH side faces
## DEFAULT = Edge stripes on side faces (current behavior)
## REPEAT = All faces use full texture (uniform UVs)
enum TextureRepeatMode {
	DEFAULT = 0,  # Side faces sample edge stripes from texture
	REPEAT = 1    # All faces use full tile texture (uniform)
}

#endregion
# ==============================================================================
#region BAKE MODE SYSTEM
# ==============================================================================

## Controls how tiles are baked into static meshes
## Used by TileMeshMerger for mesh baking operations
enum BakeMode {
	NORMAL = 0,         # Standard merge without alpha detection
	ALPHA_AWARE = 1,    # Custom alpha detection (excludes transparent pixels)
	STREAMING = 2       # For large tile counts (10,000+)
}

#endregion
# ==============================================================================
#region COLLISION SYSTEM
# ==============================================================================

## Default collision layer for generated collision shapes
## Bit 1 = layer 1 (default physics layer)
const DEFAULT_COLLISION_LAYER: int = 1

## Default collision mask for generated collision shapes
## Bit 1 = layer 1 (collides with default physics layer)
const DEFAULT_COLLISION_MASK: int = 1

## Default alpha threshold for sprite collision detection
## Pixels with alpha > this value are considered solid
## Range: 0.0 (all transparent) to 1.0 (only fully opaque)
const DEFAULT_ALPHA_THRESHOLD: float = 0.5

## Thickness of collision boxes for flat tiles
## DEPRECATED: Now using flat geometry (no thickness)
## Kept for backward compatibility, set to 0.0
const COLLISION_BOX_THICKNESS: float = 0.0

## Maximum number of cached collision shapes
## Prevents memory bloat from too many unique tile textures
const COLLISION_SHAPE_CACHE_MAX: int = 256

#endregion
# ==============================================================================
#region TILESET PANEL ZOOM CONSTANTS
# ==============================================================================

## Zoom step multiplier for mouse wheel scrolling
## Each scroll event multiplies/divides zoom by this factor
## Default: 1.1 (10% zoom per scroll = smooth incremental zoom)
const TILESET_ZOOM_STEP: float = 1.1

## Minimum zoom level (percentage of original texture size)
## Prevents zooming out too far and losing detail
## Default: 0.25 (25% = 4x zoom out)
const TILESET_MIN_ZOOM: float = 0.25

## Maximum zoom level (percentage of original texture size)
## Prevents zooming in too far (pixelation limit)
## Default: 4.0 (400% = 4x zoom in)
const TILESET_MAX_ZOOM: float = 4.0

## Default zoom level (100% = original texture size)
## Used when loading tileset or resetting zoom
## Default: 1.0 (100%)
const TILESET_DEFAULT_ZOOM: float = 1.0

#endregion
# ==============================================================================
#region UI SCALING CONSTANTS (DPI-aware)
# ==============================================================================

## Default dialog size for file dialogs (at 100% editor scale)
## Actual size will be scaled by EditorInterface.get_editor_scale()
const UI_DIALOG_SIZE_DEFAULT: Vector2i = Vector2i(800, 600)

## Small dialog size for confirmation dialogs (at 100% editor scale)
const UI_DIALOG_SIZE_CONFIRM: Vector2i = Vector2i(450, 200)

## Standard margin for content padding - small (at 100% editor scale)
## Used for: FoldableContainer margins, TileSetPlacementPanel margins
const UI_MARGIN_SMALL: int = 2

## Standard margin for section padding - medium (at 100% editor scale)
## Used for: AutotileTab main margin
const UI_MARGIN_MEDIUM: int = 4

## Standard margin for larger spacing (at 100% editor scale)
## Used for: Collision/Export tab margins
const UI_MARGIN_LARGE: int = 5

## Minimum height for list controls (at 100% editor scale)
## Used for: TerrainList in AutotileTab
const UI_MIN_LIST_HEIGHT: int = 100

## Minimum width for color picker buttons (at 100% editor scale)
## Used for: TerrainColorPicker in AutotileTab
const UI_COLOR_PICKER_WIDTH: int = 32

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
## Limits the highlight overlay pool size for performance
## Increased to 1000 for large area erase operations
## Note: If selection exceeds this, tiles are still erased but not all highlighted
const MAX_HIGHLIGHTED_TILES: int = 2500

## Tile highlight overlay color (semi-transparent yellow)
## Shows which existing tiles will be replaced during placement
## Default: Color(1.0, 0.9, 0.0, 0.5) - Yellow with 50% opacity
const TILE_HIGHLIGHT_COLOR: Color = Color(1.0, 0.9, 0.0, 0.05)

## Tile blocked highlight color (bright red for invalid positions)
## Shows when cursor is outside valid coordinate range (±3,276.7)
## Replaces normal preview to clearly indicate placement is blocked
## Default: Color(1.0, 0.0, 0.0, 0.6) - Bright red with 60% opacity
const TILE_BLOCKED_HIGHLIGHT_COLOR: Color = Color(1.0, 0.0, 0.0, 0.6)

#endregion
# ==============================================================================
#region AREA FILL SELECTION CONSTANTS
# ==============================================================================

## Area fill selection box color (semi-transparent cyan)
## Shows the rectangular area being selected for fill/erase
## Default: Color(0.0, 0.8, 1.0, 0.3) - Cyan with 30% opacity
const AREA_FILL_BOX_COLOR: Color = Color(0.0, 0.8, 1.0, 0.3)

## Area fill grid line color (brighter cyan)
## Shows individual grid cells that will be filled
## Default: Color(0.0, 0.8, 1.0, 0.6) - Cyan with 40% opacity
const AREA_FILL_GRID_LINE_COLOR: Color = Color(0.0, 0.8, 1.0, 0.4)

## Area fill box outline thickness
## Controls visual weight of selection boundary
## Default: 0.05 (thin outline)
const AREA_FILL_BOX_THICKNESS: float = 0.05

## Minimum area fill size (prevents accidental tiny selections)
## Must drag at least this distance to register as area fill
## Default: Vector3(0.1, 0.1, 0.1) - 1/10th of a grid cell
const MIN_AREA_FILL_SIZE: Vector3 = Vector3(0.1, 0.1, 0.1)

## Maximum tiles in single area fill operation
## Prevents performance issues and accidental massive fills
## Default: 10000 (100x100 area max)
const MAX_AREA_FILL_TILES: int = 10000

## Confirmation threshold for large area fills
## Prompts user before filling areas larger than this
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

# ==============================================================================
#region TILING MODE CONSTANTS
# ==============================================================================
## Constants for tiling mode selection (Manual vs Autotile)
## Used throughout the plugin for mode switching and state management
##
## IMPORTANT: These are the CANONICAL definitions. All files should reference
## these constants instead of hardcoding 0 or 1 for tiling mode checks.

## Manual tiling mode - user selects specific tiles from atlas
const TILING_MODE_MANUAL: int = 0

## Autotile mode - system selects tiles based on neighbor configuration
const TILING_MODE_AUTOTILE: int = 1

#endregion
# ==============================================================================
#region AUTOTILING CONSTANTS
# ==============================================================================
## Constants for the V5 hybrid autotiling system
## Uses Godot's native TileSet for terrain configuration

## Autotile: No terrain assigned (manual tile)
## Used to indicate manually placed tiles
const AUTOTILE_NO_TERRAIN: int = -1

## Autotile: Default terrain set index within TileSet
## Most TileSets use terrain set 0 as the primary set
const AUTOTILE_DEFAULT_TERRAIN_SET: int = 0

## Autotile: Default atlas source ID within TileSet
## Most TileSets use source 0 as the primary atlas
const AUTOTILE_DEFAULT_SOURCE_ID: int = 0

## UI Status Colors - used for status labels in AutotileTab
const STATUS_WARNING_COLOR: Color = Color(1.0, 0.7, 0.2)  # Yellow/orange for warnings
const STATUS_DEFAULT_COLOR: Color = Color(0.7, 0.7, 0.7)  # Gray for neutral status

## Terrain Color Generation - random HSV range for terrain list items
const TERRAIN_COLOR_MIN: float = 0.3
const TERRAIN_COLOR_MAX: float = 0.9

# =============================================================================
# AUTOTILE BITMASK VALUES - SINGLE SOURCE OF TRUTH
# =============================================================================
# These constants define the bitmask bit positions for 8-directional autotiling.
# Each direction corresponds to a specific bit in the 8-bit bitmask (0-255).
#
# IMPORTANT: These are the CANONICAL definitions used throughout the codebase.
# All autotile-related files should reference these constants, NOT define their own.
#
# Used by:
#   - TileSetBitmaskMapper (core/autotile/tileset_bitmask_mapper.gd)
#   - PlaneCoordinateMapper (core/autotile/plane_coordinate_mapper.gd)
#   - AutotileEngine (core/autotile/autotile_engine.gd)
#
# Bitmask Layout (8-bit integer, value range 0-255):
#   Bit 0 (value 1)   = North neighbor (top)
#   Bit 1 (value 2)   = East neighbor (right)
#   Bit 2 (value 4)   = South neighbor (bottom)
#   Bit 3 (value 8)   = West neighbor (left)
#   Bit 4 (value 16)  = Northeast corner
#   Bit 5 (value 32)  = Southeast corner
#   Bit 6 (value 64)  = Southwest corner
#   Bit 7 (value 128) = Northwest corner
#
# Visual representation (2D grid view):
#   NW(128)  N(1)   NE(16)
#   W(8)     [X]    E(2)
#   SW(64)   S(4)   SE(32)
#
# Common bitmask values:
#   0   = Isolated tile (no matching neighbors)
#   15  = Cross pattern (all 4 cardinals: N+E+S+W = 1+2+4+8)
#   255 = Fully surrounded (all 8 neighbors)
# =============================================================================

## North neighbor (top) - Bit 0
const AUTOTILE_BITMASK_N: int = 1

## East neighbor (right) - Bit 1
const AUTOTILE_BITMASK_E: int = 2

## South neighbor (bottom) - Bit 2
const AUTOTILE_BITMASK_S: int = 4

## West neighbor (left) - Bit 3
const AUTOTILE_BITMASK_W: int = 8

## Northeast corner - Bit 4
const AUTOTILE_BITMASK_NE: int = 16

## Southeast corner - Bit 5
const AUTOTILE_BITMASK_SE: int = 32

## Southwest corner - Bit 6
const AUTOTILE_BITMASK_SW: int = 64

## Northwest corner - Bit 7
const AUTOTILE_BITMASK_NW: int = 128

## Cardinal directions only (N+E+S+W) - useful for 4-directional autotiling
const AUTOTILE_BITMASK_CARDINALS: int = 15  # 1+2+4+8

## All 8 directions (fully surrounded) - maximum bitmask value
const AUTOTILE_BITMASK_ALL: int = 255

## Direction name to bitmask value mapping
## Used by PlaneCoordinateMapper for neighbor calculations
## Key: Direction string, Value: Bitmask bit value
const AUTOTILE_BITMASK_BY_DIRECTION: Dictionary = {
	"N": AUTOTILE_BITMASK_N,
	"E": AUTOTILE_BITMASK_E,
	"S": AUTOTILE_BITMASK_S,
	"W": AUTOTILE_BITMASK_W,
	"NE": AUTOTILE_BITMASK_NE,
	"SE": AUTOTILE_BITMASK_SE,
	"SW": AUTOTILE_BITMASK_SW,
	"NW": AUTOTILE_BITMASK_NW,
}

## Godot TileSet peering bit to bitmask value mapping
## Used by TileSetBitmaskMapper to convert Godot's peering bit enum to our bitmask
## Key: TileSet.CellNeighbor enum value, Value: Our bitmask bit value
## NOTE: This dictionary is populated at runtime since TileSet enum isn't available
## at const initialization time. Use get_peering_to_bitmask() helper instead.

#endregion

