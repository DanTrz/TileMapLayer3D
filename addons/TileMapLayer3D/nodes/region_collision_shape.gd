class_name RegionCollisionShape
extends CollisionShape3D

## CollisionShape3D that knows which region it belongs to.
## region_key matches TerrainRegionChunk.region_key — used for targeted hot-swap.
## Vector3i.MAX means full-map (no region).
@export var region_key: Vector3i = Vector3i.MAX
