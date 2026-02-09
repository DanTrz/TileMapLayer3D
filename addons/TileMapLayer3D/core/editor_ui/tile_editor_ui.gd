# =============================================================================
# PURPOSE: UI Coordinator for TileMapLayer3D editor plugin
# =============================================================================
# This class manages all editor UI components and routes signals between
# the UI layer and the plugin. It serves as a single point of coordination
# for UI creation, visibility, and state synchronization.
#
# ARCHITECTURE:
#   - Created by TileMapLayer3DPlugin in _enter_tree()
#   - Manages: TileTopBar, TileSideToolbar, TilesetPanel
#   - Routes signals: UI components ↔ Plugin ↔ Managers
#   - Syncs UI state from TileMapLayerSettings when node changes
#
# RESPONSIBILITIES:
#   - Create and destroy UI components
#   - Add/remove controls to editor containers
#   - Route signals between UI and plugin
#   - Sync UI state when active node changes
#   - Manage UI visibility based on plugin active state
#   - Keep top bar and dock panel in sync (bidirectional)
# =============================================================================

@tool
class_name TileEditorUI
extends RefCounted

# EditorPlugin.CustomControlContainer values (int for web export compatibility)
# These are stable Godot engine enum values used by add_control_to_container()
const CONTAINER_SPATIAL_EDITOR_MENU: int = 1
const CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT: int = 3

# Preload UI component classes
const TileTopBarClass = preload("res://addons/TileMapLayer3D/core/editor_ui/tile_top_bar.gd")
const TileSideToolbarClass = preload("res://addons/TileMapLayer3D/core/editor_ui/tile_side_toolbar.gd")

# =============================================================================
# SECTION: SIGNALS
# =============================================================================

## Emitted when the enable toggle is changed
signal enabled_changed(enabled: bool)

## Emitted when tiling mode changes (Manual/Auto)
signal mode_changed(mode: int)

## Emitted when rotation is requested (direction: +1 CW, -1 CCW)
signal rotate_requested(direction: int)

## Emitted when tilt cycling is requested (reverse: bool)
signal tilt_requested(reverse: bool)

## Emitted when reset to flat is requested
signal reset_requested()

## Emitted when face flip is requested
signal flip_requested()

# =============================================================================
# SECTION: CONSTANTS
# =============================================================================

## Tiling mode constants
const MODE_MANUAL: int = 0
const MODE_AUTOTILE: int = 1

# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

## Reference to the main plugin (for accessing managers and EditorPlugin methods)
## Dynamic type (Object) for web export compatibility - EditorPlugin not available at runtime
var _plugin: Object = null

## Current active TileMapLayer3D node
var _current_node: Node = null  # TileMapLayer3D

## UI is visible and active
var _is_visible: bool = false

# --- UI Components ---

## Top bar (HBoxContainer in CONTAINER_SPATIAL_EDITOR_MENU)
var _top_bar: Control = null  # TileTopBar

## Side toolbar (VBoxContainer in CONTAINER_SPATIAL_EDITOR_SIDE_LEFT)
var _side_toolbar: Control = null  # TileSideToolbar

## Default location for side toolbar (Left or Right side panel)
var _default_side_toolbar_location: int = CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT

## Reference to existing TilesetPanel (dock panel)
var _tileset_panel: Control = null  # TilesetPanel

# =============================================================================
# SECTION: INITIALIZATION
# =============================================================================

## Initialize the UI coordinator
## @param plugin: Reference to TileMapLayer3DPlugin
func initialize(plugin: Object) -> void:
	_plugin = plugin
	_create_top_bar()
	_create_side_toolbar()

	# Start with UI hidden - will be shown when TileMapLayer3D is selected
	set_ui_visible(false)


## Clean up all UI components
func cleanup() -> void:
	_disconnect_tileset_panel()
	_destroy_side_toolbar()
	_destroy_top_bar()
	_plugin = null
	_current_node = null
	_tileset_panel = null

# =============================================================================
# SECTION: TOP BAR
# =============================================================================

## Create the top bar component
func _create_top_bar() -> void:
	if not _plugin:
		return

	# Create top bar using preloaded class
	_top_bar = TileTopBarClass.new()

	# Connect signals from top bar to coordinator (routes to plugin)
	_top_bar.enabled_changed.connect(_on_top_bar_enabled_changed)
	_top_bar.mode_changed.connect(_on_top_bar_mode_changed)

	# Add to editor's 3D toolbar
	_plugin.add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _top_bar)


## Destroy the top bar
func _destroy_top_bar() -> void:
	if _top_bar and _plugin:
		_plugin.remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _top_bar)
		_top_bar.queue_free()
		_top_bar = null

# =============================================================================
# SECTION: SIDE TOOLBAR
# =============================================================================

## Create the side toolbar component
func _create_side_toolbar() -> void:
	if not _plugin:
		return

	# Create side toolbar using preloaded class
	_side_toolbar = TileSideToolbarClass.new()

	# Connect signals from side toolbar to coordinator (routes to plugin)
	_side_toolbar.rotate_requested.connect(_on_side_toolbar_rotate_requested)
	_side_toolbar.tilt_requested.connect(_on_side_toolbar_tilt_requested)
	_side_toolbar.reset_requested.connect(_on_side_toolbar_reset_requested)
	_side_toolbar.flip_requested.connect(_on_side_toolbar_flip_requested)

	# Add to editor's left side panel
	_plugin.add_control_to_container(_default_side_toolbar_location, _side_toolbar)


## Destroy the side toolbar
func _destroy_side_toolbar() -> void:
	if _side_toolbar and _plugin:
		_plugin.remove_control_from_container(_default_side_toolbar_location, _side_toolbar)
		_side_toolbar.queue_free()
		_side_toolbar = null

# =============================================================================
# SECTION: TILESET PANEL SYNC
# =============================================================================

## Connect to TilesetPanel signals for bidirectional sync
func _connect_tileset_panel() -> void:
	if not _tileset_panel:
		return

	# Connect to tiling_mode_changed to sync top bar when tab changes in dock
	if _tileset_panel.has_signal("tiling_mode_changed"):
		if not _tileset_panel.tiling_mode_changed.is_connected(_on_tileset_panel_mode_changed):
			_tileset_panel.tiling_mode_changed.connect(_on_tileset_panel_mode_changed)


## Disconnect from TilesetPanel signals
func _disconnect_tileset_panel() -> void:
	if not _tileset_panel:
		return

	if _tileset_panel.has_signal("tiling_mode_changed"):
		if _tileset_panel.tiling_mode_changed.is_connected(_on_tileset_panel_mode_changed):
			_tileset_panel.tiling_mode_changed.disconnect(_on_tileset_panel_mode_changed)

# =============================================================================
# SECTION: PUBLIC METHODS
# =============================================================================

## Set the currently active TileMapLayer3D node
## Called by plugin when _edit() is invoked
## @param node: The TileMapLayer3D node to edit (or null when deselected)
func set_active_node(node: Node) -> void:
	_current_node = node

	if node:
		_sync_ui_from_node(node)
	else:
		_reset_ui_state()


## Set the reference to the existing TilesetPanel
## @param panel: The TilesetPanel instance from the plugin
func set_tileset_panel(panel: Control) -> void:
	# Disconnect from old panel if any
	_disconnect_tileset_panel()

	_tileset_panel = panel

	# Connect to new panel
	_connect_tileset_panel()


## Set whether the plugin is enabled/active
## @param enabled: True to enable, false to disable
func set_enabled(enabled: bool) -> void:
	if _top_bar and _top_bar.has_method("set_enabled"):
		_top_bar.set_enabled(enabled)
	_is_visible = enabled


## Get whether the plugin is currently enabled
func is_enabled() -> bool:
	if _top_bar and _top_bar.has_method("is_enabled"):
		return _top_bar.is_enabled()
	return false


## Set tiling mode (Manual/Auto)
## @param mode: 0 = Manual, 1 = Auto
func set_mode(mode: int) -> void:
	if _top_bar and _top_bar.has_method("set_mode"):
		_top_bar.set_mode(mode)


## Get current tiling mode
func get_mode() -> int:
	if _top_bar and _top_bar.has_method("get_mode"):
		return _top_bar.get_mode()
	return 0


## Update the status display (rotation, tilt, flip state)
## @param rotation_steps: Current rotation steps (0-3)
## @param tilt_index: Current tilt index
## @param is_flipped: Whether face is flipped
func update_status(rotation_steps: int, tilt_index: int, is_flipped: bool) -> void:
	if _side_toolbar and _side_toolbar.has_method("update_status"):
		_side_toolbar.update_status(rotation_steps, tilt_index, is_flipped)


## Set visibility of all UI components (top bar and side toolbar)
## Called by plugin's _make_visible() when node selection changes
## @param visible: True to show, false to hide
func set_ui_visible(visible: bool) -> void:
	if _top_bar:
		_top_bar.visible = visible
	if _side_toolbar:
		_side_toolbar.visible = visible
	_is_visible = visible

# =============================================================================
# SECTION: PRIVATE METHODS
# =============================================================================

## Sync UI state from the given node's settings
## @param node: TileMapLayer3D node with settings to read
func _sync_ui_from_node(node: Node) -> void:
	# Read settings from node and update UI components
	if not node:
		return

	var settings = node.get("settings")
	if not settings:
		return

	# Sync top bar from settings
	if _top_bar and _top_bar.has_method("sync_from_settings"):
		_top_bar.sync_from_settings(settings)


## Reset UI to default state (no node selected)
func _reset_ui_state() -> void:
	if _top_bar and _top_bar.has_method("sync_from_settings"):
		_top_bar.sync_from_settings(null)

# =============================================================================
# SECTION: SIGNAL HANDLERS (from UI components)
# =============================================================================

## Called when enable toggle changes in top bar
func _on_top_bar_enabled_changed(pressed: bool) -> void:
	enabled_changed.emit(pressed)


## Called when tiling mode changes in top bar (user clicked Manual/Auto button)
func _on_top_bar_mode_changed(mode: int) -> void:
	# Update current node's settings
	if _current_node:
		var settings = _current_node.get("settings")
		if settings:
			settings.set("tiling_mode", mode)

	# Emit signal for plugin to handle additional logic
	mode_changed.emit(mode)

	# Update dock panel to show correct content for mode (sync top bar → dock)
	if _tileset_panel and _tileset_panel.has_method("set_tiling_mode_from_external"):
		_tileset_panel.set_tiling_mode_from_external(mode)


## Called when TilesetPanel tab changes (user clicked tab in dock)
## This syncs dock → top bar
func _on_tileset_panel_mode_changed(mode: int) -> void:
	# Update top bar to reflect the new mode (without emitting signal to avoid loop)
	if _top_bar and _top_bar.has_method("set_mode"):
		_top_bar.set_mode(mode)

	# Note: The plugin already handles the mode change via its own connection
	# to tileset_panel.tiling_mode_changed, so we don't emit mode_changed here


## Called when rotation is requested from side toolbar
func _on_side_toolbar_rotate_requested(direction: int) -> void:
	rotate_requested.emit(direction)


## Called when tilt is requested from side toolbar
func _on_side_toolbar_tilt_requested(reverse: bool) -> void:
	tilt_requested.emit(reverse)


## Called when reset is requested from side toolbar
func _on_side_toolbar_reset_requested() -> void:
	reset_requested.emit()


## Called when flip is requested from side toolbar
func _on_side_toolbar_flip_requested() -> void:
	flip_requested.emit()
