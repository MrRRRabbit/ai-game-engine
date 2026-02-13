@tool
extends VBoxContainer

var editor_plugin: EditorPlugin

var chat_history: RichTextLabel
var input_field: LineEdit
var send_btn: Button
var status_label: Label
var game_type_selector: OptionButton

var conversation: Array[Dictionary] = []
var is_generating: bool = false
var worker_thread: Thread

# Auto-repair state
var repair_attempt: int = 0
const MAX_REPAIR_ATTEMPTS := 3
var last_generated_files: Array = []

# JSON retry state
var json_retry_attempt: int = 0
const MAX_JSON_RETRIES := 2
var last_user_prompt: String = ""

# Game type detection
enum GameType { UNIVERSAL, PLATFORMER, SNAKE, BREAKOUT, SHOOTER }
var current_game_type: int = GameType.UNIVERSAL

const GAME_TYPE_KEYWORDS := {
	GameType.PLATFORMER: ["platformer", "platform", "平台跳跃", "平台", "跳跃游戏", "mario", "jump", "横版"],
	GameType.SNAKE: ["snake", "贪吃蛇", "蛇", "贪食蛇"],
	GameType.BREAKOUT: ["breakout", "打砖块", "砖块", "brick", "arkanoid", "弹球", "paddle"],
	GameType.SHOOTER: ["shooter", "射击", "shooting", "弹幕", "shmup", "太空", "飞机大战", "bullet"],
}

const GAME_TYPE_NAMES := {
	GameType.UNIVERSAL: "Auto-detect",
	GameType.PLATFORMER: "Platformer",
	GameType.SNAKE: "Snake",
	GameType.BREAKOUT: "Breakout",
	GameType.SHOOTER: "Shooter",
}

# ---------------------------------------------------------------------------
# System prompt (base + game-specific rules)
# ---------------------------------------------------------------------------
const BASE_PROMPT := """You are an expert Godot 4 game developer integrated into the Godot editor.
You help users create and modify games through natural language.

You must output a valid JSON object with this exact structure:
{
  "action": "create" or "modify",
  "message": "brief description of what you did",
  "files": [
    {
      "path": "res://relative/path",
      "content": "full file content"
    }
  ]
}

RULES:
- For "create": generate a complete game with project.godot, scenes, and scripts.
- For "modify": only include files that need to change. Unchanged files should be omitted.
- All paths must start with "res://"
- Use ONLY built-in Godot 4 nodes and ColorRect/Polygon2D for visuals (no external assets).
- Use Godot 4.x syntax (CharacterBody2D, @onready, etc.)
- Include proper collision shapes for all physics bodies.
- Use call_group() for cross-node communication.
- Include UI layer with score/status when relevant.
- All ext_resource id values in .tscn files must match correctly.
- load_steps count must match the actual number of ext_resource + sub_resource entries.
- All node parent paths must be valid and refer to existing ancestor nodes.
- All script references in scenes must point to existing .gd files with correct paths.
- Groups used in call_group() must have corresponding add_to_group() calls.
- Signal connections must reference methods that actually exist on the target script.
- Avoid duplicate node names under the same parent.

When modifying, look at the CURRENT PROJECT FILES provided and make targeted changes.
Output ONLY the JSON object."""

const GAME_RULES_PLATFORMER := """
GAME-SPECIFIC RULES (Platformer):
- Use CharacterBody2D for the player with gravity ~980.0 and jump velocity ~-650.0.
- Make jump height sufficient to reach platforms.
- Player should reset if falling off screen.
- project.godot must have input mappings (physical_keycode: A=65, D=68, Space=32, Left=4194319, Right=4194321, Up=4194320).
- Use move_and_slide() for character movement.
- Include solid ground/platforms with StaticBody2D + CollisionShape2D.
- Camera follows player if level is larger than viewport."""

const GAME_RULES_SNAKE := """
GAME-SPECIFIC RULES (Snake / 贪吃蛇):
- Use a Timer node for movement ticks (interval ~0.15s for moderate speed).
- Grid-based movement: define a CELL_SIZE (e.g., 20-30 pixels), snap all positions to grid.
- Snake body is an Array of Vector2i grid positions. Head is body[0].
- Each tick: insert new head position at front, remove tail (unless just ate food).
- Food spawns at random empty grid cell using ColorRect or Polygon2D.
- Self-collision: check if new head position exists in body array.
- Wall collision: check grid boundaries.
- Growing: when head reaches food position, do NOT remove tail that tick, increment score.
- Input: 4-direction (Up/Down/Left/Right or W/A/S/D). Prevent 180-degree reversal.
- project.godot input mappings: W=87/Up=4194320, S=83/Down=4194322, A=65/Left=4194319, D=68/Right=4194321.
- Use Node2D as root. Draw snake segments and food using _draw() or individual ColorRect children.
- Do NOT use CharacterBody2D or physics — this is purely grid logic with Timer-driven updates."""

const GAME_RULES_BREAKOUT := """
GAME-SPECIFIC RULES (Breakout / 打砖块):
- Paddle: use CharacterBody2D or AnimatableBody2D at screen bottom, horizontal movement only.
- Ball: use CharacterBody2D with move_and_collide(). Reflect velocity on collision normal.
- Ball speed should be constant magnitude, only direction changes on bounce.
- Bricks: grid of StaticBody2D nodes. Use queue_free() on hit. Track remaining count.
- Brick grid: at least 4 rows x 8 columns. Use nested loops to generate positions.
- Lives system: 3 lives. Ball falls off bottom = lose a life, reset ball to paddle.
- Win condition: all bricks destroyed. Lose condition: 0 lives.
- project.godot input mappings: A=65/Left=4194319, D=68/Right=4194321 for paddle.
- Ball initial launch: slight random angle upward from paddle center.
- Walls: StaticBody2D on left, right, and top edges. No wall on bottom (ball falls out).
- Use collision layers to separate ball-brick, ball-paddle, and ball-wall interactions."""

const GAME_RULES_SHOOTER := """
GAME-SPECIFIC RULES (Shooter / 射击):
- Player ship: CharacterBody2D, moves in 2D (left/right, optionally up/down).
- Bullet spawning: instantiate bullet scene at player position on shoot input.
- Bullets: Area2D with CollisionShape2D, move upward at constant speed, queue_free() when off-screen.
- Enemy waves: use Timer to spawn enemies at top of screen. Enemies move downward.
- Enemy types: at minimum one basic enemy that moves down in straight line or slight zigzag.
- Damage system: enemies destroyed on bullet hit (body_entered signal). Player hit = lose life.
- Score: increment on enemy kill. Display in UI Label.
- project.godot input mappings: A=65/Left=4194319, D=68/Right=4194321 for movement, Space=32 for shoot.
- Use preload() for bullet and enemy scenes. Spawn via instantiate() + add_child().
- Screen bounds: prevent player from leaving viewport. Despawn enemies/bullets that exit screen.
- Collision layers: player on layer 1, enemies on layer 2, player bullets on layer 3."""

const REPAIR_PROMPT := """The code you generated has errors. Fix ALL of the following errors.

ERRORS DETECTED:
%s

CURRENT FILES THAT NEED FIXING:
%s

Output a JSON object with the fixed files. Include ALL files that need changes, with their COMPLETE content (not partial).
Fix every error listed above. Output ONLY the JSON object."""

const JSON_RETRY_PROMPT := """Your previous response was NOT valid JSON. You returned natural language text instead.

You MUST respond with ONLY a valid JSON object. No explanations, no analysis, no markdown.
The FIRST character of your response must be "{" and the last must be "}".

The user's original request was:
%s

%s
Respond with ONLY the JSON object. Nothing else."""


func _ready() -> void:
	# Get node references manually (more reliable than @onready in @tool scripts)
	chat_history = $ChatHistory
	input_field = $InputRow/InputField
	send_btn = $InputRow/SendBtn
	status_label = $StatusBar/StatusLabel
	game_type_selector = get_node_or_null("GameTypeRow/GameTypeSelector")

	if not send_btn or not input_field or not chat_history:
		push_error("AI Engine: Required UI nodes not found")
		return

	send_btn.pressed.connect(_on_send)
	input_field.text_submitted.connect(_on_text_submitted)

	# Populate game type dropdown
	if game_type_selector:
		game_type_selector.add_item("Auto-detect", GameType.UNIVERSAL)
		game_type_selector.add_item("Platformer / 平台跳跃", GameType.PLATFORMER)
		game_type_selector.add_item("Snake / 贪吃蛇", GameType.SNAKE)
		game_type_selector.add_item("Breakout / 打砖块", GameType.BREAKOUT)
		game_type_selector.add_item("Shooter / 射击", GameType.SHOOTER)
		game_type_selector.selected = 0
		game_type_selector.item_selected.connect(_on_game_type_selected)

	_append_system("🎮 AI Game Engine v0.4")
	_append_system("Game type templates: Platformer, Snake, Breakout, Shooter (auto-detected or select above).")
	_append_system("Type a game description to create, or describe changes to modify.")


func _on_text_submitted(_text: String) -> void:
	_on_send()


func _on_send() -> void:
	var text := input_field.text.strip_edges()
	if text.is_empty() or is_generating:
		return

	input_field.text = ""
	_append_user(text)
	repair_attempt = 0
	json_retry_attempt = 0

	# Game type detection / selection
	if game_type_selector:
		var dropdown_type: int = game_type_selector.get_item_id(game_type_selector.selected)
		if dropdown_type != GameType.UNIVERSAL:
			# User explicitly selected a type — use it
			current_game_type = dropdown_type
		else:
			# Auto-detect from text
			var detected := _detect_game_type(text)
			if detected != GameType.UNIVERSAL:
				current_game_type = detected
				# Update dropdown to show detected type (visual feedback)
				for i in range(game_type_selector.item_count):
					if game_type_selector.get_item_id(i) == detected:
						game_type_selector.selected = i
						break
				_append_system("🎯 Detected game type: %s" % GAME_TYPE_NAMES.get(detected, "Unknown"))
			# else: keep current_game_type from previous message (sticky)
	else:
		# No dropdown available — auto-detect only
		var detected := _detect_game_type(text)
		if detected != GameType.UNIVERSAL:
			current_game_type = detected
			_append_system("🎯 Detected game type: %s" % GAME_TYPE_NAMES.get(detected, "Unknown"))

	_start_generation(text)


func _on_game_type_selected(index: int) -> void:
	var selected_id: int = game_type_selector.get_item_id(index)
	current_game_type = selected_id
	if current_game_type != GameType.UNIVERSAL:
		_append_system("Game type set to: %s" % game_type_selector.get_item_text(index))
	else:
		_append_system("Game type set to auto-detect.")


# ---------------------------------------------------------------------------
# Prompt composition & game type detection
# ---------------------------------------------------------------------------
func _build_system_prompt(game_type: int) -> String:
	var rules := ""
	match game_type:
		GameType.PLATFORMER:
			rules = GAME_RULES_PLATFORMER
		GameType.SNAKE:
			rules = GAME_RULES_SNAKE
		GameType.BREAKOUT:
			rules = GAME_RULES_BREAKOUT
		GameType.SHOOTER:
			rules = GAME_RULES_SHOOTER
		_:
			# Universal fallback: use platformer rules (matches v0.3 behavior)
			rules = GAME_RULES_PLATFORMER
	return BASE_PROMPT + "\n" + rules


func _detect_game_type(user_text: String) -> int:
	var lower := user_text.to_lower()
	for game_type in GAME_TYPE_KEYWORDS:
		for keyword in GAME_TYPE_KEYWORDS[game_type]:
			if lower.find(keyword) >= 0:
				return game_type
	return GameType.UNIVERSAL


# ---------------------------------------------------------------------------
# Chat display
# ---------------------------------------------------------------------------
func _append_user(text: String) -> void:
	chat_history.append_text("\n[b][color=cyan]You:[/color][/b] " + text + "\n")

func _append_ai(text: String) -> void:
	chat_history.append_text("[b][color=green]AI:[/color][/b] " + text + "\n")

func _append_system(text: String) -> void:
	chat_history.append_text("[color=gray]" + text + "[/color]\n")

func _append_error(text: String) -> void:
	chat_history.append_text("[color=red]❌ " + text + "[/color]\n")

func _append_repair(text: String) -> void:
	chat_history.append_text("[color=yellow]🔧 " + text + "[/color]\n")


# ---------------------------------------------------------------------------
# Project context gathering
# ---------------------------------------------------------------------------
func _get_project_context() -> String:
	var context := "CURRENT PROJECT FILES:\n"
	var files := _scan_project_files("res://", [])

	if files.is_empty():
		return "CURRENT PROJECT FILES: (empty project)\n"

	for path in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			if content.length() > 3000:
				content = content.substr(0, 3000) + "\n... (truncated)"
			context += "\n--- %s ---\n%s\n" % [path, content]

	return context


func _scan_project_files(dir_path: String, result: Array) -> Array:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			if file_name != "addons" and file_name != ".godot" and not file_name.begins_with("."):
				_scan_project_files(full_path, result)
		else:
			if file_name.ends_with(".gd") or file_name.ends_with(".tscn") or file_name.ends_with(".tres") or file_name == "project.godot":
				result.append(full_path)

		file_name = dir.get_next()

	return result


# ---------------------------------------------------------------------------
# Error detection & validation
# ---------------------------------------------------------------------------
func _validate_generated_files() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	for file_info in last_generated_files:
		var path: String = file_info.get("path", "")
		var content: String = file_info.get("content", "")

		if path.is_empty():
			continue

		if path.ends_with(".gd"):
			errors.append_array(_validate_gdscript(path, content))
			warnings.append_array(_check_unused_variables(path, content.split("\n")))
			warnings.append_array(_check_unused_functions_cross_file(path, content.split("\n")))
		elif path.ends_with(".tscn"):
			errors.append_array(_validate_scene(path, content))

	return {"errors": errors, "warnings": warnings}


func _validate_gdscript(path: String, content: String) -> Array[String]:
	var errors: Array[String] = []
	var lines := content.split("\n")

	# Check: Must have extends
	var has_extends := false
	for line in lines:
		if line.strip_edges().begins_with("extends "):
			has_extends = true
			break
	if not has_extends and not content.strip_edges().is_empty():
		errors.append("[%s] Missing 'extends' declaration" % path)

	for i in range(lines.size()):
		var line := lines[i].strip_edges()
		if line.begins_with("#"):
			continue

		# Godot 3 syntax checks
		if "onready var" in line and "@onready" not in line:
			errors.append("[%s:%d] Use '@onready var' instead of 'onready var' (Godot 4)" % [path, i + 1])

		if "export var" in line and "@export" not in line:
			errors.append("[%s:%d] Use '@export var' instead of 'export var' (Godot 4)" % [path, i + 1])

		if "KinematicBody2D" in line:
			errors.append("[%s:%d] Use 'CharacterBody2D' instead of 'KinematicBody2D' (Godot 4)" % [path, i + 1])

		if "move_and_slide(velocity" in line:
			errors.append("[%s:%d] In Godot 4, move_and_slide() takes no args. Set velocity property first." % [path, i + 1])

		if line.begins_with("yield") or " yield(" in line:
			errors.append("[%s:%d] Use 'await' instead of 'yield' (Godot 4)" % [path, i + 1])

		if ".connect(\"" in line:
			errors.append("[%s:%d] Use new signal syntax: signal.connect(callable) not connect(\"string\")" % [path, i + 1])

	return errors


func _check_unused_variables(path: String, lines: PackedStringArray) -> Array[String]:
	var warnings: Array[String] = []

	# Collect declared variables: { name: line_number }
	var declarations := {}
	for i in range(lines.size()):
		var line := lines[i].strip_edges()
		if line.begins_with("#"):
			continue

		var var_name := _extract_var_name(line)
		if not var_name.is_empty():
			declarations[var_name] = i + 1

	# Check each declared variable for usage elsewhere
	for var_name in declarations:
		var decl_line_idx: int = declarations[var_name] - 1

		# Skip @export variables — they are set from the Godot editor Inspector
		var decl_line := lines[decl_line_idx].strip_edges()
		if "@export" in decl_line:
			continue

		var is_used := false

		for i in range(lines.size()):
			if i == decl_line_idx:
				continue
			var line := lines[i]
			# Skip comments
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			# Check if the variable name appears as a whole word
			if _contains_identifier(line, var_name):
				is_used = true
				break

		if not is_used:
			warnings.append("[%s:%d] Variable '%s' is declared but never used" % [
				path, declarations[var_name], var_name
			])

	return warnings


func _extract_var_name(line: String) -> String:
	# Matches: var x, @onready var x, @export var x, static var x
	# Skips: lines inside func bodies that are parameters, const, enum
	var patterns := ["@onready var ", "@export var ", "static var ", "var "]
	for pattern in patterns:
		var pos := line.find(pattern)
		if pos >= 0:
			var after := line.substr(pos + pattern.length()).strip_edges()
			# Extract identifier: stops at :, =, space, or end
			var var_name := ""
			for ch_idx in range(after.length()):
				var ch := after[ch_idx]
				if ch == ":" or ch == "=" or ch == " " or ch == "\t":
					break
				var_name += ch
			if not var_name.is_empty():
				return var_name
	return ""


func _contains_identifier(line: String, identifier: String) -> bool:
	var search_start := 0
	while true:
		var pos := line.find(identifier, search_start)
		if pos < 0:
			return false

		# Check left boundary: must be start of line or non-identifier char
		var left_ok := (pos == 0) or not _is_identifier_char(line[pos - 1])
		# Check right boundary
		var end_pos := pos + identifier.length()
		var right_ok := (end_pos >= line.length()) or not _is_identifier_char(line[end_pos])

		if left_ok and right_ok:
			return true

		search_start = pos + 1
	return false


func _is_identifier_char(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or \
		(ch >= "0" and ch <= "9") or ch == "_"


func _check_unused_functions_cross_file(path: String, lines: PackedStringArray) -> Array[String]:
	var warnings: Array[String] = []

	# Built-in callbacks that Godot calls automatically — never flag these
	var builtin_callbacks := [
		"_ready", "_process", "_physics_process", "_input", "_unhandled_input",
		"_unhandled_key_input", "_enter_tree", "_exit_tree", "_notification",
		"_draw", "_gui_input", "_get_configuration_warnings",
		"_get_minimum_size", "_make_custom_tooltip",
		"_init", "_static_init", "_to_string",
	]

	# Collect declared functions: { name: line_number }
	var declarations := {}
	for i in range(lines.size()):
		var line := lines[i].strip_edges()
		if line.begins_with("#"):
			continue
		if line.begins_with("func ") or line.begins_with("static func "):
			var func_name := _extract_func_name(line)
			if func_name.is_empty():
				continue
			# Skip builtins
			if func_name in builtin_callbacks:
				continue
			# Skip signal handler naming conventions (called externally or via connect)
			if func_name.begins_with("_on_") or func_name.begins_with("on_"):
				continue
			declarations[func_name] = i + 1

	# Check each declared function for references
	for func_name in declarations:
		var decl_line_idx: int = declarations[func_name] - 1
		var is_used := false

		# 1) Search within the same file
		for i in range(lines.size()):
			if i == decl_line_idx:
				continue
			var line := lines[i]
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.begins_with("func ") or stripped.begins_with("static func "):
				continue
			if _contains_identifier(line, func_name):
				is_used = true
				break

		# 2) Search all other generated files (cross-file: direct refs + string refs)
		if not is_used:
			for other_file in last_generated_files:
				var other_path: String = other_file.get("path", "")
				var other_content: String = other_file.get("content", "")
				if other_path == path or other_path.is_empty():
					continue
				if _contains_identifier(other_content, func_name):
					is_used = true
					break
				if _content_has_string_ref(other_content, func_name):
					is_used = true
					break

		if not is_used:
			warnings.append("[%s:%d] Function '%s' is declared but never referenced" % [
				path, declarations[func_name], func_name
			])

	return warnings


func _content_has_string_ref(content: String, func_name: String) -> bool:
	# Matches function name inside string literals (catches call_group patterns)
	return content.find("\"%s\"" % func_name) >= 0 or content.find("'%s'" % func_name) >= 0


func _extract_func_name(line: String) -> String:
	var prefix := "func "
	if line.begins_with("static func "):
		prefix = "static func "
	var pos := line.find(prefix)
	if pos < 0:
		return ""
	var after := line.substr(pos + prefix.length()).strip_edges()
	var func_name := ""
	for ch_idx in range(after.length()):
		var ch := after[ch_idx]
		if ch == "(" or ch == " " or ch == ":":
			break
		func_name += ch
	return func_name


func _validate_scene(path: String, content: String) -> Array[String]:
	var errors: Array[String] = []
	var lines := content.split("\n")

	var declared_load_steps := 0
	var actual_resources := 0
	var node_names := {}
	var script_paths := []

	for line in lines:
		var stripped := line.strip_edges()

		# Parse load_steps
		if stripped.begins_with("[gd_scene"):
			var ls_pos := stripped.find("load_steps=")
			if ls_pos >= 0:
				var num_start := ls_pos + 11
				var num_end := num_start
				while num_end < stripped.length() and stripped[num_end].is_valid_int():
					num_end += 1
				if num_end > num_start:
					declared_load_steps = stripped.substr(num_start, num_end - num_start).to_int()

		# Count resources
		if stripped.begins_with("[ext_resource"):
			actual_resources += 1
			if "type=\"Script\"" in stripped or "type=\"GDScript\"" in stripped:
				var p_pos := stripped.find("path=\"")
				if p_pos >= 0:
					var p_start := p_pos + 6
					var p_end := stripped.find("\"", p_start)
					if p_end > p_start:
						script_paths.append(stripped.substr(p_start, p_end - p_start))

		if stripped.begins_with("[sub_resource"):
			actual_resources += 1

		# Check duplicate node names
		if stripped.begins_with("[node name=\""):
			var name_start := 12
			var name_end := stripped.find("\"", name_start)
			if name_end > name_start:
				var node_name := stripped.substr(name_start, name_end - name_start)
				var parent := "."
				var par_pos := stripped.find("parent=\"")
				if par_pos >= 0:
					var par_start := par_pos + 8
					var par_end := stripped.find("\"", par_start)
					if par_end > par_start:
						parent = stripped.substr(par_start, par_end - par_start)

				if parent not in node_names:
					node_names[parent] = []
				if node_name in node_names[parent]:
					errors.append("[%s] Duplicate node name '%s' under parent '%s'" % [path, node_name, parent])
				else:
					node_names[parent].append(node_name)

	# Validate load_steps
	if declared_load_steps > 0 and actual_resources > 0:
		if declared_load_steps != actual_resources + 1:
			errors.append("[%s] load_steps=%d but found %d resources. Should be load_steps=%d" % [
				path, declared_load_steps, actual_resources, actual_resources + 1
			])

	# Check script files exist
	for script_path in script_paths:
		if not FileAccess.file_exists(script_path):
			var found := false
			for file_info in last_generated_files:
				if file_info.get("path", "") == script_path:
					found = true
					break
			if not found:
				errors.append("[%s] References missing script '%s'" % [path, script_path])

	return errors


func _capture_godot_errors() -> Array[String]:
	var errors: Array[String] = []

	var log_path := OS.get_user_data_dir().path_join("logs")
	var dir := DirAccess.open(log_path)
	if not dir:
		return errors

	var latest_log := ""
	var latest_time := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".log"):
			var full := log_path.path_join(fname)
			var mod_time := FileAccess.get_modified_time(full)
			if mod_time > latest_time:
				latest_time = mod_time
				latest_log = full
		fname = dir.get_next()

	if latest_log.is_empty():
		return errors

	var file := FileAccess.open(latest_log, FileAccess.READ)
	if not file:
		return errors

	var content := file.get_as_text()
	var lines := content.split("\n")

	var start_idx := max(0, lines.size() - 50)
	for i in range(start_idx, lines.size()):
		var line := lines[i]
		# Capture both ERROR and WARNING level entries referencing project files
		var is_error := "ERROR" in line and "res://" in line
		var is_warning := "WARNING" in line and "res://" in line
		if (is_error or is_warning):
			# Filter out addon/editor noise
			if "addons/ai_engine" not in line:
				errors.append(line.strip_edges())

	return errors


# ---------------------------------------------------------------------------
# Generation (threaded)
# ---------------------------------------------------------------------------
func _start_generation(user_text: String, is_repair: bool = false) -> void:
	is_generating = true
	send_btn.disabled = true

	if is_repair:
		status_label.text = "🔧 Auto-repairing (%d/%d)..." % [repair_attempt, MAX_REPAIR_ATTEMPTS]
	else:
		status_label.text = "⏳ Generating..."

	var system_prompt := _build_system_prompt(current_game_type)
	var full_prompt: String

	if is_repair:
		full_prompt = system_prompt + "\n\n" + user_text + "\n\nIMPORTANT: Your response must be ONLY a valid JSON object starting with { — no other text."
	else:
		last_user_prompt = user_text
		conversation.append({"role": "user", "content": user_text})

		var project_context := _get_project_context()
		var history_text := ""
		for msg in conversation:
			var prefix = "User" if msg.role == "user" else "Assistant"
			history_text += "%s: %s\n" % [prefix, msg.content]

		full_prompt = "%s\n\n%s\nCONVERSATION:\n%s\n\nIMPORTANT: Your response must be ONLY a valid JSON object starting with { — no other text." % [
			system_prompt, project_context, history_text
		]

	worker_thread = Thread.new()
	worker_thread.start(_call_claude_cli.bind(full_prompt))


func _call_claude_cli(prompt: String) -> Dictionary:
	var output := []

	var temp_path := OS.get_temp_dir().path_join("ai_engine_prompt.txt")
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file:
		temp_file.store_string(prompt)
		temp_file.close()

	var shell_cmd: String
	var shell_args: PackedStringArray

	if OS.get_name() == "macOS" or OS.get_name() == "Linux":
		shell_cmd = "/bin/bash"
		shell_args = PackedStringArray(["-c", "cat '%s' | claude --print --output-format text" % temp_path])
	else:
		shell_cmd = "cmd"
		shell_args = PackedStringArray(["/c", "type \"%s\" | claude --print --output-format text" % temp_path])

	var exit_code := OS.execute(shell_cmd, shell_args, output, true, false)

	DirAccess.remove_absolute(temp_path)

	var result := {"exit_code": exit_code, "output": ""}
	if output.size() > 0:
		result.output = output[0]

	call_deferred("_on_generation_complete", result)
	return result


func _on_generation_complete(result: Dictionary) -> void:
	if worker_thread and worker_thread.is_started():
		worker_thread.wait_to_finish()
		worker_thread = null

	if result.exit_code != 0:
		is_generating = false
		send_btn.disabled = false
		_append_error("Claude CLI failed (exit code %d)" % result.exit_code)
		status_label.text = "Error"
		return

	var response_text: String = result.output.strip_edges()
	if response_text.is_empty():
		is_generating = false
		send_btn.disabled = false
		_append_error("Empty response from Claude CLI")
		status_label.text = "Error"
		return

	# Parse JSON
	var json_text := _extract_json(response_text)
	var json := JSON.new()
	var parse_result := json.parse(json_text)

	if parse_result != OK:
		# Auto-retry with stronger JSON enforcement
		if json_retry_attempt < MAX_JSON_RETRIES:
			json_retry_attempt += 1
			_append_repair("Response was not JSON, retrying (%d/%d)..." % [
				json_retry_attempt, MAX_JSON_RETRIES
			])
			var project_context := _get_project_context()
			var retry_prompt := JSON_RETRY_PROMPT % [last_user_prompt, project_context]
			_start_generation(retry_prompt, true)
			return

		# Retries exhausted, show error
		is_generating = false
		send_btn.disabled = false
		json_retry_attempt = 0
		_append_error("Failed to parse AI response as JSON")
		_append_system("Raw (first 300 chars): " + response_text.substr(0, 300))
		var debug_file := FileAccess.open("res://ai_debug_response.txt", FileAccess.WRITE)
		if debug_file:
			debug_file.store_string(response_text)
			debug_file.close()
		status_label.text = "Parse error"
		return

	var data: Dictionary = json.data
	json_retry_attempt = 0
	var action: String = data.get("action", "create")
	var message: String = data.get("message", "Done")
	var files: Array = data.get("files", [])

	last_generated_files = files

	# Write files
	var file_count := 0
	for file_info in files:
		var path: String = file_info.get("path", "")
		var content: String = file_info.get("content", "")

		if path.is_empty():
			continue

		var dir_path := path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)

		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(content)
			file.close()
			file_count += 1

	# Refresh editor: hot-reload first, then deferred filesystem scan
	# Order matters: reload updates editor's cached timestamps BEFORE scan
	# detects changes, preventing the "file modified externally" dialog.
	if editor_plugin:
		var ei := editor_plugin.get_editor_interface()
		_hot_reload_edited_scenes(ei, files)
		ei.get_resource_filesystem().call_deferred("scan")

	# --- Validation & Auto-Repair ---
	var validation_result := _validate_generated_files()
	var validation_errors: Array[String] = validation_result.get("errors", [])
	var validation_warnings: Array[String] = validation_result.get("warnings", [])
	var godot_errors := _capture_godot_errors()

	# Only hard errors trigger auto-repair (not warnings)
	var all_errors: Array[String] = []
	all_errors.append_array(validation_errors)
	all_errors.append_array(godot_errors)

	if all_errors.size() > 0 and repair_attempt < MAX_REPAIR_ATTEMPTS:
		repair_attempt += 1
		_append_ai("%s (%d files written)" % [message, file_count])
		_append_repair("Detected %d error(s), auto-repairing (%d/%d)..." % [
			all_errors.size(), repair_attempt, MAX_REPAIR_ATTEMPTS
		])
		for err in all_errors:
			_append_system("  • " + err)

		# Build repair context
		var files_context := ""
		for file_info in last_generated_files:
			files_context += "\n--- %s ---\n%s\n" % [file_info.get("path", ""), file_info.get("content", "")]

		var error_text := "\n".join(all_errors)
		var repair_prompt := REPAIR_PROMPT % [error_text, files_context]

		_start_generation(repair_prompt, true)
		return

	# --- Done ---
	is_generating = false
	send_btn.disabled = false

	conversation.append({"role": "assistant", "content": message})

	if all_errors.size() > 0:
		_append_ai("%s (%d files written)" % [message, file_count])
		_append_repair("Some errors remain after %d attempts:" % MAX_REPAIR_ATTEMPTS)
		for err in all_errors:
			_append_system("  • " + err)
		status_label.text = "Done with warnings — %d files" % file_count
	else:
		_append_ai("%s (%d files %s) ✅" % [message, file_count, "created" if action == "create" else "modified"])
		if repair_attempt > 0:
			_append_repair("All errors fixed after %d attempt(s)!" % repair_attempt)
		status_label.text = "Ready ✅ — %d files" % file_count

	# Show warnings as informational notes (do NOT trigger repair)
	if validation_warnings.size() > 0:
		_append_system("ℹ️ Notes (%d):" % validation_warnings.size())
		for w in validation_warnings:
			_append_system("  · " + w)


# ---------------------------------------------------------------------------
# JSON extraction helper
# ---------------------------------------------------------------------------
func _extract_json(text: String) -> String:
	var cleaned := text
	if cleaned.begins_with("```"):
		var lines := cleaned.split("\n")
		if lines.size() > 2:
			lines.remove_at(0)
			if lines[lines.size() - 1].strip_edges() == "```":
				lines.remove_at(lines.size() - 1)
			cleaned = "\n".join(lines)

	var start := cleaned.find("{")
	var end := cleaned.rfind("}")

	if start >= 0 and end > start:
		return cleaned.substr(start, end - start + 1)

	return cleaned


# ---------------------------------------------------------------------------
# Hot-reload: reload open scenes & scripts after file generation
# ---------------------------------------------------------------------------
func _hot_reload_edited_scenes(ei: EditorInterface, files: Array) -> void:
	# Scripts: auto-reloaded by Godot via auto_reload_scripts_on_external_change
	# setting (enabled in plugin.gd). No manual call needed.
	# Scenes: must be explicitly reloaded to update cached timestamps.
	var scene_paths: Array[String] = []
	for file_info in files:
		var path: String = file_info.get("path", "")
		if path.ends_with(".tscn") or path.ends_with(".tres"):
			scene_paths.append(path)

	var open_scenes := ei.get_open_scenes()
	for scene_path in open_scenes:
		if scene_path in scene_paths:
			ei.reload_scene_from_path(scene_path)
