@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	# Enable silent auto-reload for scripts (suppress "file modified externally" dialog)
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting(
		"text_editor/behavior/files/auto_reload_scripts_on_external_change", true
	)

	dock = preload("res://addons/ai_engine/ai_dock.tscn").instantiate()
	dock.editor_plugin = self
	add_control_to_bottom_panel(dock, "🎮 AI Engine")

func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
