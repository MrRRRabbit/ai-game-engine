# Changelog

## [0.2.0] - 2025-02-13 (开发中)
### Added
- Godot 编辑器插件 (`addons/ai_engine/`)
- 编辑器底部对话面板 (AI Engine Dock)
- 项目上下文读取: 自动扫描当前项目文件传给 AI
- 增量修改能力: AI 只修改需要变更的文件
- 多轮对话支持: 保持对话历史

## [0.1.0] - 2025-02-13
### Added
- CLI 生成工具 (`tools/generate.py`)
- 自然语言输入 → 完整 Godot 4 项目输出
- Claude Code CLI 集成 (Max 订阅, 无需 API key)
- JSON 提取和解析逻辑 (处理 markdown 包裹)
- 支持中英文游戏描述

### Verified
- 2D 平台跳跃游戏: 移动、跳跃、收集、胜利判定 ✅

### Fixed
- 跳跃高度不足 (JUMP_VELOCITY -450 → -650)
- 星星收集信号未触发 (signal → call_group)
