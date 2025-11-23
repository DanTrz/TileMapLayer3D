class_name CollisionGenerator
extends RefCounted

## ============================================================================
## COLLISION GENERATOR FOR GODOT 2.5D TILE PLACER
## ============================================================================

# Preload dependencies
const GlobalUtil = preload("uid://mybww1in648r")
const SpriteCollisionGenerator = preload("uid://vy3vb7p2wfue")
## High-level orchestration for collision generation.
##
## Key Features:
## - Connected component analysis (automatic neighbor detection via flood fill)
## - Creates separate StaticBody3D per spatially connected tile group
## - Integrates with SpriteCollisionGenerator for smart shape generation
## - Applies collision layers and masks
## - Handles all tile orientations (FLOOR, CEILING, WALLS)

# ==============================================================================
## MAIN ENTRY POINT
# ==============================================================================

# static func generate_collisions_for_mesh(bake_mode: MeshBakeManager.BakeMode) -> StaticBody3D:
# 	pass





# ## Generates collision for all tiles, grouped by spatial connectivity
# ##
# ## @param tiles: Array of TilePlacerData to generate collision for
# ## @param tileset_texture: The tileset texture to sample for collision shapes
# ## @param grid_size: World size of tiles in 3D space
# ## @param alpha_threshold: Alpha cutoff for sprite collision generation
# ## @param collision_layer: Physics layer bits
# ## @param collision_mask: Physics mask bits
# ## @returns: Array of StaticBody3D nodes (one per connected tile group)
# static func generate_simple_collision_for_tiles(
# 	tiles: Array[TilePlacerData],
# 	tileset_texture: Texture2D,
# 	grid_size: float,
# 	alpha_threshold: float,
# 	collision_layer: int,
# 	collision_mask: int,
# 	tile_map3d_node: TileMapLayer3D = null
# ) -> Array[StaticCollisionBody3D]:

# 	if tiles.is_empty():
# 		print("CollisionGenerator: No tiles to generate collision for")
# 		return []

# 	if not tileset_texture:
# 		push_warning("CollisionGenerator: No tileset texture provided")
# 		return []

# 	print("CollisionGenerator: Generating collision for %d tiles..." % tiles.size())

# 	# 1. Group tiles by spatial connectivity (flood fill)
# 	var tile_groups = _find_connected_tile_groups(tiles)

# 	print("CollisionGenerator: Found %d connected tile groups" % tile_groups.size())

# 	# 2. Create StaticBody3D per group
# 	var collision_bodies: Array[StaticCollisionBody3D] = []

# 	for i in range(tile_groups.size()):
# 		var group = tile_groups[i]
# 		var body = _create_collision_for_group(
# 			group,
# 			tileset_texture,
# 			grid_size,
# 			alpha_threshold,
# 			i,  # Group index for naming
# 			tile_map3d_node
# 		)

# 		if body and body.get_child_count() > 0:
# 			body.collision_layer = collision_layer
# 			body.collision_mask = collision_mask
# 			collision_bodies.append(body)
# 		elif body:
# 			# Body was created but has no collision shapes (all transparent tiles)
# 			body.queue_free()

# 	print("CollisionGenerator: Created %d collision bodies" % collision_bodies.size())

# 	# Print cache statistics
# 	var stats = SpriteCollisionGenerator.get_cache_stats()
# 	print("CollisionGenerator: Shape cache stats - Hits: %d, Misses: %d, Hit rate: %.1f%%" % [
# 		stats.hits, stats.misses, stats.hit_rate * 100
# 	])

# 	return collision_bodies

# # ==============================================================================
# # CONNECTED COMPONENT ANALYSIS
# # ==============================================================================

# ## Finds connected groups of tiles using flood fill algorithm
# ## Two tiles are connected if they share an edge or corner (26-neighbor connectivity in 3D)
# ##
# ## @param tiles: Array of all tiles to group
# ## @returns: Array of Arrays, each containing tiles in a connected group
# static func _find_connected_tile_groups(tiles: Array[TilePlacerData]) -> Array[Array]:
# 	var visited: Dictionary = {}
# 	var groups: Array[Array] = []

# 	# Build lookup dictionary for O(1) tile queries
# 	var tile_dict: Dictionary = {}
# 	for tile in tiles:
# 		var tile_key = GlobalUtil.make_tile_key(tile.grid_position, tile.orientation)
# 		tile_dict[tile_key] = tile

# 	# Flood fill from each unvisited tile
# 	for tile in tiles:
# 		var tile_key = GlobalUtil.make_tile_key(tile.grid_position, tile.orientation)

# 		if not visited.has(tile_key):
# 			var group = _flood_fill_neighbors(tile, tile_dict, visited)
# 			if group.size() > 0:
# 				groups.append(group)

# 	return groups

# ## Flood fill to find all tiles connected to start_tile
# ## Uses BFS (breadth-first search) with 26-neighbor connectivity
# ##
# ## @param start_tile: Tile to start flood fill from
# ## @param tile_dict: Lookup dictionary (tile_key -> TilePlacerData)
# ## @param visited: Dictionary tracking visited tiles (modified in-place)
# ## @returns: Array of connected tiles
# static func _flood_fill_neighbors(
# 	start_tile: TilePlacerData,
# 	tile_dict: Dictionary,
# 	visited: Dictionary
# ) -> Array[TilePlacerData]:

# 	var group: Array[TilePlacerData] = []
# 	var queue: Array[TilePlacerData] = [start_tile]

# 	while queue.size() > 0:
# 		var current = queue.pop_front()
# 		var current_key = GlobalUtil.make_tile_key(current.grid_position, current.orientation)

# 		if visited.has(current_key):
# 			continue

# 		visited[current_key] = true
# 		group.append(current)

# 		# Check all 26 neighbors (3D grid: ±1 in X, Y, Z)
# 		# Only connect tiles with same orientation AND mesh_rotation to avoid weird collision groups
# 		for dx in [-1, 0, 1]:
# 			for dy in [-1, 0, 1]:
# 				for dz in [-1, 0, 1]:
# 					if dx == 0 and dy == 0 and dz == 0:
# 						continue  # Skip self

# 					var neighbor_pos = current.grid_position + Vector3(dx, dy, dz)
# 					var neighbor_key = GlobalUtil.make_tile_key(neighbor_pos, current.orientation)

# 					if tile_dict.has(neighbor_key) and not visited.has(neighbor_key):
# 						var neighbor_tile: TilePlacerData = tile_dict[neighbor_key]
# 						# Only group tiles with same mesh_rotation AND mesh_mode for accurate collision
# 						# This separates squares from triangles into different groups
# 						if neighbor_tile.mesh_rotation == current.mesh_rotation \
# 							and neighbor_tile.mesh_mode == current.mesh_mode:
# 							queue.append(neighbor_tile)

# 	return group

# # ==============================================================================
# # COLLISION BODY CREATION
# # ==============================================================================

# ## Creates StaticBody3D with collision shapes for a connected tile group
# ##
# ## CHUNKED APPROACH: Merges adjacent tiles into larger rectangular collision boxes.
# ## Inspired by Godot 4.4's TileMapLayer physics chunking (PR #102662).
# ## Significantly reduces collision shape count while maintaining accuracy.
# ##
# ## @param tiles: Array of tiles in this group
# ## @param tileset_texture: Texture to sample for collision shapes (unused)
# ## @param grid_size: World size of tiles
# ## @param alpha_threshold: Alpha cutoff for collision generation (unused)
# ## @param group_index: Index for naming the body
# ## @returns: StaticBody3D with CollisionShape3D children (merged rectangular chunks)
# static func _create_collision_for_group(
# 	tiles: Array[TilePlacerData],
# 	tileset_texture: Texture2D,
# 	grid_size: float,
# 	alpha_threshold: float,
# 	group_index: int,
# 	tile_map3d_node: TileMapLayer3D = null
# ) -> StaticCollisionBody3D:

# 	var static_body = StaticCollisionBody3D.new()
# 	static_body.name = "CollisionGroup_%d" % group_index

# 	if tiles.is_empty():
# 		return static_body

# 	# Get orientation from first tile (all tiles in group have same orientation)
# 	var orientation := tiles[0].orientation

# 	# Find rectangular chunks of adjacent tiles
# 	var chunks := _find_rectangular_chunks(tiles, orientation)

# 	# UNIFIED CONVEX COLLISION: Both triangles and squares now use ConvexPolygonShape3D
# 	# This eliminates BoxShape3D alignment issues with non-uniform scaling + rotation

# 	var shape_count := 0

# 	# Route to appropriate collision generator based on mesh_mode
# 	if tiles.size() > 0 and tiles[0].mesh_mode == GlobalConstants.MeshMode.MESH_TRIANGLE:
# 		# Triangle tiles: Use 6-point triangular prism
# 		var triangle_shapes := _create_triangle_collision_shapes(
# 			tiles,
# 			grid_size,
# 			group_index,
# 			tile_map3d_node
# 		)
# 		for shape in triangle_shapes:
# 			static_body.add_child(shape)

# 		shape_count = triangle_shapes.size()
# 		print("CollisionGenerator: Group %d - Created %d triangle collision shapes" % [
# 			group_index, shape_count
# 		])
# 	else:
# 		# Square tiles: Use 8-point rectangular prism
# 		# Check if chunking would be beneficial (30%+ reduction)
# 		var use_chunking := chunks.size() < tiles.size() * 0.7

# 		if use_chunking:
# 			# Dense arrangement - use chunked rectangles
# 			var square_shapes := _create_chunked_square_collision_shapes(
# 				tiles,
# 				chunks,
# 				grid_size,
# 				group_index,
# 				tile_map3d_node
# 			)
# 			for shape in square_shapes:
# 				static_body.add_child(shape)

# 			shape_count = square_shapes.size()
# 			print("CollisionGenerator: Group %d - Created %d chunked square shapes for %d tiles (%.1f%% reduction)" % [
# 				group_index, shape_count, tiles.size(), 100.0 * (1.0 - float(shape_count) / tiles.size())
# 			])
# 		else:
# 			# Sparse arrangement - individual convex boxes per tile
# 			var square_shapes := _create_square_collision_shapes(
# 				tiles,
# 				grid_size,
# 				group_index,
# 				tile_map3d_node
# 			)
# 			for shape in square_shapes:
# 				static_body.add_child(shape)

# 			shape_count = square_shapes.size()
# 			print("CollisionGenerator: Group %d - Sparse arrangement, using %d individual square shapes" % [
# 				group_index, shape_count
# 			])

# 	return static_body

# # ==============================================================================
# # TRIANGLE COLLISION GENERATION
# # ==============================================================================

# ## Creates ConvexPolygonShape3D collision for triangular tiles
# ## Each triangle gets a 6-point convex prism (3 bottom + 3 top vertices)
# ##
# ## Triangle geometry (LOCAL space, before transform):
# ##   Right-angled triangle with right angle at bottom-left corner
# ##   V0: Bottom-left (-0.5, 0, -0.5)
# ##   V1: Bottom-right (+0.5, 0, -0.5)
# ##   V2: Top-left (-0.5, 0, +0.5)
# ##   Hypotenuse: V1 to V2
# ##
# ## @param tiles: Array of triangle tiles (all same orientation + mesh_rotation)
# ## @param grid_size: World size of tiles
# ## @param group_index: Index for naming collision shapes
# ## @param tile_map3d_node: TileMapLayer3D reference for tilt offset calculation
# ## @returns: Array of CollisionShape3D nodes
# static func _create_triangle_collision_shapes(
# 	tiles: Array[TilePlacerData],
# 	grid_size: float,
# 	group_index: int,
# 	tile_map3d_node: TileMapLayer3D = null
# ) -> Array[CollisionShape3D]:

# 	var collision_shapes: Array[CollisionShape3D] = []
# 	var shape_count := 0

# 	for tile in tiles:
# 		var half_size := grid_size * 0.5
# 		var thickness := GlobalConstants.COLLISION_BOX_THICKNESS

# 		# CRITICAL: Create triangle points in LOCAL space (XZ plane, Y=thickness)
# 		# DO NOT pre-transform these points - let CollisionShape3D.transform handle it!
# 		# This ensures normals are calculated correctly by Godot's physics engine
# 		var local_points: PackedVector3Array = [
# 			Vector3(-half_size, 0.0, -half_size),      # Bottom face (3 points)
# 			Vector3(half_size, 0.0, -half_size),
# 			Vector3(-half_size, 0.0, half_size),
# 			Vector3(-half_size, thickness, -half_size), # Top face (3 points)
# 			Vector3(half_size, thickness, -half_size),
# 			Vector3(-half_size, thickness, half_size)
# 		]

# 		# Create convex shape with LOCAL space points (not pre-transformed)
# 		var convex_shape := ConvexPolygonShape3D.new()
# 		convex_shape.points = local_points

# 		# Create collision shape node
# 		var collision_shape := CollisionShape3D.new()
# 		collision_shape.shape = convex_shape
# 		collision_shape.name = "Triangle_%d" % shape_count

# 		# Build FULL transform (matches visual mesh system)
# 		# This applies orientation + mesh_rotation + position all at once
# 		var full_transform: Transform3D = GlobalUtil.build_tile_transform(
# 			tile.grid_position,
# 			tile.orientation,
# 			tile.mesh_rotation,
# 			grid_size,
# 			tile_map3d_node,  # For tilt offset calculation
# 			tile.is_face_flipped
# 		)

# 		# Set complete transform (basis + origin)
# 		# Godot's physics engine will correctly calculate normals from this
# 		collision_shape.transform = full_transform

# 		collision_shapes.append(collision_shape)
# 		shape_count += 1

# 	return collision_shapes

# # ==============================================================================
# # SQUARE COLLISION GENERATION
# # ==============================================================================

# ## Creates ConvexPolygonShape3D collision for individual square tiles
# ## Each square gets an 8-point convex box (4 bottom + 4 top vertices)
# ##
# ## CRITICAL APPROACH: Pre-transform the convex points with scale + orientation,
# ## then apply only position + mesh rotation to the collision shape.
# ## This avoids Godot physics engine issues with non-uniform scaling in transforms.
# ##
# ## @param tiles: Array of square tiles (all same orientation + mesh_rotation)
# ## @param grid_size: World size of tiles
# ## @param group_index: Index for naming collision shapes
# ## @param tile_map3d_node: TileMapLayer3D reference for tilt offset calculation
# ## @returns: Array of CollisionShape3D nodes
# static func _create_square_collision_shapes(
# 	tiles: Array[TilePlacerData],
# 	grid_size: float,
# 	group_index: int,
# 	tile_map3d_node: TileMapLayer3D = null
# ) -> Array[CollisionShape3D]:

# 	var collision_shapes: Array[CollisionShape3D] = []
# 	var shape_count := 0

# 	for tile in tiles:
# 		var half_size := grid_size * 0.5
# 		var thickness := GlobalConstants.COLLISION_BOX_THICKNESS

# 		# CRITICAL: Create square points in LOCAL space (XZ plane, Y=thickness)
# 		# DO NOT pre-transform these points - let CollisionShape3D.transform handle it!
# 		# This ensures normals are calculated correctly by Godot's physics engine
# 		var local_points: PackedVector3Array = [
# 			Vector3(-half_size, 0.0, -half_size),      # Bottom face (4 points)
# 			Vector3(half_size, 0.0, -half_size),
# 			Vector3(half_size, 0.0, half_size),
# 			Vector3(-half_size, 0.0, half_size),
# 			Vector3(-half_size, thickness, -half_size), # Top face (4 points)
# 			Vector3(half_size, thickness, -half_size),
# 			Vector3(half_size, thickness, half_size),
# 			Vector3(-half_size, thickness, half_size)
# 		]

# 		# Create convex shape with LOCAL space points (not pre-transformed)
# 		var convex_shape := ConvexPolygonShape3D.new()
# 		convex_shape.points = local_points

# 		# Create collision shape node
# 		var collision_shape := CollisionShape3D.new()
# 		collision_shape.shape = convex_shape
# 		collision_shape.name = "Square_%d" % shape_count

# 		# Build FULL transform (matches visual mesh system)
# 		# This applies orientation + mesh_rotation + position all at once
# 		var full_transform: Transform3D = GlobalUtil.build_tile_transform(
# 			tile.grid_position,
# 			tile.orientation,
# 			tile.mesh_rotation,
# 			grid_size,
# 			tile_map3d_node,  # For tilt offset calculation
# 			tile.is_face_flipped
# 		)

# 		# Set complete transform (basis + origin)
# 		# Godot's physics engine will correctly calculate normals from this
# 		collision_shape.transform = full_transform

# 		collision_shapes.append(collision_shape)
# 		shape_count += 1

# 	return collision_shapes

# ## Creates ConvexPolygonShape3D collision for chunked square tiles
# ## Chunks are merged rectangular groups of adjacent tiles for performance
# ##
# ## CRITICAL: Chunk dimensions are orientation-aware
# ## - XZ plane (FLOOR/CEILING): Width=X, Depth=Z
# ## - XY plane (WALL_NORTH/SOUTH): Width=X, Depth=Y
# ## - YZ plane (WALL_EAST/WEST): Width=Y, Depth=Z
# ##
# ## @param tiles: Array of all square tiles in group (for validation)
# ## @param chunks: Array of chunk dictionaries with "min" and "max" grid bounds
# ## @param grid_size: World size of tiles
# ## @param group_index: Index for naming collision shapes
# ## @param tile_map3d_node: TileMapLayer3D reference for tilt offset calculation
# ## @returns: Array of CollisionShape3D nodes
# static func _create_chunked_square_collision_shapes(
# 	tiles: Array[TilePlacerData],
# 	chunks: Array,
# 	grid_size: float,
# 	group_index: int,
# 	tile_map3d_node: TileMapLayer3D = null
# ) -> Array[CollisionShape3D]:

# 	var collision_shapes: Array[CollisionShape3D] = []
# 	var shape_count := 0

# 	# Get orientation from first tile to determine plane
# 	var orientation := tiles[0].orientation
# 	var plane_mode: String

# 	# Determine which plane we're working in (same logic as chunking)
# 	match orientation:
# 		GlobalUtil.TileOrientation.FLOOR, \
# 		GlobalUtil.TileOrientation.CEILING, \
# 		GlobalUtil.TileOrientation.FLOOR_TILT_POS_X, \
# 		GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X, \
# 		GlobalUtil.TileOrientation.CEILING_TILT_POS_X, \
# 		GlobalUtil.TileOrientation.CEILING_TILT_NEG_X:
# 			plane_mode = "XZ"  # Horizontal tiles - width=X, depth=Z

# 		GlobalUtil.TileOrientation.WALL_NORTH, \
# 		GlobalUtil.TileOrientation.WALL_SOUTH, \
# 		GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y, \
# 		GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y, \
# 		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y, \
# 		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y:
# 			plane_mode = "XY"  # North/South walls - width=X, depth=Y

# 		GlobalUtil.TileOrientation.WALL_EAST, \
# 		GlobalUtil.TileOrientation.WALL_WEST, \
# 		GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X, \
# 		GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X, \
# 		GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X, \
# 		GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X:
# 			plane_mode = "YZ"  # East/West walls - width=Y, depth=Z

# 		_:
# 			plane_mode = "XZ"  # Fallback

# 	for chunk in chunks:
# 		var chunk_min: Vector3 = chunk["min"]
# 		var chunk_max: Vector3 = chunk["max"]

# 		# Calculate chunk dimensions and center in grid space
# 		var chunk_size_grid := chunk_max - chunk_min + Vector3.ONE
# 		var chunk_center_grid := chunk_min + (chunk_size_grid - Vector3.ONE) * 0.5

# 		# Calculate scaled dimensions based on plane orientation
# 		# CRITICAL: Use correct axes for each plane!
# 		var half_width: float
# 		var half_depth: float
# 		var thickness := GlobalConstants.COLLISION_BOX_THICKNESS

# 		match plane_mode:
# 			"XZ":  # Floor/Ceiling: Width=X, Depth=Z
# 				half_width = (chunk_size_grid.x * grid_size) * 0.5
# 				half_depth = (chunk_size_grid.z * grid_size) * 0.5

# 			"XY":  # North/South walls: Width=X, Depth=Y
# 				half_width = (chunk_size_grid.x * grid_size) * 0.5
# 				half_depth = (chunk_size_grid.y * grid_size) * 0.5

# 			"YZ":  # East/West walls: Width=Y, Depth=Z
# 				half_width = (chunk_size_grid.y * grid_size) * 0.5
# 				half_depth = (chunk_size_grid.z * grid_size) * 0.5

# 			_:
# 				# Fallback to XZ dimensions
# 				half_width = (chunk_size_grid.x * grid_size) * 0.5
# 				half_depth = (chunk_size_grid.z * grid_size) * 0.5

# 		# CRITICAL: Create chunk box in LOCAL space (XZ plane, Y=thickness)
# 		# DO NOT pre-transform these points - let CollisionShape3D.transform handle it!
# 		# This ensures normals are calculated correctly by Godot's physics engine
# 		var local_points: PackedVector3Array = [
# 			Vector3(-half_width, 0.0, -half_depth),      # Bottom face (4 points)
# 			Vector3(half_width, 0.0, -half_depth),
# 			Vector3(half_width, 0.0, half_depth),
# 			Vector3(-half_width, 0.0, half_depth),
# 			Vector3(-half_width, thickness, -half_depth), # Top face (4 points)
# 			Vector3(half_width, thickness, -half_depth),
# 			Vector3(half_width, thickness, half_depth),
# 			Vector3(-half_width, thickness, half_depth)
# 		]

# 		# Get representative tile for orientation/rotation
# 		var representative_tile: TilePlacerData = tiles[0]

# 		# Create convex shape with LOCAL space points (not pre-transformed)
# 		var convex_shape := ConvexPolygonShape3D.new()
# 		convex_shape.points = local_points

# 		# Create collision shape node
# 		var collision_shape := CollisionShape3D.new()
# 		collision_shape.shape = convex_shape
# 		collision_shape.name = "SquareChunk_%d" % shape_count

# 		# Build FULL transform (matches visual mesh system)
# 		# This applies orientation + mesh_rotation + position all at once
# 		var full_transform: Transform3D = GlobalUtil.build_tile_transform(
# 			chunk_center_grid,
# 			representative_tile.orientation,
# 			representative_tile.mesh_rotation,
# 			grid_size,
# 			tile_map3d_node,  # For tilt offset calculation
# 			representative_tile.is_face_flipped
# 		)

# 		# Set complete transform (basis + origin)
# 		# Godot's physics engine will correctly calculate normals from this
# 		collision_shape.transform = full_transform

# 		collision_shapes.append(collision_shape)
# 		shape_count += 1

# 	return collision_shapes

# # ==============================================================================
# # RECTANGULAR CHUNKING (Inspired by Godot 4.4 TileMapLayer)
# # ==============================================================================

# ## Finds rectangular chunks of adjacent tiles to minimize collision shape count
# ## Uses a greedy algorithm to find the largest possible rectangles
# ##
# ## @param tiles: Array of tiles to chunk
# ## @param orientation: Tile orientation (determines which plane to work in)
# ## @returns: Array of chunk dictionaries with "min" and "max" Vector3 bounds
# static func _find_rectangular_chunks(tiles: Array[TilePlacerData], orientation: int) -> Array:
# 	var chunks: Array = []

# 	if tiles.is_empty():
# 		return chunks

# 	# Build a 3D grid of occupied positions for quick lookup
# 	var occupied: Dictionary = {}
# 	for tile in tiles:
# 		occupied[tile.grid_position] = true

# 	# Track which tiles have been assigned to chunks
# 	var assigned: Dictionary = {}

# 	# Determine which plane to work in based on orientation
# 	# Different wall orientations use different 2D planes for chunking
# 	var plane_mode: String
# 	match orientation:
# 		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
# 			plane_mode = "XZ"  # Horizontal tiles - expand in X and Z
# 		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
# 			plane_mode = "XY"  # North/South walls - expand in X and Y
# 		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
# 			plane_mode = "YZ"  # East/West walls - expand in Y and Z
# 		_:
# 			plane_mode = "XZ"  # Fallback

# 	# IMPROVED GREEDY CHUNKING: Sort tiles to process them in optimal order
# 	# Processing tiles in a consistent order (e.g., top-left to bottom-right) helps find larger rectangles
# 	var sorted_tiles := tiles.duplicate()
# 	match plane_mode:
# 		"XZ":  # Sort by Z first (rows), then X (columns)
# 			sorted_tiles.sort_custom(func(a, b):
# 				if a.grid_position.z != b.grid_position.z:
# 					return a.grid_position.z < b.grid_position.z
# 				return a.grid_position.x < b.grid_position.x
# 			)
# 		"XY":  # Sort by Y first (rows), then X (columns)
# 			sorted_tiles.sort_custom(func(a, b):
# 				if a.grid_position.y != b.grid_position.y:
# 					return a.grid_position.y < b.grid_position.y
# 				return a.grid_position.x < b.grid_position.x
# 			)
# 		"YZ":  # Sort by Z first (rows), then Y (columns)
# 			sorted_tiles.sort_custom(func(a, b):
# 				if a.grid_position.z != b.grid_position.z:
# 					return a.grid_position.z < b.grid_position.z
# 				return a.grid_position.y < b.grid_position.y
# 			)

# 	# Greedy chunking: find largest possible rectangle starting from each unassigned tile
# 	for tile in sorted_tiles:
# 		var start_pos: Vector3 = tile.grid_position

# 		if assigned.has(start_pos):
# 			continue

# 		# Find the largest rectangle starting at this position
# 		var chunk_rect: Dictionary = _find_largest_rectangle(start_pos, occupied, assigned, plane_mode)

# 		if chunk_rect:
# 			chunks.append(chunk_rect)

# 	return chunks

# ## Finds the largest rectangle of tiles starting from a given position
# ## IMPROVED: Tries expanding in both directions and picks the larger rectangle
# ##
# ## @param start: Starting grid position
# ## @param occupied: Dictionary of all occupied positions
# ## @param assigned: Dictionary tracking assigned positions (modified in-place)
# ## @param plane_mode: Which 2D plane to work in ("XZ", "XY", or "YZ")
# ## @returns: Dictionary with "min" and "max" Vector3, or null if can't create chunk
# static func _find_largest_rectangle(
# 	start: Vector3,
# 	occupied: Dictionary,
# 	assigned: Dictionary,
# 	plane_mode: String
# ) -> Dictionary:

# 	if assigned.has(start):
# 		return {}

# 	# Try both expansion strategies and pick the one that creates a larger rectangle
# 	# Strategy 1: Expand width first, then height
# 	var rect1: Dictionary = _try_expand_rectangle(start, occupied, assigned, plane_mode, true)

# 	# Strategy 2: Expand height first, then width
# 	var rect2: Dictionary = _try_expand_rectangle(start, occupied, assigned, plane_mode, false)

# 	# Pick the rectangle with larger area
# 	var area1: int = rect1["width"] * rect1["height"]
# 	var area2: int = rect2["width"] * rect2["height"]

# 	var best_rect: Dictionary = rect1 if area1 >= area2 else rect2
# 	var width: int = best_rect["width"]
# 	var height: int = best_rect["height"]

# 	# Mark all tiles in this rectangle as assigned
# 	for x in range(width):
# 		for y in range(height):
# 			match plane_mode:
# 				"XZ":  # Floors/Ceilings
# 					var pos := Vector3(start.x + x, start.y, start.z + y)
# 					assigned[pos] = true
# 				"XY":  # North/South walls
# 					var pos := Vector3(start.x + x, start.y + y, start.z)
# 					assigned[pos] = true
# 				"YZ":  # East/West walls
# 					var pos := Vector3(start.x, start.y + x, start.z + y)
# 					assigned[pos] = true

# 	# Return the chunk bounds
# 	var chunk_max: Vector3
# 	match plane_mode:
# 		"XZ":
# 			chunk_max = Vector3(start.x + width - 1, start.y, start.z + height - 1)
# 		"XY":
# 			chunk_max = Vector3(start.x + width - 1, start.y + height - 1, start.z)
# 		"YZ":
# 			chunk_max = Vector3(start.x, start.y + width - 1, start.z + height - 1)
# 		_:
# 			chunk_max = start

# 	return {
# 		"min": start,
# 		"max": chunk_max
# 	}

# ## Helper function: Try expanding a rectangle with a specific strategy
# ## @param width_first: If true, expand width then height. If false, expand height then width.
# ## @returns: Dictionary with "width" and "height"
# static func _try_expand_rectangle(
# 	start: Vector3,
# 	occupied: Dictionary,
# 	assigned: Dictionary,
# 	plane_mode: String,
# 	width_first: bool
# ) -> Dictionary:

# 	if width_first:
# 		# Strategy 1: Expand width as far as possible, then expand height
# 		var width := 1
# 		var test_pos := start

# 		# Expand first dimension (width)
# 		while true:
# 			match plane_mode:
# 				"XZ":
# 					test_pos = Vector3(start.x + width, start.y, start.z)
# 				"XY":
# 					test_pos = Vector3(start.x + width, start.y, start.z)
# 				"YZ":
# 					test_pos = Vector3(start.x, start.y + width, start.z)

# 			if occupied.has(test_pos) and not assigned.has(test_pos):
# 				width += 1
# 			else:
# 				break

# 		# Expand second dimension (height), checking entire rows
# 		var height := 1
# 		while true:
# 			var can_expand := true
# 			for x in range(width):
# 				match plane_mode:
# 					"XZ":
# 						test_pos = Vector3(start.x + x, start.y, start.z + height)
# 					"XY":
# 						test_pos = Vector3(start.x + x, start.y + height, start.z)
# 					"YZ":
# 						test_pos = Vector3(start.x, start.y + x, start.z + height)

# 				if not occupied.has(test_pos) or assigned.has(test_pos):
# 					can_expand = false
# 					break

# 			if can_expand:
# 				height += 1
# 			else:
# 				break

# 		return {"width": width, "height": height}

# 	else:
# 		# Strategy 2: Expand height as far as possible, then expand width
# 		var height := 1
# 		var test_pos := start

# 		# Expand first dimension (height)
# 		while true:
# 			match plane_mode:
# 				"XZ":
# 					test_pos = Vector3(start.x, start.y, start.z + height)
# 				"XY":
# 					test_pos = Vector3(start.x, start.y + height, start.z)
# 				"YZ":
# 					test_pos = Vector3(start.x, start.y, start.z + height)

# 			if occupied.has(test_pos) and not assigned.has(test_pos):
# 				height += 1
# 			else:
# 				break

# 		# Expand second dimension (width), checking entire columns
# 		var width := 1
# 		while true:
# 			var can_expand := true
# 			for y in range(height):
# 				match plane_mode:
# 					"XZ":
# 						test_pos = Vector3(start.x + width, start.y, start.z + y)
# 					"XY":
# 						test_pos = Vector3(start.x + width, start.y + y, start.z)
# 					"YZ":
# 						test_pos = Vector3(start.x, start.y + y, start.z + width)

# 				if not occupied.has(test_pos) or assigned.has(test_pos):
# 					can_expand = false
# 					break

# 			if can_expand:
# 				width += 1
# 			else:
# 				break

# 		return {"width": width, "height": height}


# # ==============================================================================
# # MERGED COLLISION SHAPE GENERATION (UNUSED - Kept for reference)
# # ==============================================================================

# ## Creates a single merged collision shape for a group of connected tiles
# ## Traces the outer perimeter of the tile group and creates a ConcavePolygonShape3D
# ##
# ## @param tiles: Array of tiles in the group (must all have same orientation)
# ## @param grid_size: World size of tiles
# ## @returns: ConcavePolygonShape3D representing the merged collision, or null on failure
# static func _create_merged_collision_shape(
# 	tiles: Array[TilePlacerData],
# 	grid_size: float
# ) -> ConcavePolygonShape3D:

# 	if tiles.is_empty():
# 		return null

# 	# Get orientation from first tile (all tiles in group have same orientation)
# 	var orientation = tiles[0].orientation

# 	# Build a set of occupied grid positions for quick lookup
# 	var occupied_positions: Dictionary = {}
# 	var min_pos := Vector3(INF, INF, INF)
# 	var max_pos := Vector3(-INF, -INF, -INF)

# 	for tile in tiles:
# 		var pos = tile.grid_position
# 		occupied_positions[pos] = true
# 		min_pos.x = min(min_pos.x, pos.x)
# 		min_pos.y = min(min_pos.y, pos.y)
# 		min_pos.z = min(min_pos.z, pos.z)
# 		max_pos.x = max(max_pos.x, pos.x)
# 		max_pos.y = max(max_pos.y, pos.y)
# 		max_pos.z = max(max_pos.z, pos.z)

# 	# For floor/ceiling tiles, trace in XZ plane
# 	# For wall tiles, trace in XY plane
# 	var perimeter_points := _trace_perimeter_2d(occupied_positions, min_pos, max_pos, orientation)

# 	if perimeter_points.is_empty():
# 		return null

# 	# Convert 2D perimeter to 3D collision shape
# 	# Pass min_pos for proper Y/Z positioning
# 	var shape := _create_3d_shape_from_perimeter(perimeter_points, grid_size, orientation, min_pos)

# 	return shape

# ## Traces the outer perimeter of occupied tiles in 2D
# ## Uses edge tracing to find the boundary following the actual tile shape
# ##
# ## @param occupied: Dictionary of occupied grid positions (Vector3 keys)
# ## @param min_pos: Minimum position in the group
# ## @param max_pos: Maximum position in the group
# ## @param orientation: Tile orientation (determines which plane to trace in)
# ## @returns: PackedVector2Array of perimeter points in grid coordinates
# static func _trace_perimeter_2d(
# 	occupied: Dictionary,
# 	min_pos: Vector3,
# 	max_pos: Vector3,
# 	orientation: int
# ) -> PackedVector2Array:

# 	# Determine which 2D plane to work in based on orientation
# 	var use_xz := (orientation == GlobalUtil.TileOrientation.FLOOR or
# 	               orientation == GlobalUtil.TileOrientation.CEILING)

# 	# Convert 3D occupied positions to 2D grid for easier processing
# 	var occupied_2d: Dictionary = {}
# 	for pos in occupied.keys():
# 		if use_xz:
# 			# XZ plane - use X and Z coordinates
# 			var key := Vector2(pos.x, pos.z)
# 			occupied_2d[key] = true
# 		else:
# 			# XY plane - use X and Y coordinates
# 			var key := Vector2(pos.x, pos.y)
# 			occupied_2d[key] = true

# 	# Trace the outline by finding boundary edges
# 	var outline := _trace_outline_2d(occupied_2d, use_xz, min_pos, max_pos)

# 	return outline

# ## Traces the outline of a 2D tile grid by finding boundary edges
# ## Each tile is a 1x1 square, we find edges where tile meets empty space
# ##
# ## @param occupied: Dictionary of occupied 2D positions (Vector2 keys)
# ## @param use_xz: Whether using XZ plane (true) or XY plane (false)
# ## @param min_pos: Minimum 3D position (for bounds)
# ## @param max_pos: Maximum 3D position (for bounds)
# ## @returns: PackedVector2Array of corner points tracing the outline
# static func _trace_outline_2d(
# 	occupied: Dictionary,
# 	use_xz: bool,
# 	min_pos: Vector3,
# 	max_pos: Vector3
# ) -> PackedVector2Array:

# 	var outline: PackedVector2Array = []

# 	# Get 2D bounds
# 	var min_2d: Vector2
# 	var max_2d: Vector2
# 	if use_xz:
# 		min_2d = Vector2(min_pos.x, min_pos.z)
# 		max_2d = Vector2(max_pos.x, max_pos.z)
# 	else:
# 		min_2d = Vector2(min_pos.x, min_pos.y)
# 		max_2d = Vector2(max_pos.x, max_pos.y)

# 	# Find all boundary edges (edges between occupied and empty cells)
# 	var edges: Array[Dictionary] = []

# 	for grid_pos in occupied.keys():
# 		var gx := int(grid_pos.x)
# 		var gy := int(grid_pos.y)

# 		# Check all 4 neighbors (N, E, S, W)
# 		var neighbors: Array[Vector2] = [
# 			Vector2(gx, gy - 1),  # North
# 			Vector2(gx + 1, gy),  # East
# 			Vector2(gx, gy + 1),  # South
# 			Vector2(gx - 1, gy),  # West
# 		]

# 		# For each empty neighbor, add the edge between this tile and that neighbor
# 		for i in range(4):
# 			var neighbor: Vector2 = neighbors[i]
# 			if not occupied.has(neighbor):
# 				# This is a boundary edge
# 				var edge := _get_edge_corners(gx, gy, i)
# 				edges.append(edge)

# 	if edges.is_empty():
# 		# Single tile - return its corners
# 		outline.append(Vector2(min_2d.x - 0.5, min_2d.y - 0.5))
# 		outline.append(Vector2(max_2d.x + 0.5, min_2d.y - 0.5))
# 		outline.append(Vector2(max_2d.x + 0.5, max_2d.y + 0.5))
# 		outline.append(Vector2(min_2d.x - 0.5, max_2d.y + 0.5))
# 		return outline

# 	# Convert edges to an ordered outline by connecting them
# 	outline = _connect_edges_to_outline(edges)

# 	return outline

# ## Gets the two corner points for a boundary edge
# ## @param gx: Grid X position of tile
# ## @param gy: Grid Y position of tile
# ## @param direction: 0=North, 1=East, 2=South, 3=West
# ## @returns: Dictionary with 'start' and 'end' Vector2 corners
# static func _get_edge_corners(gx: int, gy: int, direction: int) -> Dictionary:
# 	var half := 0.5
# 	var edge := {}

# 	match direction:
# 		0:  # North edge (top)
# 			edge["start"] = Vector2(gx - half, gy - half)
# 			edge["end"] = Vector2(gx + half, gy - half)
# 		1:  # East edge (right)
# 			edge["start"] = Vector2(gx + half, gy - half)
# 			edge["end"] = Vector2(gx + half, gy + half)
# 		2:  # South edge (bottom)
# 			edge["start"] = Vector2(gx + half, gy + half)
# 			edge["end"] = Vector2(gx - half, gy + half)
# 		3:  # West edge (left)
# 			edge["start"] = Vector2(gx - half, gy + half)
# 			edge["end"] = Vector2(gx - half, gy - half)

# 	return edge

# ## Connects boundary edges into a continuous outline
# ## @param edges: Array of edge dictionaries with 'start' and 'end' points
# ## @returns: PackedVector2Array of connected corner points
# static func _connect_edges_to_outline(edges: Array[Dictionary]) -> PackedVector2Array:
# 	var outline: PackedVector2Array = []

# 	if edges.is_empty():
# 		return outline

# 	# Start with first edge
# 	var current_edge := edges[0]
# 	outline.append(current_edge["start"])
# 	outline.append(current_edge["end"])
# 	edges.remove_at(0)

# 	# Keep connecting edges until we form a closed loop
# 	var max_iterations := 10000  # Safety limit
# 	var iterations := 0

# 	while edges.size() > 0 and iterations < max_iterations:
# 		iterations += 1
# 		var last_point := outline[outline.size() - 1]

# 		# Find edge that starts where we ended
# 		var found := false
# 		for i in range(edges.size()):
# 			var edge := edges[i]
# 			var epsilon := 0.001

# 			if last_point.distance_to(edge["start"]) < epsilon:
# 				# This edge continues from our last point
# 				outline.append(edge["end"])
# 				edges.remove_at(i)
# 				found = true
# 				break
# 			elif last_point.distance_to(edge["end"]) < epsilon:
# 				# This edge is reversed - flip it
# 				outline.append(edge["start"])
# 				edges.remove_at(i)
# 				found = true
# 				break

# 		if not found:
# 			# Can't find connecting edge - outline might be complete
# 			break

# 	return outline

# ## Converts 2D perimeter points to a 3D ConcavePolygonShape3D
# ## Creates a thin mesh by extruding the perimeter and triangulating faces
# ##
# ## @param perimeter: 2D perimeter points
# ## @param grid_size: World size of tiles
# ## @param orientation: Tile orientation
# ## @param min_pos: Minimum grid position (for Y/Z positioning)
# ## @returns: ConcavePolygonShape3D
# static func _create_3d_shape_from_perimeter(
# 	perimeter: PackedVector2Array,
# 	grid_size: float,
# 	orientation: int,
# 	min_pos: Vector3
# ) -> ConcavePolygonShape3D:

# 	if perimeter.is_empty():
# 		return null

# 	var shape := ConcavePolygonShape3D.new()
# 	var faces: PackedVector3Array = []

# 	var thickness := GlobalConstants.COLLISION_BOX_THICKNESS
# 	var half_thickness := thickness * 0.5

# 	# Determine orientation basis
# 	var use_xz := (orientation == GlobalUtil.TileOrientation.FLOOR or
# 	               orientation == GlobalUtil.TileOrientation.CEILING)

# 	# Convert perimeter to 3D points
# 	var bottom_points: PackedVector3Array = []
# 	var top_points: PackedVector3Array = []

# 	if use_xz:
# 		# XZ plane (floor/ceiling) - extrude in Y direction
# 		for point in perimeter:
# 			var grid_pos := Vector3(point.x, min_pos.y, point.y)
# 			var world_pos := GlobalUtil.grid_to_world(grid_pos, grid_size)
# 			bottom_points.append(Vector3(world_pos.x, world_pos.y - half_thickness, world_pos.z))
# 			top_points.append(Vector3(world_pos.x, world_pos.y + half_thickness, world_pos.z))
# 	else:
# 		# XY plane (walls) - extrude in Z direction
# 		for point in perimeter:
# 			var grid_pos := Vector3(point.x, point.y, min_pos.z)
# 			var world_pos := GlobalUtil.grid_to_world(grid_pos, grid_size)
# 			bottom_points.append(Vector3(world_pos.x, world_pos.y, world_pos.z - half_thickness))
# 			top_points.append(Vector3(world_pos.x, world_pos.y, world_pos.z + half_thickness))

# 	# Create triangulated faces for ConcavePolygonShape3D
# 	# ConcavePolygonShape3D requires faces as triangles (every 3 points = 1 triangle)

# 	var num_points := bottom_points.size()

# 	# 1. Add side walls (quads made of 2 triangles each)
# 	for i in range(num_points):
# 		var next_i := (i + 1) % num_points

# 		var b0 := bottom_points[i]
# 		var b1 := bottom_points[next_i]
# 		var t0 := top_points[i]
# 		var t1 := top_points[next_i]

# 		# Triangle 1: b0, b1, t0
# 		faces.append(b0)
# 		faces.append(b1)
# 		faces.append(t0)

# 		# Triangle 2: b1, t1, t0
# 		faces.append(b1)
# 		faces.append(t1)
# 		faces.append(t0)

# 	# 2. Add top cap (ear clipping triangulation for concave polygons)
# 	var top_triangles := _triangulate_polygon(top_points)
# 	for tri in top_triangles:
# 		faces.append(tri[0])
# 		faces.append(tri[1])
# 		faces.append(tri[2])

# 	# 3. Add bottom cap (ear clipping triangulation, reversed winding)
# 	var bottom_triangles := _triangulate_polygon(bottom_points)
# 	for tri in bottom_triangles:
# 		# Reverse winding order for bottom
# 		faces.append(tri[0])
# 		faces.append(tri[2])
# 		faces.append(tri[1])

# 	shape.set_faces(faces)
# 	return shape

# ## Triangulates a 3D polygon using ear clipping algorithm
# ## Works for both convex and concave polygons (but not self-intersecting)
# ##
# ## @param points: PackedVector3Array of polygon vertices (coplanar)
# ## @returns: Array of triangles, each triangle is [Vector3, Vector3, Vector3]
# static func _triangulate_polygon(points: PackedVector3Array) -> Array:
# 	var triangles: Array = []

# 	if points.size() < 3:
# 		return triangles

# 	if points.size() == 3:
# 		triangles.append([points[0], points[1], points[2]])
# 		return triangles

# 	# Create a mutable copy of vertex indices
# 	var remaining_indices: Array[int] = []
# 	for i in range(points.size()):
# 		remaining_indices.append(i)

# 	# Ear clipping: repeatedly find and remove "ears"
# 	var max_iterations := points.size() * 2
# 	var iterations := 0

# 	while remaining_indices.size() > 3 and iterations < max_iterations:
# 		iterations += 1
# 		var found_ear := false

# 		for i in range(remaining_indices.size()):
# 			var prev_idx := remaining_indices[(i - 1 + remaining_indices.size()) % remaining_indices.size()]
# 			var curr_idx := remaining_indices[i]
# 			var next_idx := remaining_indices[(i + 1) % remaining_indices.size()]

# 			var v0 := points[prev_idx]
# 			var v1 := points[curr_idx]
# 			var v2 := points[next_idx]

# 			# Check if this forms a valid ear (convex vertex with no points inside)
# 			if _is_ear(points, remaining_indices, i):
# 				# Add this triangle
# 				triangles.append([v0, v1, v2])
# 				# Remove the ear vertex
# 				remaining_indices.remove_at(i)
# 				found_ear = true
# 				break

# 		if not found_ear:
# 			# Can't find any more ears - add remaining as final triangle
# 			break

# 	# Add the last triangle
# 	if remaining_indices.size() == 3:
# 		triangles.append([
# 			points[remaining_indices[0]],
# 			points[remaining_indices[1]],
# 			points[remaining_indices[2]]
# 		])

# 	return triangles

# ## Checks if a vertex forms a valid "ear" for ear clipping
# ## An ear is a triangle that doesn't contain any other vertices
# ##
# ## @param points: All polygon points
# ## @param remaining_indices: Indices of remaining vertices
# ## @param ear_index: Index in remaining_indices to check
# ## @returns: true if this is a valid ear
# static func _is_ear(points: PackedVector3Array, remaining_indices: Array[int], ear_index: int) -> bool:
# 	var n := remaining_indices.size()
# 	var prev_idx := remaining_indices[(ear_index - 1 + n) % n]
# 	var curr_idx := remaining_indices[ear_index]
# 	var next_idx := remaining_indices[(ear_index + 1) % n]

# 	var v0 := points[prev_idx]
# 	var v1 := points[curr_idx]
# 	var v2 := points[next_idx]

# 	# Check if the angle at v1 is convex (using cross product)
# 	var edge1 := v1 - v0
# 	var edge2 := v2 - v1
# 	var cross := edge1.cross(edge2)

# 	# For floor tiles (XZ plane), check Y component of cross product
# 	# For walls (XY plane), check Z component
# 	# We want counter-clockwise winding (positive cross product)
# 	if cross.y < 0.001 and cross.z < 0.001:  # Concave or collinear
# 		return false

# 	# Check if any other vertex is inside this triangle
# 	for i in range(remaining_indices.size()):
# 		if i == ear_index or i == (ear_index - 1 + n) % n or i == (ear_index + 1) % n:
# 			continue

# 		var p := points[remaining_indices[i]]
# 		if _point_in_triangle(p, v0, v1, v2):
# 			return false

# 	return true

# ## Checks if a point is inside a triangle (2D test, ignoring one axis)
# ##
# ## @param p: Point to test
# ## @param a, b, c: Triangle vertices
# ## @returns: true if point is inside triangle
# static func _point_in_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
# 	# Use barycentric coordinates
# 	var v0 := c - a
# 	var v1 := b - a
# 	var v2 := p - a

# 	# Project to 2D (use XZ for floors, XY for walls)
# 	# For simplicity, use XZ projection
# 	var dot00 := v0.x * v0.x + v0.z * v0.z
# 	var dot01 := v0.x * v1.x + v0.z * v1.z
# 	var dot02 := v0.x * v2.x + v0.z * v2.z
# 	var dot11 := v1.x * v1.x + v1.z * v1.z
# 	var dot12 := v1.x * v2.x + v1.z * v2.z

# 	var inv_denom := 1.0 / (dot00 * dot11 - dot01 * dot01)
# 	var u := (dot11 * dot02 - dot01 * dot12) * inv_denom
# 	var v := (dot00 * dot12 - dot01 * dot02) * inv_denom

# 	return (u >= 0) and (v >= 0) and (u + v <= 1)

# # ==============================================================================
# # UTILITY FUNCTIONS
# # ==============================================================================

# ## Clears the sprite collision shape cache
# ## Call this when switching scenes or reloading tilesets
static func clear_shape_cache() -> void:
	SpriteCollisionGenerator.clear_cache()
	print("CollisionGenerator: Cleared sprite collision shape cache")

# ## Gets cache statistics for debugging/profiling
# static func get_cache_stats() -> Dictionary:
# 	return SpriteCollisionGenerator.get_cache_stats()
