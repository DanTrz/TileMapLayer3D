# =============================================================================
# PURPOSE: UI Coordinator for TileMapLayer3D editor plugin
# =============================================================================
# This class manages all editor UI components and routes signals between
# the UI layer and the plugin. It serves as a single point of coordination
# for UI creation, visibility, and state synchronization.
#
# ARCHITECTURE:
#   - Created by TileMapLayer3DPlugin in _enter_tree()
#   - Manages: TileMainMenu, TileContextToolbar, TilesetPanel
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
const VIEWPORT_TOP: int = 1
const VIEWPORT_LEFT: int = 2
const VIEWPORT_RIGHT: int = 3
const VIEWPORT_BOTTOM: int = 4

# Preload UI component classes
# const TileMainToolbarClass = preload("uid://dqnu0nddbxutv")
# const TileContextToolbarClass = preload("uid://blhnwkxv1r6eg")
const TileContextToolbarScene = preload("uid://dgitfqnhx4ghe")
const TileMainToolbarScene = preload("uid://dinh7e08nxmrc")


# =============================================================================
# SECTION: SIGNALS
# =============================================================================

## Emitted when the enable toggle is changed
signal tiling_enabled_changed(enabled: bool)

## Emitted when tiling mode changes (Manual/Auto)
signal tilemap_main_mode_changed(mode: int)

## Emitted when rotation is requested (direction: +1 CW, -1 CCW)
signal rotate_requested(direction: int)

## Emitted when tilt cycling is requested (reverse: bool)
signal tilt_requested(reverse: bool)

## Emitted when reset to flat is requested
signal reset_requested()

## Emitted when face flip is requested
signal flip_requested()

signal smart_select_operation_requested(smart_mode: GlobalConstants.SmartSelectionOperation)


# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

## Reference to the main plugin (for accessing managers and EditorPlugin methods)
## Dynamic type (Object) for web export compatibility - EditorPlugin not available at runtime
var _plugin: Object = null

## Current active TileMapLayer3D node
var _active_tilema3d_node: TileMapLayer3D = null  # TileMapLayer3D

## UI is visible and active
var _is_visible: bool = false

# --- UI Components ---

## Main menu toolbar (enable toggle, mode buttons)
# var _main_toolbar: Control = null  # TileMainMenu
var _main_toolbar_scene: TileMainToolbar = null

## Secondary toolbar that shows the details (second level actions) depending on the Main Menu selection
var _context_toolbar: TileContextToolbar = null  # TileContextToolbar

## Default location for Main Menu toolbar (Left or Right side panel)
var _main_toolbar_location: int = VIEWPORT_LEFT

## Default location for context menu / secondary menu toolbar
var _contextual_toolbar_location: int = VIEWPORT_BOTTOM

## Reference to existing TilesetPanel (dock panel)
var _tileset_panel: TilesetPanel = null  # TilesetPanel

# =============================================================================
# SECTION: INITIALIZATION
# =============================================================================

## Initialize the UI coordinator
## @param plugin: Reference to TileMapLayer3DPlugin
func initialize(plugin: Object) -> void:
	_plugin = plugin
	_create_main_toolbar()
	_create_context_toolbar()

	# Start with UI hidden - will be shown when TileMapLayer3D is selected
	set_ui_visible(false)
	_sync_ui_from_node()


## Clean up all UI components
func cleanup() -> void:
	_disconnect_tileset_panel()
	_destroy_context_toolbar()
	_destroy_main_toolbar()
	_plugin = null
	_active_tilema3d_node = null
	_tileset_panel = null

# =============================================================================
# SECTION: MAIN MENU TOOLBAR
# =============================================================================

func _create_main_toolbar() -> void:
	if not _plugin:
		return

	_main_toolbar_scene = TileMainToolbarScene.instantiate()
	
	# Connect signals
	_main_toolbar_scene.main_toolbar_tiling_enabled_clicked.connect(_on_tiling_enabled_changed)
	_main_toolbar_scene.main_toolbar_mode_changed.connect(_on_mode_changed)



	# Add to editor's 3D toolbar
	_plugin.add_control_to_container(_main_toolbar_location, _main_toolbar_scene)


func _destroy_main_toolbar() -> void:
	if _main_toolbar_scene and _plugin:
		_plugin.remove_control_from_container(_main_toolbar_location, _main_toolbar_scene)
		_main_toolbar_scene.queue_free()
		_main_toolbar_scene = null

# =============================================================================
# SECTION: CONTEXT TOOLBAR
# =============================================================================

func _create_context_toolbar() -> void:
	if not _plugin:
		return

	# Create side toolbar using preloaded class
	_context_toolbar = TileContextToolbarScene.instantiate()

	# Connect signals from side toolbar to coordinator (routes to plugin)
	_context_toolbar.rotate_btn_pressed.connect(_on_rotate_btn_pressed)
	_context_toolbar.tilt_btn_pressed.connect(_on_tilt_btn_pressed)
	_context_toolbar.reset_btn_pressed.connect(_on_reset_btn_pressed)
	_context_toolbar.flip_btn_pressed.connect(_on_flip_btn_pressed)
	_context_toolbar.smart_select_mode_changed.connect(_on_smart_select_mode_changed)
	_context_toolbar.smart_select_operation_btn_pressed.connect(_on_smart_select_operation_btn_pressed)


	# Add to editor's left side panel
	_plugin.add_control_to_container(_contextual_toolbar_location, _context_toolbar)


func _destroy_context_toolbar() -> void:
	if _context_toolbar and _plugin:
		_plugin.remove_control_from_container(_contextual_toolbar_location, _context_toolbar)
		_context_toolbar.queue_free()
		_context_toolbar = null

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
func set_active_node(node: TileMapLayer3D) -> void:
	_active_tilema3d_node = node

	if node:
		_sync_ui_from_node()
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
	if _main_toolbar_scene and _main_toolbar_scene.has_method("set_enabled"):
		_main_toolbar_scene.set_enabled(enabled)
	_is_visible = enabled


## Get whether the plugin is currently enabled
func is_enabled() -> bool:
	if _main_toolbar_scene and _main_toolbar_scene.has_method("is_enabled"):
		return _main_toolbar_scene.is_enabled()
	return false


## Update the status display (rotation, tilt, flip state)
## @param rotation_steps: Current rotation steps (0-3)
## @param tilt_index: Current tilt index
## @param is_flipped: Whether face is flipped
func update_status(rotation_steps: int, tilt_index: int, is_flipped: bool) -> void:
	if _context_toolbar and _context_toolbar.has_method("update_status"):
		_context_toolbar.update_status(rotation_steps, tilt_index, is_flipped)


## Set visibility of all UI components (top bar and side toolbar)
## Called by plugin's _make_visible() when node selection changes
## @param visible: True to show, false to hide
func set_ui_visible(visible: bool) -> void:
	if _main_toolbar_scene:
		_main_toolbar_scene.visible = visible

	if _context_toolbar:
		_context_toolbar.visible = visible
	_is_visible = visible

# =============================================================================
# SECTION: PRIVATE METHODS
# =============================================================================

## Sync UI state from the given node's settings
## @param node: TileMapLayer3D node with settings to read
func _sync_ui_from_node() -> void:
	# Read settings from node and update UI components
	# print("Syncing UI from node: ", _active_tilema3d_node)
	if not _active_tilema3d_node:
		return

	# Sync top bar from settings
	if _main_toolbar_scene and _main_toolbar_scene.has_method("sync_from_settings"):
		_main_toolbar_scene.sync_from_settings(_active_tilema3d_node.settings)

	# Sync context toolbar smart select from settings
	if _context_toolbar and _context_toolbar.has_method("sync_from_settings"):
		_context_toolbar.sync_from_settings(_active_tilema3d_node.settings)
		# print("Context toolbar synced from node settings: ", _active_tilema3d_node.settings.smart_select_mode)



## Reset UI to default state (no node selected)
func _reset_ui_state() -> void:
	if _main_toolbar_scene and _main_toolbar_scene.has_method("sync_from_settings"):
		_main_toolbar_scene.sync_from_settings(null)
	
	if _context_toolbar and _context_toolbar.has_method("sync_from_settings"):
		_context_toolbar.sync_from_settings(null)

# =============================================================================
# SECTION: SIGNAL HANDLERS (from UI components)
# =============================================================================

## Called when enable toggle changes in top bar
func _on_tiling_enabled_changed(pressed: bool) -> void:
	tiling_enabled_changed.emit(pressed)


## Called when any mode button is clicked in main toolbar
## Receives both mode and smart select state as one atomic event
func _on_mode_changed(mode: GlobalConstants.MainAppMode, is_smart_select: bool) -> void:
	# Update settings (single source of truth)
	print("Main toolbar mode changed: ", mode, " Smart Select: ", is_smart_select)
	if _active_tilema3d_node:
		var settings: TileMapLayerSettings = _active_tilema3d_node.get("settings")
		if settings:
			settings.main_app_mode = mode

	# Emit for plugin (clears selection on autotile, toggles extension, updates preview)
	tilemap_main_mode_changed.emit(mode)

	# Sync dock panel tabs
	if _tileset_panel and _tileset_panel.has_method("set_tiling_mode_from_external"):
		_tileset_panel.set_tiling_mode_from_external(mode)

	# Update smart select state based on new mode (smart select only applies to manual mode)
	if mode == GlobalConstants.MainAppMode.AUTOTILE:
		update_smart_select_mode(false, 0)
	else:
		update_smart_select_mode(is_smart_select, _context_toolbar.smart_mode_option_btn.get_selected_id())

	# Context toolbar sync handles visibility of menus based on mode and smart select state
	if _context_toolbar and _active_tilema3d_node and _context_toolbar.has_method("sync_from_settings"):
		_context_toolbar.sync_from_settings(_active_tilema3d_node.settings)


func update_smart_select_mode(is_smart_select_on: bool, smart_mode: GlobalConstants.SmartSelectionMode) -> void:
	#Update settings to confirm smart select mode
	if _active_tilema3d_node.settings.is_smart_select_active != null:
		_active_tilema3d_node.settings.is_smart_select_active = is_smart_select_on

		if smart_mode != _active_tilema3d_node.settings.smart_select_mode:
			_active_tilema3d_node.clear_highlights() # Clear highlights when changing modes
			_active_tilema3d_node.smart_selected_tiles.clear() # Clear smart selection when changing
			_active_tilema3d_node.settings.smart_select_mode = smart_mode

	# Clear highlights when exiting smart select mode
	if not is_smart_select_on and _active_tilema3d_node:
		_active_tilema3d_node.clear_highlights()
		_active_tilema3d_node.smart_selected_tiles.clear()

## Captures the MODE change for Smart Selection : SINGLE_PICK, CONNECTED_UV, CONNECTED_NEIGHBOR
func _on_smart_select_mode_changed(smart_mode: GlobalConstants.SmartSelectionMode) -> void:
	if _active_tilema3d_node:
		update_smart_select_mode(_active_tilema3d_node.settings.is_smart_select_active, smart_mode)

## Captures the REPLACE/DELETE operations for Smart Selection
func _on_smart_select_operation_btn_pressed(smart_mode_operation: GlobalConstants.SmartSelectionOperation) -> void:
	# FUTURE FEATURE - TODO - DEBUG
	print("Smart Select Operation requested: ", smart_mode_operation)
	#This is passed on to the Plugin Main Class for processing the opearations
	smart_select_operation_requested.emit(smart_mode_operation) 

	#
## Called when TilesetPanel tab changes (user clicked tab in dock)
## This syncs dock → top bar
func _on_tileset_panel_mode_changed(mode: int) -> void:
	# Update top bar to reflect the new mode (without emitting signal to avoid loop)
	if _main_toolbar_scene and _main_toolbar_scene.has_method("set_mode"):
		_main_toolbar_scene.set_mode(mode)
	# Note: The plugin already handles the mode change via its own connection
	# to tileset_panel.tiling_mode_changed, so we don't emit tilemap_main_mode_changed here


## Called when rotation is requested from side toolbar
func _on_rotate_btn_pressed(direction: int) -> void:
	rotate_requested.emit(direction)


## Called when tilt is requested from side toolbar
func _on_tilt_btn_pressed(reverse: bool) -> void:
	tilt_requested.emit(reverse)


## Called when reset is requested from side toolbar
func _on_reset_btn_pressed() -> void:
	reset_requested.emit()


## Called when flip is requested from side toolbar
func _on_flip_btn_pressed() -> void:
	flip_requested.emit()
	
