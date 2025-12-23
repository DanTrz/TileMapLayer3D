@tool
class_name TilePlacerData
extends Resource

## ⚠️⚠️⚠️ DEPRECATED - DO NOT USE IN NEW CODE ⚠️⚠️⚠️
##
## This class is being PHASED OUT and exists ONLY for:
## 1. UNDO/REDO operations (tile_placement_manager.gd stores TilePlacerData for history)
## 2. MIGRATION from old Array[TilePlacerData] saved_tiles format
## 3. RUNTIME tile tracking in _placement_data dictionary (NOT for storage!)
##
## ❌ DO NOT USE FOR:
## - Saving tiles to persistent storage (use save_tile_data_direct() instead)
## - Loading/rebuilding tiles from scene files (read columnar arrays directly)
## - Creating new tiles (pass params directly to add_tile_direct())
## - Any new features or systems
##
## ✅ PREFERRED APIS:
## - For STORAGE: tilemap_layer_3d.save_tile_data_direct()
## - For LOADING: Read columnar arrays directly in _rebuild_chunks_from_saved_data()
## - For NEW TILES: tilemap_layer_3d.add_tile_direct()
##
## WHY DEPRECATED:
## - Creates dual defaults (0.1 for new tiles vs 1.0 for old tiles)
## - Causes unnecessary object allocations (TilePlacerData → columnar conversion)
## - Slower than direct columnar writes
## - Architectural bandaid that should be eliminated
## - Will be removed once undo/redo system refactored to use direct API
##
## Data wrapper for tile information in MultiMesh architecture
## Responsibility: RUNTIME tracking ONLY (NOT for persistent storage - DEPRECATED)
## Note: Renamed from TileData to avoid conflict with Godot's built-in TileData class

@export var uv_rect: Rect2 = Rect2()

## Grid position - supports half-grid positioning (0.5, 1.5, 2.5...)
## COORDINATE LIMITS: Valid range is ±3,276.7 on each axis.
## Positions beyond this range will be clamped by TileKeySystem, causing
## incorrect tile placement and potential key collisions.
## See TileKeySystem and GlobalConstants.MAX_GRID_RANGE for details.
@export var grid_position: Vector3 = Vector3.ZERO

@export var orientation: int = 0  # TilePlacementManager.TileOrientation enum value
@export var mesh_rotation: int = 0  # Mesh rotation: 0-3 (0°, 90°, 180°, 270°)
@export var mesh_mode: int = GlobalConstants.DEFAULT_MESH_MODE  # Square or Triangle
@export var is_face_flipped: bool = false  # Face flip: true = back face visible (F key)

## Terrain ID for autotiled tiles (-1 = not autotiled, manual placement)
## When >= 0, this tile was placed via autotiling and belongs to that terrain
@export var terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN

# ==============================================================================
# TRANSFORM PARAMETERS FOR DATA PERSISTENCY
# ==============================================================================
## These values are saved at placement time to ensure tiles are reconstructed
## with the exact same transform parameters, even if GlobalConstants change.
## A value of 0.0 indicates "use GlobalConstants" (backward compatibility).

## Spin angle in radians used for Q/E rotation (0.0 = use GlobalConstants.SPIN_ANGLE_RAD)
## Saved at placement time to preserve rotation when SPIN_ANGLE_RAD changes
@export var spin_angle_rad: float = 0.0

## Tilt angle in radians for tilted orientations (0.0 = use GlobalConstants.TILT_ANGLE_RAD)
## Saved at placement time to preserve tilt when TILT_ANGLE_RAD changes
@export var tilt_angle_rad: float = 0.0

## Diagonal scale factor for 45° tiles (0.0 = use GlobalConstants.DIAGONAL_SCALE_FACTOR)
## Saved at placement time to preserve gap compensation when scale factor changes
@export var diagonal_scale: float = 0.0

## Tilt position offset factor (0.0 = use GlobalConstants.TILT_POSITION_OFFSET_FACTOR)
## Saved at placement time to preserve position offset for tilted tiles
@export var tilt_offset_factor: float = 0.0

## Depth scale for BOX/PRISM mesh modes (0.1 = default thin tiles, 1.0 = full unit depth)
## Only affects BOX_MESH and PRISM_MESH modes - FLAT modes ignore this value.
## Applied via Transform3D scaling on the depth_axis (per-instance, not per-mesh).
##
## ⚠️ CRITICAL: DUAL DEFAULT VALUES FOR BACKWARD COMPATIBILITY ⚠️
## - NEW tiles (placement): Default is 0.1 (thin tiles) - set here and in UI
## - OLD tiles (storage): Default is 1.0 (full depth) - sparse storage threshold
##
## WHY: Old scenes (before depth_scale feature) have tiles with no stored depth_scale.
## These must load with 1.0 (their original thickness). Sparse storage checks != 1.0,
## so old tiles with implicit 1.0 were never stored. If rebuild code uses this class's
## 0.1 default, old tiles would incorrectly appear thin!
##
## SOLUTION: In _rebuild_chunks_from_saved_data(), NEVER use get_tile_at()/TilePlacerData.
## Read columnar arrays directly with depth_scale defaulting to 1.0 for backward compat.
## See CLAUDE.md "Depth Scale Feature" for complete documentation.
@export var depth_scale: float = 0.1

# MultiMesh instance index (which instance in the MultiMesh this tile corresponds to)
# NOTE: This is runtime only and not saved
var multimesh_instance_index: int = -1

##  Resets this object to default state for object pooling
## Called before returning object to pool for reuse
func reset() -> void:
	uv_rect = Rect2()
	grid_position = Vector3.ZERO
	orientation = 0
	mesh_rotation = 0
	mesh_mode = GlobalConstants.DEFAULT_MESH_MODE
	is_face_flipped = false
	terrain_id = GlobalConstants.AUTOTILE_NO_TERRAIN
	# Transform parameters (0.0 = use GlobalConstants)
	spin_angle_rad = 0.0
	tilt_angle_rad = 0.0
	diagonal_scale = 0.0
	tilt_offset_factor = 0.0
	# NOTE: depth_scale reset to 0.1 for new tiles, but sparse storage checks against 1.0
	# This is for backward compatibility with old scenes
	depth_scale = 0.1  # 0.1 = default thin tiles for new placements
	multimesh_instance_index = -1
