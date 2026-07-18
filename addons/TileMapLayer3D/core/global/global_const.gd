extends RefCounted
class_name GlobalConstants

# Must match in placement, rebuild, and preview — mismatch = preview offset from placed tiles
const GRID_ALIGNMENT_OFFSET: Vector3 = Vector3(0.5, 0.5, 0.5)

const DEFAULT_GRID_SIZE: float = 1.0
const DEFAULT_GRID_SNAP_SIZE: float = 1.0
const DEFAULT_GRID_SNAP: float = DEFAULT_GRID_SNAP_SIZE

# True limit is ±3276.7; use ±2500 to stay clear of clamp errors
const MAX_GRID_RANGE: float = 2500.0

# Half-grid (0.5) is the smallest supported; 0.25/0.125 are not
const MIN_SNAP_SIZE: float = 0.5

const GRID_PRECISION: float = 0.1

const MAX_RECOMMENDED_TILES: int = 50000

const TILE_COUNT_WARNING_THRESHOLD: float = 0.95

# Max distance from cursor tiles can be placed on the active plane (grid cells)
const MAX_CANVAS_DISTANCE: float = 20.0

const DEFAULT_CURSOR_STEP_SIZE: float = 1.0

const CURSOR_CENTER_CUBE_SIZE: Vector3 = Vector3(0.2, 0.2, 0.2)

const CURSOR_AXIS_LINE_THICKNESS: float = 0.05

const DEFAULT_CURSOR_START_POSITION: Vector3 = Vector3.ZERO

const CURSOR_X_AXIS_COLOR: Color = Color(1, 0, 0, 0.6)

const CURSOR_Y_AXIS_COLOR: Color = Color(0, 1, 0, 0.6)

const CURSOR_Z_AXIS_COLOR: Color = Color(0, 0, 1, 0.6)

const CURSOR_CENTER_COLOR: Color = Color(1, 1, 1, 0.8)

const DEFAULT_CROSSHAIR_LENGTH: float = 20.0

const YZ_PLANE_COLOR: Color = Color(1, 0, 0, 0.0)

const XZ_PLANE_COLOR: Color = Color(0, 1, 0, 0.0)

const XY_PLANE_COLOR: Color = Color(0, 0, 1, 0.0)

const DEFAULT_GRID_EXTENT: int = 20

const DEFAULT_GRID_LINE_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)

const ACTIVE_OVERLAY_ALPHA: float = 0.01

const ACTIVE_GRID_LINE_ALPHA: float = 0.5

const PLANE_OVERLAY_PUSH_BACK: float = -0.01

# Multiplier — actual dash = DOTTED_LINE_DASH_LENGTH * grid_size
const DOTTED_LINE_DASH_LENGTH: float = 0.25

# Purely cosmetic offset of visual grid lines; does not affect logic
const VISUAL_GRID_LINES_OFFSET: Vector3 = Vector3.ZERO

# Per-axis push-back; differs per axis because camera angle affects required offset
const VISUAL_GRID_LINES_PUSH_BACK: Vector3 = Vector3(-0.1, -0.1, 0.1)

const PREVIEW_GRID_INDICATOR_SIZE: Vector3 = Vector3(0.15, 0.15, 0.15)

const PREVIEW_GRID_INDICATOR_COLOR: Color = Color(1.0, 0.8, 0.0, 0.9)

const DEFAULT_PREVIEW_COLOR: Color = Color(1, 1, 1, 0.7)

const PREVIEW_POOL_SIZE: int = 48

const PREVIEW_UPDATE_INTERVAL: float = 0.033

const PREVIEW_MIN_MOVEMENT: float = 1.0

# Multiplied by current snap size to get minimum grid movement per preview update
const PREVIEW_GRID_MOVEMENT_MULTIPLIER: float = 1.0

const PLACEMENT_MODE_NAMES: Array[String] = ["CURSOR_PLANE", "CURSOR", "RAYCAST"]

const PAINT_UPDATE_INTERVAL: float = 0.050

const MIN_PAINT_GRID_DISTANCE: float = 0.01

const RAYCAST_MAX_DISTANCE: float = 1000.0

# Rays with abs(denom) below this are treated as parallel — no valid intersection
const PARALLEL_PLANE_THRESHOLD: float = 0.0001

# Q/E spin step
const SPIN_ANGLE_RAD: float =  PI/2

const MAX_SPIN_ROTATION_STEPS = 4

# R/F tilt step
const TILT_ANGLE_RAD: float = PI / 4.0

# Backward compatibility only — do not use
const TILT_POSITION_OFFSET_FACTOR: float = 0.5

# √2 non-uniform scale applied to the perpendicular axis so 45° tiles fill the grid without gaps
const DIAGONAL_SCALE_FACTOR: float = 1.41421356237

# Tiny normal-direction nudge to prevent Z-fighting between opposite-facing flat tiles (FLAT_SQUARE/FLAT_TRIANGULE only)
const FLAT_TILE_ORIENTATION_OFFSET: float = 0.0001

const DECAL_NODE_OFFSET: float = 0.0005

# Per-orientation BOX/PRISM Z-fighting offsets, index = TileOrientation (0-25).
# Values are unique per-axis so coplanar faces always separate; tune only via BOX_PRISM_Z_OFFSET_SCALE.
const BOX_PRISM_Z_OFFSET_SCALE: float = 0.0005
const BOX_PRISM_ORIENTATION_OFFSETS: Array[Vector3] = [
	Vector3(-1.0000, -1.0000, -1.0000),
	Vector3( 0.2361, -0.3634, -0.2642),
	Vector3(-0.8279,  0.2732,  0.8715),
	Vector3( 0.7082,  0.9099, -0.7927),
	Vector3(-0.3507, -0.4535, -0.3700),
	Vector3(-0.6197,  0.1831,  0.6788),
	Vector3( 0.4164,  0.8197, -0.5854),
	Vector3(-0.3475, -0.5437,  0.1503),
	Vector3( 0.8885,  0.0930,  0.8861),
	Vector3( 0.2246,  0.7296, -0.3782),
	Vector3(-0.6393, -0.6338,  0.3576),
	Vector3( 0.5967,  0.0028, -0.9067),
	Vector3(-0.1672,  0.6394, -0.1709),
	Vector3(-0.9311, -0.7239,  0.5649),
	Vector3( 0.3050, -0.0873, -0.6994),
	Vector3(-0.4590,  0.5493,  0.0364),
	Vector3( 0.4771, -0.8141,  0.7721),
	Vector3( 0.5132, -0.1775, -0.4921),
	Vector3(-0.7508,  0.4592,  0.2437),
	Vector3( 0.4853, -0.9042,  0.9794),
	Vector3(-0.2786, -0.2676, -0.2848),
	Vector3( 0.9574,  0.3690,  0.4509),
	Vector3( 0.1935, -0.9944, -0.8133),
	Vector3(-0.5704, -0.3577, -0.0775),
	Vector3( 0.6656,  0.2789,  0.6582),
	Vector3(-0.1983,  0.9155, -0.6060),
]

# Experimental alternative offsets — NOT WIRED UP. Wider per-axis separation (gap 0.08);
# needs BOX_PRISM_Z_OFFSET_SCALE ~= 0.006 for a ~0.0005 world nudge.
const BOX_PRISM_ORIENTATION_OFFSETS_ALTERNATIVE: Array[Vector3] = [
	Vector3(-1.0000, -1.0000, -1.0000),
	Vector3(-0.9200, -0.4400, -0.1200),
	Vector3(-0.8400, +0.1200, +0.7600),
	Vector3(-0.7600, +0.6800, -0.4400),
	Vector3(-0.6800, -0.8400, +0.4400),
	Vector3(-0.6000, -0.2800, -0.7600),
	Vector3(-0.5200, +0.2800, +0.1200),
	Vector3(-0.4400, +0.8400, +1.0000),
	Vector3(-0.3600, -0.6800, -0.2000),
	Vector3(-0.2800, -0.1200, +0.6800),
	Vector3(-0.2000, +0.4400, -0.5200),
	Vector3(-0.1200, +1.0000, +0.3600),
	Vector3(-0.0400, -0.5200, -0.8400),
	Vector3(+0.0400, +0.0400, +0.0400),
	Vector3(+0.1200, +0.6000, +0.9200),
	Vector3(+0.2000, -0.9200, -0.2800),
	Vector3(+0.2800, -0.3600, +0.6000),
	Vector3(+0.3600, +0.2000, -0.6000),
	Vector3(+0.4400, +0.7600, +0.2800),
	Vector3(+0.5200, -0.7600, -0.9200),
	Vector3(+0.6000, -0.2000, -0.0400),
	Vector3(+0.6800, +0.3600, +0.8400),
	Vector3(+0.7600, +0.9200, -0.3600),
	Vector3(+0.8400, -0.6000, +0.5200),
	Vector3(+0.9200, -0.0400, -0.6800),
	Vector3(+1.0000, +0.5200, +0.2000),
]

# Tile size in the texture atlas (pixels), not world size
const DEFAULT_TILE_SIZE: Vector2i = Vector2i(32, 32)

const CURSOR_STEP_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

const GRID_SNAP_OPTIONS: Array[float] = [1.0, 0.5]

# Indices map to BaseMaterial3D.TextureFilter
const TEXTURE_FILTER_OPTIONS: Array[String] = [
	"Nearest",
	"Nearest Mipmap",
	"Linear",
	"Linear Mipmap"
]

const DEFAULT_TEXTURE_FILTER: int = 0

# Pixel inset for UV clamping to prevent texture bleeding
const DEFAULT_PIXEL_INSET: float = 0.25

const MAX_TEXTURE_FILTER_MODE: int = 3

enum Tile_UV_Select_Mode {
	TILE = 0,
	POINTS = 1
}

const CHUNK_MAX_TILES: int = 1000

# Region cube side (world units). Larger = fewer chunks (CPU-friendly), smaller = GPU-friendly.
const CHUNK_REGION_SIZE: float = 30.0

# +1 on each side catches boundary tiles that would otherwise miss culling
const CHUNK_LOCAL_AABB: AABB = AABB(
	Vector3(-0.5, -0.5, -0.5),
	Vector3(CHUNK_REGION_SIZE + 1.0, CHUNK_REGION_SIZE + 1.0, CHUNK_REGION_SIZE + 1.0)
)

const DEFAULT_RENDER_PRIORITY: int = 0

const PREVIEW_RENDER_PRIORITY: int = 5

const HIGHLIGHT_RENDER_PRIORITY: int = 10

const AREA_FILL_RENDER_PRIORITY: int = 10

const GRID_OVERLAY_RENDER_PRIORITY: int = 10

enum MeshMode {
	FLAT_SQUARE = 0,
	FLAT_TRIANGULE = 1,
	BOX_MESH = 2,
	PRISM_MESH = 3,
	FLAT_ARCH = 4,
	FLAT_ARCH_I = 5,
	FLAT_ARCH_CORNER = 6,
	FLAT_ARCH_CORNER_I = 7,
	FLAT_ARCH_CORNER_CAP = 8,
	FLAT_ARCH_CORNER_CAP_I = 9,
	FLAT_ARCH_CORNER_C = 10,
	FLAT_ARCH_CORNER_C_I = 11,
	FLAT_ARCH_CORNER_S = 12,
	FLAT_ARCH_CORNER_S_I = 13,
	FLAT_ARCH_CORNER_CAP_DUO = 14
}

const DEFAULT_MESH_MODE: MeshMode = MeshMode.FLAT_SQUARE

const MESH_THICKNESS_RATIO: float = 1.0

# Edge stripe width for BOX/PRISM side faces as fraction of tile UV (0-1)
const MESH_SIDE_UV_STRIPE_RATIO: float = 0.1

# BOX/PRISM REPEAT shader: side faces have |n.y| below this; top/bottom/caps ~= 1
const BOX_SIDE_NORMAL_Y_THRESHOLD: float = 0.5

enum TextureRepeatMode {
	DEFAULT = 0,
	REPEAT = 1
}

enum DepthGrowthMode {
	OUTWARD = 0,
	INWARD  = 1
}

# Bit 17 in _tile_flags (v2): keep UV fixed when mesh is rotated via Q/E
const TILE_FLAG_BIT_FREEZE_UV: int = 17

# Bit 20 in _tile_flags (v2): 0=OUTWARD, 1=INWARD (BOX/PRISM). Old scenes default 0.
const TILE_FLAG_BIT_DEPTH_GROWTH_MODE: int = 20

const ARCH_ARC_SEGMENTS: int = 8

const ARCH_DEFAULT_RADIUS_RATIO: float = 0.2

const ARCH_MIN_RADIUS_RATIO: float = 0.1

const ARCH_MAX_RADIUS_RATIO: float = 0.5

enum BakeMode {
	NORMAL = 0,
	ALPHA_AWARE = 1
}

const DEFAULT_COLLISION_LAYER: int = 1

const DEFAULT_COLLISION_MASK: int = 1

const SAVE_FOLDER_NAME: String = "_SavedData"

# Pixels with alpha above this count as solid
const DEFAULT_ALPHA_THRESHOLD: float = 0.5

const TILESET_ZOOM_STEP: float = 1.1

const TILESET_MIN_ZOOM: float = 0.1

const TILESET_MAX_ZOOM: float = 4.0

const TILESET_DEFAULT_ZOOM: float = 1.0

# Sizes at 100% editor scale; multiply by EditorInterface.get_editor_scale()
const UI_DIALOG_SIZE_DEFAULT: Vector2i = Vector2i(800, 600)

const UI_DIALOG_SIZE_CONFIRM: Vector2i = Vector2i(450, 200)

const UI_MARGIN_SMALL: int = 2

const UI_MARGIN_MEDIUM: int = 4

const UI_MARGIN_LARGE: int = 5

const UI_MIN_LIST_HEIGHT: int = 100

const UI_COLOR_PICKER_WIDTH: int = 32

static func get_dash_length(grid_size: float) -> float:
	return DOTTED_LINE_DASH_LENGTH * grid_size

static func get_plane_pushback(grid_size: float) -> float:
	return PLANE_OVERLAY_PUSH_BACK * grid_size

static func get_visual_grid_offset(grid_size: float) -> Vector3:
	return VISUAL_GRID_LINES_OFFSET * grid_size

static func get_visual_grid_pushback(grid_size: float) -> Vector3:
	return VISUAL_GRID_LINES_PUSH_BACK * grid_size

const DEFAULT_ENABLE_AUTO_FLIP: bool = true

# Selections beyond this are still erased but not all highlighted
const MAX_HIGHLIGHTED_TILES: int = 2500

const TILE_HIGHLIGHT_COLOR: Color = Color(1.0, 0.9, 0.0, 0.05)

const VERTEX_TILE_HIGHLIGHT_COLOR: Color = Color(0.0, 0.8, 1.0, 0.08)

# Shown when cursor is outside valid coordinate range
const TILE_BLOCKED_HIGHLIGHT_COLOR: Color = Color(1.0, 0.0, 0.0, 0.6)

const HIGHLIGHT_BOX_SCALE: float = 1.05

const BLOCKED_HIGHLIGHT_BOX_SCALE: float = 1.1

const HIGHLIGHT_BOX_THICKNESS: float = 0.1

const BLOCKED_HIGHLIGHT_BOX_THICKNESS: float = 0.15

const AREA_FILL_BOX_COLOR: Color = Color(0.0, 0.8, 1.0, 0.3)

const AREA_FILL_GRID_LINE_COLOR: Color = Color(0.0, 0.8, 1.0, 0.4)

const AREA_FILL_BOX_THICKNESS: float = 0.05

const MIN_AREA_FILL_SIZE: Vector3 = Vector3(0.1, 0.1, 0.1)

const MAX_AREA_FILL_TILES: int = 10000

# Expands area-erase box in-plane; higher = more forgiving edge selection
const AREA_ERASE_SURFACE_TOLERANCE: float = 0.5

# Must be > 0 for float rounding; too large bleeds across layers (recommend 0.5-2.0)
const AREA_ERASE_DEPTH_TOLERANCE: float = 0.5

const SPATIAL_INDEX_BUCKET_SIZE: float = 10.0

const DEBUG_CHUNK_MANAGEMENT: bool = false

const DEBUG_BATCH_UPDATES: bool = false

const DEBUG_AREA_OPERATIONS: bool = false

const DEBUG_DATA_INTEGRITY: bool = false

const DEBUG_SPATIAL_INDEX: bool = false

const DEBUG_PICK_RAYCAST: bool = false

# Runs validate_columnar_data_quality() after every columnar mutation; editor-only, dev opt-in
const DEBUG_VALIDATE_AFTER_MUTATION: bool = false

const DEBUG_BAKE_PROFILE: bool = false

const DEBUG_CHUNK_BOUNDS_COLOR: Color = Color(0.0, 1.0, 1.0, 0.6)

enum MainAppMode {
	MANUAL = 0,
	AUTOTILE = 1,
	SETTINGS = 2,
	SMART_OPERATIONS = 3,
	ANIMATED_TILES = 4,
	SCULPT = 5,
	VERTEX_EDIT = 6
}

enum TilSetTab {
	MANUAL = MainAppMode.MANUAL,
	AUTOTILE = MainAppMode.AUTOTILE,
	SETTINGS = MainAppMode.SETTINGS,

}

enum SmartOperationsMainMode {
	SMART_SELECT = 0,
	SMART_FILL = 1,
}

enum SmartSelectionMode {
	SINGLE_PICK = 0,
	CONNECTED_UV = 1,
	CONNECTED_NEIGHBOR = 2,
	CONNECTED_TILE_TYPE = 3,
	HORIZONTAL_LOOP = 4,
}

enum SmartFillMode {
	FILL_RAMP = 0,
	FILL_GAP = 1,
}

const SMART_FILL_START_MARKER_COLOR: Color = Color(0.0, 0.9, 0.0, 0.5)
const SMART_FILL_PREVIEW_COLOR: Color = Color(0.0, 0.8, 1.0, 0.3)

enum SmartSelectionOperation {
	REPLACE_UV = 0,
	DELETE = 1,
	CLEAR = 2,
	REPLACE_MESH_TYPE = 3,
}



const BUTTOM_CONTEXT_UI_SIZE = 32
const BUTTOM_MAIN_UI_SIZE = 36


const AUTOTILE_NO_TERRAIN: int = -1

const AUTOTILE_DEFAULT_TERRAIN_SET: int = 0

const AUTOTILE_DEFAULT_SOURCE_ID: int = 0

const AUTOTILE_NO_SEED: int = -2147483648
const AUTOTILE_VARIANT_DEFAULT_INDEX: int = 0
const AUTOTILE_HASH_PRIME_Y: int = 73856093
const AUTOTILE_HASH_PRIME_Z: int = 19349663

const STATUS_WARNING_COLOR: Color = Color(1.0, 0.7, 0.2)
const STATUS_DEFAULT_COLOR: Color = Color(0.7, 0.7, 0.7)

const TERRAIN_COLOR_MIN: float = 0.3
const TERRAIN_COLOR_MAX: float = 0.9


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

const AUTOTILE_BITMASK_CARDINALS: int = 15

const AUTOTILE_BITMASK_ALL: int = 255

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

const CUSTOM_DATA_ANIMATED: String = "Animated"
const CUSTOM_DATA_VARIANT_TILE: String = "VariantTile"
const CUSTOM_DATA_COLLECTION_TILES: String = "CollectionTiles"
const CUSTOM_DATA_COLLISION: String = "Collision"


const SCULPT_BRUSH_SIZE_DEFAULT: int = 2

const SCULPT_DRAG_SENSITIVITY: float = 0.05

const SCULPT_FLOOR_ORIENTATION: int = 0

## Number of line segments for the circular brush ring outline.
## 32 segments = visually smooth circle at typical editor zoom levels.
const SCULPT_RING_SEGMENTS: int = 32

## Y offset applied to all gizmo geometry to prevent z-fighting with floor plane.
## Larger than FLAT_TILE_ORIENTATION_OFFSET (0.0001) because gizmo quads are
## drawn on top of existing tiles and need more clearance to stay visible.
const SCULPT_GIZMO_FLOOR_OFFSET: float = 0.005

const SCULPT_CELL_GAP_FACTOR: float = 0.9

enum SculptCellType {
	SQUARE = 0,
	TRI_NE = 1,
	TRI_NW = 2,
	TRI_SE = 3,
	TRI_SW = 4,
	ARCH_CAP_NE = 5,
	ARCH_CAP_NW = 6,
	ARCH_CAP_SE = 7,
	ARCH_CAP_SW = 8,
}

enum SculptBrushType {
	DIAMOND = 0,
	SQUARE = 1,
	ERASE = 2,
	ARCHED_RECT = 3,

}

const SCULPT_CELL_TO_TILE: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 3),
	Vector2i(1, 0),
	Vector2i(1, 2),
	Vector2i(1, 1),
	Vector2i(MeshMode.FLAT_ARCH_CORNER_CAP, 0),
	Vector2i(MeshMode.FLAT_ARCH_CORNER_CAP, 3),
	Vector2i(MeshMode.FLAT_ARCH_CORNER_CAP, 1),
	Vector2i(MeshMode.FLAT_ARCH_CORNER_CAP, 2),
]

const SCULPT_WALL_SOUTH: Vector3 = Vector3(0.0, 0.5, 2)
const SCULPT_WALL_NORTH: Vector3 = Vector3(0.0, -0.5, 3)
const SCULPT_WALL_EAST: Vector3 = Vector3(0.5, 0.0, 5)
const SCULPT_WALL_WEST: Vector3 = Vector3(-0.5, 0.0, 4)

const SCULPT_TRI_TILT_WALL: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(0, -0.5, 11),
	Vector3(0, -0.5, 10),
	Vector3(0, -0.5, 14),
	Vector3(-0.5, 0, 24),
	Vector3.ZERO,
	Vector3.ZERO,
	Vector3.ZERO,
	Vector3.ZERO,
]

const SCULPT_TRI_LEGS: Array = [
	[[0, 1], [0, -1], [1, 0], [-1, 0]],
	[[0, -1], [1, 0]],
	[[0, -1], [-1, 0]],
	[[0, 1], [1, 0]],
	[[0, 1], [-1, 0]],
	[[0, 1], [-1, 0]],
	[[0, 1], [1, 0]],
	[[0, -1], [-1, 0]],
	[[0, -1], [1, 0]],
]


enum ArchTurnDir { NE = 0, NW = 1, SE = 2, SW = 3 }

const ARCH_CONVEX_WALL1: Array = [
	[MeshMode.FLAT_ARCH_CORNER, 2, 0],
	[MeshMode.FLAT_ARCH_CORNER, 2, 2],
	[MeshMode.FLAT_ARCH_CORNER, 3, 2],
	[MeshMode.FLAT_ARCH_CORNER, 3, 0],
]
const ARCH_CONVEX_WALL2: Array = [
	[MeshMode.FLAT_ARCH_CORNER, 5, 2],
	[MeshMode.FLAT_ARCH_CORNER, 4, 0],
	[MeshMode.FLAT_ARCH_CORNER, 5, 0],
	[MeshMode.FLAT_ARCH_CORNER, 4, 2],
]
const ARCH_CONVEX_CAP: Array = [
	[MeshMode.FLAT_ARCH_CORNER_CAP, 0, 0],
	[MeshMode.FLAT_ARCH_CORNER_CAP, 0, 3],
	[MeshMode.FLAT_ARCH_CORNER_CAP, 0, 1],
	[MeshMode.FLAT_ARCH_CORNER_CAP, 0, 2],
]

const ARCH_CONCAVE_WALL1: Array = [
	[MeshMode.FLAT_ARCH_CORNER_I, 3, 2],
	[MeshMode.FLAT_ARCH_CORNER_I, 3, 0],
	[MeshMode.FLAT_ARCH_CORNER_I, 2, 0],
	[MeshMode.FLAT_ARCH_CORNER_I, 2, 2],
]
const ARCH_CONCAVE_WALL2: Array = [
	[MeshMode.FLAT_ARCH_CORNER_I, 4, 0],
	[MeshMode.FLAT_ARCH_CORNER_I, 5, 2],
	[MeshMode.FLAT_ARCH_CORNER_I, 4, 2],
	[MeshMode.FLAT_ARCH_CORNER_I, 5, 0],
]
const ARCH_CONCAVE_CAP: Array = [
	[MeshMode.FLAT_ARCH_CORNER_CAP_I, 0, 0],
	[MeshMode.FLAT_ARCH_CORNER_CAP_I, 0, 3],
	[MeshMode.FLAT_ARCH_CORNER_CAP_I, 0, 1],
	[MeshMode.FLAT_ARCH_CORNER_CAP_I, 0, 2],
]

const ARCH_CORNER_OFFSETS: Array = [
	[-0.5, 0.0, 0.0, -0.5, -0.5, -0.5],
	[0.5, 0.0, 0.0, -0.5, 0.5, -0.5],
	[-0.5, 0.0, 0.0, 0.5, -0.5, 0.5],
	[0.5, 0.0, 0.0, 0.5, 0.5, 0.5],
]

const ARCH_CONVEX_FLAT_WALL_REMOVAL: Array = [
	[0.0, -0.5, 3, 0.5, 0.0, 5],
	[0.0, -0.5, 3, -0.5, 0.0, 4],
	[0.0, 0.5, 2, 0.5, 0.0, 5],
	[0.0, 0.5, 2, -0.5, 0.0, 4],
]

const ARCH_STAIRCASE_STEP: Array = [
	[1, -1],
	[1, 1],
	[-1, -1],
	[-1, 1],
]

const ARCH_STAIRCASE_S_WALL_A: Array = [
	[MeshMode.FLAT_ARCH_CORNER_S, 2, 0],
	[MeshMode.FLAT_ARCH_CORNER_S, 2, 2],
	[MeshMode.FLAT_ARCH_CORNER_S, 5, 0],
	[MeshMode.FLAT_ARCH_CORNER_S, 3, 0],
]
const ARCH_STAIRCASE_S_WALL_B: Array = [
	[MeshMode.FLAT_ARCH_CORNER_S, 5, 2],
	[MeshMode.FLAT_ARCH_CORNER_S, 4, 0],
	[MeshMode.FLAT_ARCH_CORNER_S, 3, 2],
	[MeshMode.FLAT_ARCH_CORNER_S, 4, 2],
]
const ARCH_STAIRCASE_S_STEP_OFFSET: Array = [
	[0.5, -0.5],
	[-0.5, -0.5],
	[0.5, 0.5],
	[-0.5, 0.5],
]

const ARCH_SHARP_C: Array = [
	[MeshMode.FLAT_ARCH_CORNER_C, 2, 0],
	[MeshMode.FLAT_ARCH_CORNER_C, 3, 0],
	[MeshMode.FLAT_ARCH_CORNER_C, 4, 0],
	[MeshMode.FLAT_ARCH_CORNER_C, 5, 0],
]
const ARCH_SHARP_C_CAP_DUO: Array = [
	[MeshMode.FLAT_ARCH_CORNER_CAP_DUO, 0, 0, 0.0, -0.5],
	[MeshMode.FLAT_ARCH_CORNER_CAP_DUO, 0, 2, 0.0, 0.5],
	[MeshMode.FLAT_ARCH_CORNER_CAP_DUO, 0, 3, 0.5, 0.0],
	[MeshMode.FLAT_ARCH_CORNER_CAP_DUO, 0, 1, -0.5, 0.0],
]

const ARCH_STAIRCASE_CAP_ROT: Array = [0, 3, 1, 2]
const ARCH_STAIRCASE_CAPI_ROT: Array = [2, 1, 3, 0]

const ARCH_STAIRCASE_CAPI_OFFSET: Array = [
	[1, 0],
	[0, 1],
	[0, -1],
	[-1, 0],
]

const VERTEX_HANDLE_COLOR: Color = Color(1.0, 0.2, 0.2, 1.0)

const VERTEX_HANDLE_SIZE: float = 0.05

const VERTEX_WIREFRAME_COLOR: Color = Color(1.0, 0.4, 0.4, 0.8)

const VERTEX_TILE_WARNING_THRESHOLD: int = 100
