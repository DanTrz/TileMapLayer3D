class_name RegionBakeOptions
extends RefCounted

## Options bag for RegionBaker.bake_mesh / RegionBaker.bake_collision.
## One Resource carries every dial so callers don't fork the code path
## per variant. Defaults match the most common runtime use case
## (synchronous, non-alpha, respect collision custom data).

## Alpha-aware merge — skips transparent pixels via AlphaMeshGenerator.
## Slower per tile but produces tighter collision/mesh for sprites.
var alpha_aware: bool = false

## When true, collision shapes have backface_collision enabled
## (rays from inside the volume still hit). Only meaningful for bake_collision.
var backface_collision: bool = false

## Honor the per-tile "Collision" custom data layer (skip tiles where the
## TileSet TileData has Collision = false). Set false to bake every tile.
var respect_collision_custom_data: bool = true

## Run the merge on a WorkerThreadPool task instead of the main thread.
## Default true — keeps the main thread free during a large region bake
## (~200 ms of merge work on the worker, only ~30 ms on the main thread
## for the final shape build + attach). Flip false for tests, or for a
## tiny region where the worker handoff cost outweighs the merge cost.
##
## Currently RegionBaker always uses the worker path; the flag is plumbed
## for future force-sync use without forking the code path.
var async: bool = true

## Scene root to assign as owner of newly created collision nodes so they
## persist in the .tscn. Leave null for runtime hot-swap (no save).
var attach_owner: Node = null
