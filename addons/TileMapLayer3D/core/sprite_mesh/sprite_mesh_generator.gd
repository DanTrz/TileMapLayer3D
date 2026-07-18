extends RefCounted
class_name SpriteMeshGenerator


##Integration and based on (https://github.com/98teg/SpriteMesh)** by [98teg](https://github.com/98teg) - A Godot plugin for creating 3D meshes from 2D sprites. Licensed under the MIT License.

static var _material_cache: Dictionary = {}

static func generate_sprite_mesh_instance(current_TileMapLayer3D: TileMapLayer3D, current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float, tile_cursor_position: Vector3, filter_mode: int = 0, undo_redo: Object = null) -> void:

	var sprite_mesh_instance: SpriteMeshInstance = generate_sprite_mesh_node(current_texture, selected_tiles, tile_size, grid_size)
	if not sprite_mesh_instance:
		push_warning("SpriteMeshGenerator: Failed to generate SpriteMeshInstance.")
		return

	var scene_root: Node = current_TileMapLayer3D.get_tree().edited_scene_root

	generate_mesh(sprite_mesh_instance, current_texture, filter_mode, current_TileMapLayer3D)

	var first_rect: Rect2 = selected_tiles[0]
	var last_rect: Rect2 = selected_tiles[selected_tiles.size() - 1]
	var tiles_tall: int = int((last_rect.position.y - first_rect.position.y) / tile_size.y) + 1
	var total_height: float = tiles_tall * grid_size

	var local_position: Vector3 = tile_cursor_position - current_TileMapLayer3D.global_position
	var adjusted_position: Vector3 = Vector3(
		local_position.x,
		local_position.y + (total_height / 2.0),
		local_position.z
	)

	sprite_mesh_instance.position = adjusted_position

	if undo_redo:
		undo_redo.create_action("Create SpriteMesh")
		undo_redo.add_do_method(current_TileMapLayer3D, "add_child", sprite_mesh_instance)
		undo_redo.add_do_method(sprite_mesh_instance, "set_owner", scene_root)
		undo_redo.add_undo_method(current_TileMapLayer3D, "remove_child", sprite_mesh_instance)
		undo_redo.commit_action()
	else:
		current_TileMapLayer3D.add_child(sprite_mesh_instance)
		sprite_mesh_instance.owner = scene_root

static func generate_sprite_mesh_node(current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float) -> SpriteMeshInstance:
	if not current_texture:
		return null

	var first_rect: Rect2 = selected_tiles[0]
	var last_rect: Rect2 = selected_tiles[selected_tiles.size() - 1]
	var bounding_rect := Rect2(
		first_rect.position,
		last_rect.position + last_rect.size - first_rect.position
	)

	var tiles_wide: int = int((last_rect.position.x - first_rect.position.x) / tile_size.x) + 1
	var tiles_tall: int = int((last_rect.position.y - first_rect.position.y) / tile_size.y) + 1
	var selection_tile_size := Vector2(tiles_wide * grid_size, tiles_tall * grid_size)

	var total_tex_size := Vector2(bounding_rect.size)
	if total_tex_size.x <= 0 or total_tex_size.y <= 0:
		return null
	var pixel_size: float = selection_tile_size.x / total_tex_size.x

	var sprite_mesh_instance: SpriteMeshInstance = SpriteMeshInstance.new()
	sprite_mesh_instance.spritemesh_texture = current_texture
	sprite_mesh_instance.region_enabled = true
	sprite_mesh_instance.region_rect = Rect2i(bounding_rect)
	sprite_mesh_instance.pixel_size = pixel_size
	sprite_mesh_instance.double_sided = true
	sprite_mesh_instance.depth = 5.0

	return sprite_mesh_instance

static func find_matching_sprite_mesh(parent_node: Node, texture: Texture2D, region_rect: Rect2i) -> SpriteMesh:
	if not texture:
		return null

	var texture_path: String = texture.resource_path

	for child in parent_node.get_children():
		if child is SpriteMeshInstance:
			var existing: SpriteMeshInstance = child
			if existing.spritemesh_texture and existing.spritemesh_texture.resource_path == texture_path:
				if existing.region_enabled and existing.region_rect == region_rect:
					if existing.generated_sprite_mesh and existing.generated_sprite_mesh.meshes.size() > 0:
						return existing.generated_sprite_mesh

	return null


static func generate_mesh(sprite_mesh_instance: SpriteMeshInstance, atlas_texture: Texture2D, filter_mode: int = 0, parent_node: Node = null) -> void:
	if parent_node:
		var existing_sprite_mesh: SpriteMesh = find_matching_sprite_mesh(
			parent_node,
			atlas_texture,
			sprite_mesh_instance.region_rect
		)
		if existing_sprite_mesh:
			sprite_mesh_instance.generated_sprite_mesh = existing_sprite_mesh
			return

	var material: StandardMaterial3D = get_or_create_material(atlas_texture, filter_mode)
	var sprite_mesh: SpriteMesh = sprite_mesh_instance._generate_sprite_mesh(material)

	sprite_mesh_instance.generated_sprite_mesh = sprite_mesh

static func get_or_create_material(texture: Texture2D, filter_mode: int) -> StandardMaterial3D:
	var cache_key: String = texture.resource_path + "_" + str(filter_mode)

	if _material_cache.has(cache_key):
		return _material_cache[cache_key]

	var material: StandardMaterial3D = GlobalUtil.create_baked_mesh_material(
		texture,
		filter_mode,
		0,
		true,
		true
	)

	_material_cache[cache_key] = material
	return material
