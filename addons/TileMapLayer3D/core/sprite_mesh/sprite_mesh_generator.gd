extends RefCounted
class_name SpriteMeshGenerator


static func generate_sprite_mesh_instance(current_tilemap_node: TileMapLayer3D, current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float) -> void:

	var sprite_mesh_instance :SpriteMeshInstance = await generate_sprite_mesh_node(current_texture, selected_tiles, tile_size, grid_size)
	if not sprite_mesh_instance:
		push_warning("SpriteMeshGenerator: Failed to generate SpriteMeshInstance.")
		return
	

	# print("Starting to add SpriteMeshInstance to TileMapLayer3D node as child...")
	current_tilemap_node.add_child(sprite_mesh_instance)
	var scene_root: Node = current_tilemap_node.get_tree().edited_scene_root
	sprite_mesh_instance.owner = scene_root

	# print("Adding SpriteMeshInstance to TileMapLayer3D node completed.")

	# Generate the Mesh for SpriteMesh and assign materials for final update
	generate_mesh_for_sprite_mesh_instance(sprite_mesh_instance)



	

static func generate_mesh_for_sprite_mesh_instance(sprite_mesh_instance: SpriteMeshInstance) -> void:
	# print("Start generating sprite mesh...")

	#TODO: Potentially Option to add a Material Override to add our own material later
	sprite_mesh_instance.mesh = sprite_mesh_instance._generate_sprite_mesh().meshes[0]
	sprite_mesh_instance.material_override = sprite_mesh_instance._generate_material()
	sprite_mesh_instance._request_update()

	# await sprite_mesh_instance.mesh_instance_updated
static func generate_sprite_mesh_node(current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float) -> SpriteMeshInstance:
	var atlas_image: Image = current_texture.get_image()
	if not atlas_image:return

	#Get the total area (bounding rect) of the selected tiles
	var first_rect: Rect2 = selected_tiles[0]
	var last_rect: Rect2 = selected_tiles[selected_tiles.size() - 1]
	var bounding_rect := Rect2(
		first_rect.position,
		last_rect.position + last_rect.size - first_rect.position
	)

	#Get the image (as a copy) from the atlas region defined by the bounding rect (selected tiles)
	var tile_image: Image = atlas_image.get_region(Rect2i(bounding_rect))
	var tile_texture: ImageTexture = ImageTexture.create_from_image(tile_image)
	if not tile_texture:return

	#calculate world size based on number of tiles selected and grid size
	var tiles_wide: int = (last_rect.position.x - first_rect.position.x) / tile_size.x + 1
	var tiles_tall: int = (last_rect.position.y - first_rect.position.y) / tile_size.y + 1
	var selection_tile_size := Vector2(tiles_wide * grid_size, tiles_tall * grid_size)


	#calculate pixel size for Sprite Mesh generation. Relative to grid size.
	var total_tex_size := tile_texture.get_size()
	if total_tex_size.x <= 0 or total_tex_size.y <= 0: return
	var pixel_size = selection_tile_size.x / total_tex_size.x


	#Create an instance of SpriteMesh Instance and set its properties
	var sprite_mesh_instance :SpriteMeshInstance = SpriteMeshInstance.new()
	sprite_mesh_instance.spritemesh_texture = tile_texture as Texture2D
	sprite_mesh_instance.pixel_size = pixel_size
	sprite_mesh_instance.double_sided = true #TODO: Potentially add this as an option in the UI later
	sprite_mesh_instance.depth = 5.0 #TODO: Potentially add this as an option in the UI later
	sprite_mesh_instance.region_enabled = false #TODO: Potentially add this as an option to simplify and avoid us having to create a new texture laters


	# print("SpriteMehs Instance Node created WITHOUT mesh")


	if not sprite_mesh_instance:
		return null
	return sprite_mesh_instance






