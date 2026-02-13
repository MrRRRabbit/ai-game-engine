@tool
extends VBoxContainer

var editor_plugin: EditorPlugin

@onready var chat_history: RichTextLabel = $ChatHistory
@onready var input_field: LineEdit = $InputRow/InputField
@onready var send_btn: Button = $InputRow/SendBtn
@onready var status_label: Label = $StatusBar/StatusLabel

var conversation: Array[Dictionary] = []
var is_generating: bool = false
var worker_thread: Thread

# ---------------------------------------------------------------------------
# System prompt
# ---------------------------------------------------------------------------
const SYSTEM_PROMPT := """You are an expert Godot 4 game developer integrated into the Godot editor.
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
- Gravity ~980.0, jump velocity ~-650.0
- Make jump height sufficient to reach platforms.
- Player should reset if falling off screen.
- Include UI layer with score/status when relevant.
- project.godot must have input mappings (physical_keycode: A=65, D=68, Space=32, Left=4194319, Right=4194321, Up=4194320).

When modifying, look at the CURRENT PROJECT FILES provided and make targeted changes.
Output ONLY the JSON object."""


func _ready() -> void:
	send_btn.pressed.connect(_on_send)
	input_field.text_submitted.connect(_on_text_submitted)
	_append_system("🎮 AI Game Engine v0.2")
	_append_system("Type a game description to create, or describe changes to modify.")
	_append_system("Example: \"做一个2D平台跳跃游戏\" or \"加一个会巡逻的敌人\"")


func _on_text_submitted(_text: String) -> void:
	_on_send()


func _on_send() -> void:
	var text := input_field.text.strip_edges()
	if text.is_empty() or is_generating:
		return

	input_field.text = ""
	_append_user(text)
	_start_generation(text)


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
			# Limit per-file size to avoid overwhelming the context
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
			# Skip addons and .godot directories
			if file_name != "addons" and file_name != ".godot" and not file_name.begins_with("."):
				_scan_project_files(full_path, result)
		else:
			# Include game-relevant files
			if file_name.ends_with(".gd") or file_name.ends_with(".tscn") or file_name.ends_with(".tres") or file_name == "project.godot":
				result.append(full_path)

		file_name = dir.get_next()

	return result


# ---------------------------------------------------------------------------
# Generation (threaded)
# ---------------------------------------------------------------------------
func _start_generation(user_text: String) -> void:
	is_generating = true
	send_btn.disabled = true
	status_label.text = "⏳ Generating..."

	# Build conversation context
	conversation.append({"role": "user", "content": user_text})

	# Build full prompt with project context
	var project_context := _get_project_context()

	var history_text := ""
	for msg in conversation:
		var prefix = "User" if msg.role == "user" else "Assistant"
		history_text += "%s: %s\n" % [prefix, msg.content]

	var full_prompt := "%s\n\n%s\nCONVERSATION:\n%s\nRespond with JSON only." % [
		SYSTEM_PROMPT, project_context, history_text
	]

	# Run in thread to avoid freezing editor
	worker_thread = Thread.new()
	worker_thread.start(_call_claude_cli.bind(full_prompt))


func _call_claude_cli(prompt: String) -> Dictionary:
	var output := []
	var exit_code := OS.execute("claude", ["--print", "--output-format", "text"], output, true, false)

	# OS.execute doesn't support stdin easily, so we write prompt to temp file
	var temp_path := OS.get_temp_dir().path_join("ai_engine_prompt.txt")
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file:
		temp_file.store_string(prompt)
		temp_file.close()

	output.clear()

	# Use shell to pipe the temp file into claude CLI
	var shell_cmd: String
	var shell_args: PackedStringArray

	if OS.get_name() == "macOS" or OS.get_name() == "Linux":
		shell_cmd = "/bin/bash"
		shell_args = PackedStringArray(["-c", "cat '%s' | claude --print --output-format text" % temp_path])
	else:
		shell_cmd = "cmd"
		shell_args = PackedStringArray(["/c", "type \"%s\" | claude --print --output-format text" % temp_path])

	exit_code = OS.execute(shell_cmd, shell_args, output, true, false)

	# Clean up temp file
	DirAccess.remove_absolute(temp_path)

	var result := {"exit_code": exit_code, "output": ""}
	if output.size() > 0:
		result.output = output[0]

	# Call deferred to process result on main thread
	call_deferred("_on_generation_complete", result)
	return result


func _on_generation_complete(result: Dictionary) -> void:
	if worker_thread and worker_thread.is_started():
		worker_thread.wait_to_finish()
		worker_thread = null

	is_generating = false
	send_btn.disabled = false

	if result.exit_code != 0:
		_append_error("Claude CLI failed (exit code %d)" % result.exit_code)
		status_label.text = "Error"
		return

	var response_text: String = result.output.strip_edges()
	if response_text.is_empty():
		_append_error("Empty response from Claude CLI")
		status_label.text = "Error"
		return

	# Parse JSON from response
	var json_text := _extract_json(response_text)
	var json := JSON.new()
	var parse_result := json.parse(json_text)

	if parse_result != OK:
		_append_error("Failed to parse AI response as JSON")
		_append_system("Raw response (first 300 chars): " + response_text.substr(0, 300))
		# Save debug output
		var debug_file := FileAccess.open("res://ai_debug_response.txt", FileAccess.WRITE)
		if debug_file:
			debug_file.store_string(response_text)
			debug_file.close()
		status_label.text = "Parse error"
		return

	var data: Dictionary = json.data
	var action: String = data.get("action", "create")
	var message: String = data.get("message", "Done")
	var files: Array = data.get("files", [])

	# Store assistant response in conversation
	conversation.append({"role": "assistant", "content": message})

	# Write files
	var file_count := 0
	for file_info in files:
		var path: String = file_info.get("path", "")
		var content: String = file_info.get("content", "")

		if path.is_empty():
			continue

		# Ensure directory exists
		var dir_path := path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)

		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(content)
			file.close()
			file_count += 1

	# Refresh the editor filesystem so new files appear
	if editor_plugin:
		editor_plugin.get_editor_interface().get_resource_filesystem().scan()

	_append_ai("%s (%d files %s)" % [message, file_count, "created" if action == "create" else "modified"])
	status_label.text = "Ready — %d files written" % file_count


# ---------------------------------------------------------------------------
# JSON extraction helper
# ---------------------------------------------------------------------------
func _extract_json(text: String) -> String:
	# Remove markdown code fences if present
	var cleaned := text
	if cleaned.begins_with("```"):
		var lines := cleaned.split("\n")
		# Remove first line (```json) and last line (```)
		if lines.size() > 2:
			lines.remove_at(0)
			if lines[lines.size() - 1].strip_edges() == "```":
				lines.remove_at(lines.size() - 1)
			cleaned = "\n".join(lines)

	# Try to find JSON object boundaries
	var start := cleaned.find("{")
	var end := cleaned.rfind("}")

	if start >= 0 and end > start:
		return cleaned.substr(start, end - start + 1)

	return cleaned
