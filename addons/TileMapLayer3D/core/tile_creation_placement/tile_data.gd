@tool
class_name TilePlacerData
extends Resource

## Data wrapper for tile information in MultiMesh architecture
## Responsibility: Data storage ONLY
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
	multimesh_instance_index = -1
