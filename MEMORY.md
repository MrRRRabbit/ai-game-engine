# AI Game Engine — 项目记忆文件

> ⚠️ 此文件是 AI 协作的核心上下文。每次与 AI 开始新对话时，请提供此文件。
> 每次重要决策或里程碑完成后，请更新此文件。

---

## 项目基本信息

- **项目名称**: AI Game Engine
- **启动日期**: 2025-02-13
- **创始人**: Steve
- **AI 协作者**: Claude (Anthropic)
- **第一性原则**: 让没有游戏开发经验的人，有创意就能通过引擎实现游戏研发
- **技术路线**: Godot 4 (开源引擎基座) + Claude AI (生成层)

---

## 关键技术决策记录

### 决策 1: 选择 Godot 作为引擎基座
- **日期**: 2025-02-13
- **原因**:
  - MIT 协议，完全自由，可深度魔改和商业化
  - 场景树结构与自然语言高度同构，AI 友好
  - GDScript 类似 Python，LLM 生成质量高
  - 代码量 ~150 万行，可控，便于后期改造
  - GDExtension 机制提供完美的 AI 插入点
- **对比淘汰**: Bevy (生态太早期), O3DE (太复杂), Unreal (协议限制)

### 决策 2: AI 后端使用 Claude Code CLI
- **日期**: 2025-02-13
- **原因**:
  - Steve 是 Claude Max 订阅用户，无需额外 API 费用
  - Claude Code CLI 的 `--print` 模式可直接做文本生成后端
  - OAuth token 不能直接用于 Python SDK，CLI 是最佳变通方案
- **调用方式**: `claude --print --output-format text`，通过 stdin 传入 prompt

### 决策 3: 三步走开发路径
- **日期**: 2025-02-13
- **路径**:
  - 第一步: Python CLI 外部工具（Godot 外生成项目文件）
  - 第二步: Godot 编辑器插件（编辑器内对话式迭代）
  - 第三步: GDExtension 运行时 AI 模块（游戏内智能行为）
- **核心思想**: 先不动引擎核心，通过插件/外部工具验证 AI 能力，验证后再深入

---

## 开发进度

### ✅ 第一步: CLI 生成工具 (v0.1) — 已完成
- **完成日期**: 2025-02-13
- **验证结果**: 完全符合预期
- **文件**: `tools/generate.py`
- **能力**: 自然语言 → 完整 Godot 4 项目（.tscn + .gd + project.godot）
- **已验证的游戏类型**: 2D 平台跳跃（移动、跳跃、收集星星、胜利判定）
- **已修复的问题**:
  - 跳跃高度不足：JUMP_VELOCITY 从 -450 调整为 -650
  - 星星收集信号未连接：改用 call_group() 替代信号连接

### ✅ 第二步: 编辑器插件 (v0.2) — 已完成
- **完成日期**: 2025-02-13
- **文件**: `addons/ai_engine/`
- **能力**: 编辑器底部对话面板，读取项目上下文，增量修改文件
- **验证结果**: 完全符合预期
- **已验证的迭代操作**:
  - 加入巡逻敌人 + 碰撞死亡 ✅
  - 多轮连续迭代修改（3次）均基本符合预期 ✅
- **发现的问题**: 生成代码有不影响主功能的小错误，需要自动修复机制

### ✅ 第二步追加: 自动修复循环 (v0.3) — 已完成
- **开始日期**: 2025-02-13
- **能力**: 生成后自动校验 → 捕获错误 → 喂回 AI 修复 → 最多重试 3 次
- **核心架构决策: error vs warning 分级**:
  - **error（触发修复循环）**: 语法错误、Godot 3/4 混用、场景结构问题、Godot 日志 ERROR/WARNING
  - **warning（仅展示为 ℹ️ 提示，不触发修复）**: 未使用变量、未使用函数
  - **原因**: 未使用检测存在不可消除的误报（call_group 跨文件调用、信号处理函数），喂给 AI 修复会导致死循环
- **校验项（error 级别）**:
  - GDScript: extends 声明、Godot 3/4 语法混用、信号连接语法
  - Scene: load_steps 计数、重复节点名、脚本引用缺失
  - Godot 日志: 捕获最近 ERROR + WARNING 级别输出
- **校验项（warning 级别）**:
  - GDScript: 未使用变量检测（跳过 @export 变量）
  - GDScript: 未使用函数检测（跳过 17 个内置回调 + `on_`/`_on_` 信号处理函数）
  - 跨文件搜索: 遍历所有生成文件查找直接引用 + `call_group()` 字符串引用
- **辅助工具函数**: `_extract_var_name()`, `_extract_func_name()`, `_contains_identifier()`, `_is_identifier_char()`, `_content_has_string_ref()`
- **已修复的 bug**: 误报导致自动修复死循环（音效生成场景，9 个假错误无限重试）
- **JSON 重试机制**: Claude 返回非 JSON 响应时自动重试最多 2 次，使用 `JSON_RETRY_PROMPT` 强化 JSON 指令
- **状态**: ✅ Steve 验证通过，功能落地和错误自修复体验符合预期

### 📋 第三步: GDExtension 运行时模块 — 未开始

---

## 已验证的 Demo

### Demo 1: 2D 平台跳跃
- **描述**: 蓝色角色左右移动跳跃，3 个棕色平台，3 颗黄色星星，吃完显示胜利
- **操作**: A/D 移动，空格跳跃
- **结果**: ✅ 完全可玩
- **生成方式**: CLI 自动生成 + Godot 打开即玩

---

## Prompt 工程经验

### System Prompt 关键要素
1. 输出格式必须严格定义为 JSON，包含 files 数组
2. 每个 file 需要 path 和 content 两个字段
3. 必须明确指定 Godot 4.x 语法（CharacterBody2D, @onready 等）
4. 必须要求包含 project.godot、input mapping、collision shapes
5. 物理参数需要给出参考范围（gravity ~980, jump ~-650）
6. 明确禁止使用外部资产，只用 ColorRect/Polygon2D

### 常见生成问题及修复
| 问题 | 原因 | 修复 |
|------|------|------|
| 跳跃太低 | JUMP_VELOCITY 绝对值太小 | 在 prompt 中指定 -600 到 -700 范围 |
| 信号未连接 | _ready 中信号连接时序问题 | 改用 call_group 替代直接信号连接 |
| JSON 解析失败 | 模型输出包含 markdown 代码围栏 | 添加 JSON 提取逻辑，去除 ``` 包裹 |
| 自动修复死循环 | 未使用变量/函数误报触发修复，Claude 无法消除误报 | 将 unused 检测降级为 warning，不触发修复循环 |
| Claude 返回纯文本而非 JSON | prompt 过长时 "Respond with JSON only" 指令被淹没 | 1) 强化 prompt 末尾 JSON 指令 2) 自动重试机制（最多 2 次）用 JSON_RETRY_PROMPT 重新请求 |

---

## 技术栈版本

| 组件 | 版本 | 备注 |
|------|------|------|
| Godot | 4.6 | 标准版（非 .NET） |
| Python | 3.x | 仅 CLI 工具 |
| Claude Code CLI | latest | Max 订阅认证 |
| OS | macOS | Steve 的开发环境 |

---

## 下一步计划

> Phase 1 ✅ → Phase 2 ✅ → v0.3 ✅ → **Phase 3 剩余工作 ←（当前）**

1. 支持更多游戏类型：贪吃蛇、打砖块、弹幕射击、RPG 等，验证泛化能力
2. Prompt 分类优化：按游戏类型使用专门的 prompt 模板，提升一次成功率
3. 自动运行测试：headless 模式运行生成的游戏，截图对比验证
4. 支持中英文混合输入优化

---

## 对 AI 协作者的说明

当你（Claude）在新对话中收到此文件时：
1. 阅读全部内容，理解项目当前状态
2. 注意已完成的决策，不要重新讨论已决定的事项
3. 关注"下一步计划"，优先推进这些任务
4. 任何重要变更完成后，提醒 Steve 更新此文件
5. 如果需要的上下文不在此文件中，主动询问

---

*最后更新: 2026-02-13*
