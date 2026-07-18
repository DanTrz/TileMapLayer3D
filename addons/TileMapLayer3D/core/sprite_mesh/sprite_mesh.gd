@icon("icons/sprite_mesh.svg")
class_name SpriteMesh
extends Resource
# Based on https://github.com/98teg/SpriteMesh by 98teg (MIT).

@export var meshes: Array[ArrayMesh] = []: set = set_meshes
@export var material: StandardMaterial3D = null: set = set_material


func _init():
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
