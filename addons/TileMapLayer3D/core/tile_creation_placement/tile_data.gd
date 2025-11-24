@tool
class_name TilePlacerData
extends Resource

## Data wrapper for tile information in MultiMesh architecture
## Responsibility: Data storage ONLY
## Note: Renamed from TileData to avoid conflict with Godot's built-in TileData class

@export var uv_rect: Rect2 = Rect2()
@export var grid_position: Vector3 = Vector3.ZERO  # Supports fractional positioning (0.5, 1.75, 2.25...)
@export var orientation: int = 0  # TilePlacementManager.TileOrientation enum value
@export var mesh_rotation: int = 0  # Mesh rotation: 0-3 (0°, 90°, 180°, 270°)
@export var mesh_mode: int = GlobalConstants.DEFAULT_MESH_MODE  # Square or Triangle
@export var is_face_flipped: bool = false  # Face flip: true = back face visible (F key)

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
	multimesh_instance_index = -1
