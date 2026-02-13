@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	dock = preload("res://addons/ai_engine/ai_dock.tscn").instantiate()
	dock.editor_plugin = self
	add_control_to_bottom_panel(dock, "🎮 AI Engine")

func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
