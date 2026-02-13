#!/usr/bin/env python3
"""
AI Game Engine - Natural language to playable Godot 4 game generator.
Uses Claude Code CLI (Max subscription) as the AI backend.

Usage: python3 generate.py "做一个2D平台跳跃游戏，有3个平台和可收集的星星"
"""

import sys
import os
import json
import re
import subprocess


# ---------------------------------------------------------------------------
# System prompt: teaches Claude how to output valid Godot 4 project files
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = r"""You are an expert Godot 4 game developer. Your job is to generate COMPLETE, RUNNABLE Godot 4 projects from natural language descriptions.

You must output a valid JSON object with this exact structure:
{
  "project_name": "string",
  "files": [
    {
      "path": "relative/path/to/file",
      "content": "file content as string"
    }
  ]
}

CRITICAL RULES:
1. Always include a `project.godot` file with proper config, input mappings, and main_scene set.
2. Always include at least one .tscn scene file as the main scene.
3. All scripts (.gd files) must be separate files referenced by the scene via ext_resource.
4. Use ONLY built-in Godot nodes and ColorRect/Polygon2D for visuals (no external assets).
5. The game must be IMMEDIATELY PLAYABLE with no additional setup.
6. Use Godot 4.x syntax (CharacterBody2D, not KinematicBody2D; @onready, not onready).
7. Include proper collision shapes for all physics bodies.
8. For 2D games, use reasonable viewport size (800x600 or 1024x768).
9. Include a UI layer with score/status display when relevant.
10. Use input map actions defined in project.godot (move_left, move_right, jump, etc.).

INPUT MAPPING FORMAT for project.godot:
- Use physical_keycode for key bindings
- Common keys: A=65, D=68, W=87, S=83, Space=32, Left=4194319, Right=4194321, Up=4194320, Down=4194322

SCENE FILE FORMAT (.tscn):
- Use [gd_scene load_steps=N format=3] header
- Define ext_resource for scripts
- Define sub_resource for shapes and other inline resources
- Node tree uses [node name="X" type="Y" parent="Z"] format
- Root node has no parent attribute
- Use groups=["group_name"] for node grouping

GDSCRIPT RULES:
- Use `extends NodeType` as first line
- Use `@onready var` for node references
- Use `func _ready()`, `func _physics_process(delta)`, `func _process(delta)`
- CharacterBody2D: set velocity then call move_and_slide()
- Use call_group() for cross-node communication
- Gravity should be around 980.0, jump velocity around -600 to -700

IMPORTANT GAMEPLAY RULES:
- Make sure jump height is sufficient to reach platforms
- Make sure collision layers work correctly
- Add win/lose conditions when appropriate
- Player should reset if falling off screen

Output ONLY the JSON object, nothing else. No markdown, no explanation."""


def call_claude_cli(prompt: str, system: str) -> str:
    """Call Claude Code CLI in print mode and return the response."""

    full_prompt = f"""<system>
{system}
</system>

{prompt}"""

    try:
        result = subprocess.run(
            ["claude", "--print", "--output-format", "text"],
            input=full_prompt,
            capture_output=True,
            text=True,
            timeout=120
        )

        if result.returncode != 0:
            print(f"❌ Claude CLI error (exit code {result.returncode})")
            if result.stderr:
                print(f"   stderr: {result.stderr.strip()}")
            sys.exit(1)

        return result.stdout.strip()

    except FileNotFoundError:
        print("❌ Claude Code CLI not found.")
        print("   Install it with: npm install -g @anthropic-ai/claude-code")
        print("   Then run: claude login")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("❌ Claude CLI timed out (120s). Try a simpler game description.")
        sys.exit(1)


def generate_game(description: str, output_dir: str) -> None:
    """Call Claude CLI and generate a complete Godot project."""

    print(f"\n🎮 AI Game Engine v0.1")
    print(f"📝 Input: {description}")
    print(f"⏳ Generating game via Claude Code CLI...\n")

    prompt = f"Generate a complete Godot 4 game project for this description:\n\n{description}"
    response_text = call_claude_cli(prompt, SYSTEM_PROMPT)

    # Try to parse JSON - handle potential markdown wrapping
    cleaned = response_text
    if cleaned.startswith("```"):
        cleaned = re.sub(r'^```(?:json)?\s*', '', cleaned)
        cleaned = re.sub(r'\s*```$', '', cleaned)

    # Try to find JSON object in response
    json_match = re.search(r'\{[\s\S]*\}', cleaned)
    if json_match:
        cleaned = json_match.group(0)

    try:
        project = json.loads(cleaned)
    except json.JSONDecodeError as e:
        print(f"❌ Failed to parse AI response as JSON: {e}")
        print(f"Raw response (first 500 chars):\n{response_text[:500]}")
        # Save raw response for debugging
        debug_path = os.path.join(output_dir, "_debug_response.txt")
        os.makedirs(output_dir, exist_ok=True)
        with open(debug_path, 'w') as f:
            f.write(response_text)
        print(f"💾 Raw response saved to {debug_path}")
        sys.exit(1)

    project_name = project.get("project_name", "ai_generated_game")
    files = project.get("files", [])

    if not files:
        print("❌ AI returned no files")
        sys.exit(1)

    # Create output directory
    project_dir = os.path.join(output_dir, project_name)
    os.makedirs(project_dir, exist_ok=True)

    # Write all files
    print(f"📁 Project: {project_name}")
    print(f"📂 Output:  {project_dir}\n")

    for file_info in files:
        file_path = os.path.join(project_dir, file_info["path"])
        file_dir = os.path.dirname(file_path)
        if file_dir:
            os.makedirs(file_dir, exist_ok=True)

        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(file_info["content"])
        print(f"  ✅ {file_info['path']}")

    print(f"\n🎉 Done! Generated {len(files)} files.")
    print(f"\n▶️  To play:")
    print(f"   1. Open Godot 4")
    print(f"   2. Import → select {project_dir}/project.godot")
    print(f"   3. Cmd+B to run")


def main():
    if len(sys.argv) < 2:
        print("🎮 AI Game Engine v0.1")
        print("   Powered by Claude Code CLI + Godot 4\n")
        print("Usage: python3 generate.py \"game description\"")
        print("\nExamples:")
        print('  python3 generate.py "做一个2D平台跳跃游戏，有3个平台和可收集的星星"')
        print('  python3 generate.py "a simple pong game with AI opponent"')
        print('  python3 generate.py "贪吃蛇游戏，经典绿色风格"')
        sys.exit(0)

    description = sys.argv[1]
    output_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")

    # Verify claude CLI is available
    try:
        version_check = subprocess.run(
            ["claude", "--version"],
            capture_output=True, text=True, timeout=10
        )
        if version_check.returncode == 0:
            print(f"✅ Claude Code CLI: {version_check.stdout.strip()}")
    except (FileNotFoundError, subprocess.TimeoutExpired):
        print("❌ Claude Code CLI not found.")
        print("   Install: npm install -g @anthropic-ai/claude-code")
        print("   Login:   claude login")
        sys.exit(1)

    generate_game(description, output_dir)


if __name__ == "__main__":
    main()
