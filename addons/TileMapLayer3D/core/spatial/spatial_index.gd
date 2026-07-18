@tool
class_name SpatialIndex
extends RefCounted


var _bucket_size: float = GlobalConstants.SPATIAL_INDEX_BUCKET_SIZE

var _buckets: Dictionary = {}

var _tile_to_bucket: Dictionary = {}

const BUCKET_COORD_BITS: int = 20
const BUCKET_COORD_MASK: int = 0xFFFFF
const BUCKET_X_SHIFT: int = 40
const BUCKET_Y_SHIFT: int = 20
const BUCKET_Z_SHIFT: int = 0

func _get_bucket_key(pos: Vector3) -> int:
	var bx: int = floori(pos.x / _bucket_size)
	var by: int = floori(pos.y / _bucket_size)
	var bz: int = floori(pos.z / _bucket_size)
	
	const OFFSET: int = 100
	bx += OFFSET
	by += OFFSET
	bz += OFFSET
	
	bx = clampi(bx, 0, BUCKET_COORD_MASK)
	by = clampi(by, 0, BUCKET_COORD_MASK)
	bz = clampi(bz, 0, BUCKET_COORD_MASK)
	
	return (bx << BUCKET_X_SHIFT) | (by << BUCKET_Y_SHIFT) | bz

func _get_bucket_coords(pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(pos.x / _bucket_size),
		floori(pos.y / _bucket_size),
		floori(pos.z / _bucket_size)
	)

func add_tile(tile_key: Variant, position: Vector3) -> void:
	var bucket_key: int = _get_bucket_key(position)

	if not _buckets.has(bucket_key):
		_buckets[bucket_key] = []

	var bucket: Array = _buckets[bucket_key]
	if not bucket.has(tile_key):
		bucket.append(tile_key)

	_tile_to_bucket[tile_key] = bucket_key

func remove_tile(tile_key: Variant) -> void:
	if not _tile_to_bucket.has(tile_key):
		return

	var bucket_key: int = _tile_to_bucket[tile_key]

	if _buckets.has(bucket_key):
		var bucket: Array = _buckets[bucket_key]
		bucket.erase(tile_key)

		if bucket.is_empty():
			_buckets.erase(bucket_key)

	_tile_to_bucket.erase(tile_key)


func get_tile_keys() -> Array:
	return _tile_to_bucket.keys()

func get_tiles_in_area(min_pos: Vector3, max_pos: Vector3) -> Array:
	var results: Array = []
	var checked_buckets: Dictionary = {}

	var min_bucket: Vector3i = _get_bucket_coords(min_pos)
	var max_bucket: Vector3i = _get_bucket_coords(max_pos)

	for bx in range(min_bucket.x, max_bucket.x + 1):
		for by in range(min_bucket.y, max_bucket.y + 1):
			for bz in range(min_bucket.z, max_bucket.z + 1):
				var test_pos: Vector3 = Vector3(bx * _bucket_size, by * _bucket_size, bz * _bucket_size)
				var bucket_key: int = _get_bucket_key(test_pos)
				
				if checked_buckets.has(bucket_key):
					continue
				checked_buckets[bucket_key] = true
				
				if _buckets.has(bucket_key):
					results.append_array(_buckets[bucket_key])

	return results

func clear() -> void:
	_buckets.clear()
	_tile_to_bucket.clear()

func size() -> int:
	return _tile_to_bucket.size()
