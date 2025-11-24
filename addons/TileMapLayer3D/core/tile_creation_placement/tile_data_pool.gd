@tool
class_name TileDataPool
extends RefCounted

##  Object pool for TilePlacerData to reduce GC pressure

# Static pool shared across all users
static var _pool: Array[TilePlacerData] = []
static var _pool_size: int = 0
static var _max_pool_size: int = 1000  # Reasonable limit to prevent unlimited growth

# Statistics for monitoring
static var _total_acquired: int = 0
static var _total_released: int = 0
static var _total_allocated: int = 0

##  Acquires a TilePlacerData from pool (or creates new if pool empty)
## Always returns a clean, reset object ready for use
## @returns: TilePlacerData instance (reset to defaults)
static func acquire() -> TilePlacerData:
	_total_acquired += 1

	if _pool_size > 0:
		# Reuse from pool
		_pool_size -= 1
		var data: TilePlacerData = _pool.pop_back()
		data.reset()  # Ensure clean state
		return data
	else:
		# Pool empty, allocate new
		_total_allocated += 1
		return TilePlacerData.new()

##  Returns a TilePlacerData to pool for reuse
## Object will be reset and made available for future acquire() calls
## @param data: TilePlacerData to return to pool
static func release(data: TilePlacerData) -> void:
	if not data:
		push_warning("TileDataPool: Attempted to release null object")
		return

	_total_released += 1

	# Only keep up to max pool size
	if _pool_size < _max_pool_size:
		data.reset()  # Clean the object
		_pool.append(data)
		_pool_size += 1
	# else: Let it be garbage collected (pool is full)

## Clears the entire pool
## Use this when unloading scenes or during cleanup
static func clear() -> void:
	_pool.clear()
	_pool_size = 0

## Returns statistics about pool usage
## Useful for debugging and performance monitoring
## @returns: Dictionary with pool statistics
static func get_stats() -> Dictionary:
	return {
		"pool_size": _pool_size,
		"max_pool_size": _max_pool_size,
		"total_acquired": _total_acquired,
		"total_released": _total_released,
		"total_allocated": _total_allocated,
		"reuse_rate": _calculate_reuse_rate()
	}

## Calculates the percentage of acquisitions that reused pooled objects
## @returns: Float between 0.0 and 1.0 (1.0 = 100% reuse)
static func _calculate_reuse_rate() -> float:
	if _total_acquired == 0:
		return 0.0

	var reused: int = _total_acquired - _total_allocated
	return float(reused) / float(_total_acquired)

## DEBUG: Prints pool statistics to console
static func print_stats() -> void:
	var stats: Dictionary = get_stats()
	print("═══ TileDataPool Statistics ═══")
	print("  Current pool size: %d / %d" % [stats.pool_size, stats.max_pool_size])
	print("  Total acquired: %d" % stats.total_acquired)
	print("  Total released: %d" % stats.total_released)
	print("  Total allocated (new): %d" % stats.total_allocated)
	print("  Reuse rate: %.1f%%" % (stats.reuse_rate * 100.0))
	print("═══════════════════════════════")

## Resets all statistics (useful for benchmarking)
static func reset_stats() -> void:
	_total_acquired = 0
	_total_released = 0
	_total_allocated = 0
