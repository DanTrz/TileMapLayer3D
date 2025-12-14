@icon("icons/sprite_mesh.svg")
class_name SpriteMesh
extends Resource
## [SpriteMesh] is a [Resource] that contains an array of meshes and their material.

## Array of meshes. Each mesh of the array represents a frame of the animation.
@export var meshes: Array[ArrayMesh] = []: set = set_meshes
## The meshes' material.
@export var material: StandardMaterial3D = null: set = set_material


func _init():
	# Create unique material instance per SpriteMesh (avoid shared default resource)
	if material == null:
		material = StandardMaterial3D.new()


func set_meshes(new_meshes: Array[ArrayMesh]) -> void:
	if meshes != new_meshes:
		meshes = new_meshes
		emit_changed()


func set_material(new_material: StandardMaterial3D) -> void:
	if material != new_material:
		material = new_material
		emit_changed()


func get_meshes() -> Array[ArrayMesh]:
	return meshes


func get_material() -> StandardMaterial3D:
	return material
