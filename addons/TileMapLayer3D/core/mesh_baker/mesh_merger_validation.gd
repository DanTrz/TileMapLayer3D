@tool
class_name MeshMergerValidator
extends RefCounted

## ============================================================================
## MESH MERGER VALIDATOR FOR GODOT 2.5D TILE PLACER
## ============================================================================
## Validates merged meshes for UV preservation and correctness
## Responsibility: Quality assurance for mesh merging operations
## Author: Claude Code (2025)
## Version: 1.0
##
## This class provides comprehensive validation for merged ArrayMesh objects
## to ensure that:
## - UV coordinates are preserved correctly
## - Vertex counts match expectations
## - No degenerate triangles exist
## - UV bounds are within valid [0,1] range
## - Texture compatibility is maintained
##
## Usage:
##   var report: Dictionary = MeshMergerValidator.validate_merged_mesh(mesh, source_layer)
##   if report.is_valid:
##       print("Validation passed!")
##   else:
##       print("Errors: ", report.errors)

# ==============================================================================
# MAIN VALIDATION FUNCTION
# ==============================================================================

## Validate that merged mesh preserves all UV coordinates correctly
## @param merged_mesh: ArrayMesh to validate
## @param source_layer: Original TileMapLayer3D (for comparison)
## @returns: Dictionary with keys:
##   - is_valid: bool - Overall validation status
##   - vertex_count: int - Number of vertices in mesh
##   - uv_count: int - Number of UV coordinates
##   - uv_bounds: Rect2 - Bounding box of all UVs
##   - warnings: Array[String] - Non- issues
##   - errors: Array[String] -  issues
##   - uv_coverage_percent: float - UV coverage percentage (optional)
static func validate_merged_mesh(merged_mesh: ArrayMesh, source_layer: TileMapLayer3D) -> Dictionary:
	var report: Dictionary = {
		"is_valid": true,
		"vertex_count": 0,
		"uv_count": 0,
		"uv_bounds": Rect2(),
		"warnings": [],
		"errors": []
	}

	# Validation: Check mesh exists
	if not merged_mesh:
		report.is_valid = false
		report.errors.append("No mesh provided")
		return report

	# Validation: Check mesh has surfaces
	if merged_mesh.get_surface_count() == 0:
		report.is_valid = false
		report.errors.append("Mesh has no surfaces")
		return report

	# Get mesh arrays
	var arrays: Array = merged_mesh.surface_get_arrays(0)

	if not arrays or arrays.is_empty():
		report.is_valid = false
		report.errors.append("Failed to get mesh arrays")
		return report

	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

	report.vertex_count = vertices.size()
	report.uv_count = uvs.size()

	# Check 1: Vertex and UV counts must match
	if vertices.size() != uvs.size():
		report.is_valid = false
		report.errors.append("Vertex count (%d) doesn't match UV count (%d)" % [vertices.size(), uvs.size()])
		return report

	# Check 2: Calculate UV bounds
	report.uv_bounds = _get_uv_bounds(uvs)

	# Check 3: Verify UV coordinates are within valid [0,1] range
	var uv_errors: int = 0
	for i: int in range(uvs.size()):
		var uv: Vector2 = uvs[i]
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			uv_errors += 1
			if uv_errors <= 5:  # Only report first 5 errors
				report.errors.append("UV out of bounds at vertex %d: %v" % [i, uv])

	if uv_errors > 0:
		report.is_valid = false
		report.errors.append("Total UV errors: %d" % uv_errors)

	# Check 4: Verify expected vertex count matches source tiles
	if source_layer:
		var expected_vertices: int = 0
		for tile: TilePlacerData in source_layer.saved_tiles:
			match tile.mesh_mode:
				GlobalConstants.MeshMode.FLAT_SQUARE:
					expected_vertices += 4
				GlobalConstants.MeshMode.FLAT_TRIANGULE:
					expected_vertices += 3
				GlobalConstants.MeshMode.BOX_MESH:
					expected_vertices += 24
				GlobalConstants.MeshMode.PRISM_MESH:
					expected_vertices += 18

		if vertices.size() != expected_vertices:
			report.warnings.append("Vertex count mismatch: got %d, expected %d" % [vertices.size(), expected_vertices])

	# Check 5: Detect degenerate triangles
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var degenerate_count: int = 0

	for i: int in range(0, indices.size(), 3):
		if i + 2 < indices.size():
			var v0: Vector3 = vertices[indices[i]]
			var v1: Vector3 = vertices[indices[i + 1]]
			var v2: Vector3 = vertices[indices[i + 2]]

			var area: float = (v1 - v0).cross(v2 - v0).length()
			if area < 0.0001:
				degenerate_count += 1

	if degenerate_count > 0:
		report.warnings.append("Found %d degenerate triangles" % degenerate_count)

	# Check 6: Verify UV coverage
	if source_layer and source_layer.tileset_texture:
		var expected_uv_area: float = 0.0
		for tile: TilePlacerData in source_layer.saved_tiles:
			var normalized_area: Vector2 = (tile.uv_rect.size / source_layer.tileset_texture.get_size())
			expected_uv_area += normalized_area.x * normalized_area.y

		var actual_area: float = report.uv_bounds.get_area()
		var coverage_percent: float = (expected_uv_area / actual_area) * 100.0 if actual_area > 0 else 0.0

		report["uv_coverage_percent"] = coverage_percent

		if coverage_percent < 50.0:
			report.warnings.append("Low UV coverage: %.1f%%" % coverage_percent)

	# Print validation report
	_print_report(report)

	return report

# ==============================================================================
# UV BOUNDS CALCULATION
# ==============================================================================

## Calculate bounding box of UV coordinates
## @param uvs: PackedVector2Array of UV coordinates
## @returns: Rect2 representing min/max UV bounds
static func _get_uv_bounds(uvs: PackedVector2Array) -> Rect2:
	if uvs.is_empty():
		return Rect2()

	var min_uv: Vector2 = uvs[0]
	var max_uv: Vector2 = uvs[0]

	for uv: Vector2 in uvs:
		min_uv.x = min(min_uv.x, uv.x)
		min_uv.y = min(min_uv.y, uv.y)
		max_uv.x = max(max_uv.x, uv.x)
		max_uv.y = max(max_uv.y, uv.y)

	return Rect2(min_uv, max_uv - min_uv)

# ==============================================================================
# PRETTY REPORT FORMATTING
# ==============================================================================

## Print formatted validation report with box drawing characters
## @param report: Dictionary containing validation results
static func _print_report(report: Dictionary) -> void:
	print("\n╔══════════════════════════════════════════╗")
	print("║         MESH VALIDATION REPORT           ║")
	print("╠══════════════════════════════════════════╣")

	var status: String = "VALID" if report.is_valid else "INVALID"
	print("║ Status: %s" % status)
	print("║ Vertices: %d" % report.vertex_count)
	print("║ UVs: %d" % report.uv_count)
	print("║ UV Bounds: %s" % report.uv_bounds)

	if report.has("uv_coverage_percent"):
		print("║ UV Coverage: %.1f%%" % report.uv_coverage_percent)

	if not report.errors.is_empty():
		print("╠══════════════════════════════════════════╣")
		print("║ ERRORS:")
		for error: String in report.errors:
			print("║    %s" % error)

	if not report.warnings.is_empty():
		print("╠══════════════════════════════════════════╣")
		print("║ WARNINGS:")
		for warning: String in report.warnings:
			print("║   %s" % warning)

	print("╚══════════════════════════════════════════╝\n")

# ==============================================================================
# QUICK VALIDATION
# ==============================================================================

## Quick validation check for UI feedback
## Fast boolean check without detailed analysis
##
## @param merged_mesh: ArrayMesh to validate
## @returns: true if mesh appears valid, false otherwise
static func quick_validate(merged_mesh: ArrayMesh) -> bool:
	# Check mesh exists and has surfaces
	if not merged_mesh or merged_mesh.get_surface_count() == 0:
		return false

	# Get arrays
	var arrays: Array = merged_mesh.surface_get_arrays(0)
	if not arrays or arrays.is_empty():
		return false

	# Check basic requirements
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

	return vertices.size() == uvs.size() and vertices.size() > 0

# ==============================================================================
# TEXTURE COMPATIBILITY VALIDATION
# ==============================================================================

## Validate texture compatibility with mesh UVs
## Ensures mesh UVs are compatible with the texture
##
## @param mesh: ArrayMesh to validate
## @param texture: Texture2D to check compatibility with
## @returns: true if compatible, false otherwise
static func validate_texture_compatibility(mesh: ArrayMesh, texture: Texture2D) -> bool:
	# Check both mesh and texture exist
	if not mesh or not texture:
		return false

	# Check if mesh has valid UV coordinates
	var arrays: Array = mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

	if uvs.is_empty():
		return false

	# All UVs should be in 0-1 range for the texture to work
	for uv: Vector2 in uvs:
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			return false

	return true
