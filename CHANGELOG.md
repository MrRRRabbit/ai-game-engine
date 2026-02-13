# Changelog

## [0.4.0] - 2025-02-13 (开发中)
### Added
- 游戏类型 Prompt 模板系统: 拆分 SYSTEM_PROMPT 为 BASE_PROMPT + 4 种游戏专用规则
- 支持 4 种游戏类型: Platformer(平台跳跃), Snake(贪吃蛇), Breakout(打砖块), Shooter(射击)
- 游戏类型自动检测: 从用户输入关键词自动识别游戏类型（支持中英文）
- 游戏类型下拉选择器: 编辑器 UI 新增 OptionButton，可手动选择或自动检测
- Sticky 类型记忆: 检测到的游戏类型在会话内持久化，后续修改命令自动继承
- 每种游戏类型包含专用规则: 物理参数、输入映射、节点类型、架构模式

## [0.3.0] - 2025-02-13 ✅
### Added
- 自动修复循环: 生成后自动校验错误并喂回 AI 修复 (最多 3 次)
- GDScript 校验器: 检查 extends、Godot 3/4 语法混用、信号语法
- Scene 校验器: 检查 load_steps 计数、重复节点名、脚本引用
- Godot 日志错误捕获: 读取最近 ERROR 输出
- 修复过程可视化: 聊天面板显示 🔧 修复状态和错误详情
- System Prompt 增强: 新增场景文件格式约束规则
- 未使用变量检测: 静态分析 var/@onready var/@export var 声明，全词匹配检查引用
- 未使用函数检测: 静态分析 func/static func 声明，自动跳过 Godot 内置回调 (17 个)
- Godot 日志 WARNING 捕获: 日志扫描范围从仅 ERROR 扩展至 ERROR + WARNING
- JSON 解析失败自动重试: Claude 返回非 JSON 时自动重试 (最多 2 次)，使用强化 JSON 指令
- Prompt 末尾 JSON 强制指令增强: "Respond with JSON only" → 更明确的 JSON-only 约束

### Fixed
- 修复校验器误报导致自动修复死循环: 未使用变量/函数降级为 warning（不触发修复）
- 信号处理函数误报: `on_`/`_on_` 前缀函数自动识别为信号处理器，不再标记
- 跨文件引用检测: call_group() 字符串引用 + 跨文件标识符搜索
- @export 变量误报: 由编辑器 Inspector 设置的变量不再标记为未使用

## [0.2.0] - 2025-02-13 ✅
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
