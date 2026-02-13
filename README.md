# AI Game Engine

> 让创意成为唯一门槛 —— 用自然语言创造游戏

AI Game Engine 是一个基于 Godot 4 的 AI 原生游戏引擎，目标是让没有游戏开发经验的人，仅凭创意和自然语言就能完成游戏研发。

## 核心愿景（第一性原则）

**消除技术门槛，让创意直接变成可玩的游戏。** 用户不需要懂编程、不需要懂引擎、不需要懂美术，只需要描述自己想要什么，AI 就能生成、修改、迭代出一个完整可运行的游戏。

## 技术架构

```
用户层（自然语言 / 草图 / 语音）
        ↓
   AI 编排层（核心差异化产品）
   ├── 意图理解：用户想做什么
   ├── 任务分解：拆成引擎可执行的操作
   ├── 代码生成：输出 GDScript / 场景文件
   └── 验证反馈：运行 → 截图 → AI 自检 → 修正
        ↓
   Godot 引擎（用户永远不直接接触）
   ├── 渲染 / 物理 / 音频（原封不动）
   ├── 场景树（AI 操作的核心接口）
   └── GDExtension（AI 模块挂载点）
```

## 项目结构

```
ai-game-engine/
├── README.md                  # 本文件
├── MEMORY.md                  # 项目记忆文件（AI 上下文）
├── ROADMAP.md                 # 开发路线图
├── CHANGELOG.md               # 版本变更记录
├── project.godot              # Godot 项目配置
├── addons/
│   └── ai_engine/             # Godot 编辑器插件（第二步）
│       ├── plugin.cfg
│       ├── plugin.gd
│       ├── ai_dock.gd
│       └── ai_dock.tscn
├── tools/
│   └── generate.py            # CLI 生成工具（第一步）
├── scripts/                   # 游戏脚本模板 / 生成产物
├── scenes/                    # 场景模板 / 生成产物
└── docs/
    ├── architecture.md        # 架构设计文档
    └── prompt-engineering.md  # Prompt 工程记录
```

## 快速开始

### 方式一：CLI 生成（已验证 ✅）

```bash
cd tools
python3 generate.py "做一个2D平台跳跃游戏，有3个平台和可收集的星星"
```

### 方式二：编辑器内对话（开发中 🚧）

1. 将 `addons/ai_engine` 复制到 Godot 项目
2. Project → Project Settings → Plugins → 启用 AI Game Engine
3. 底部面板打开 🎮 AI Engine，直接对话

## 依赖

- Godot 4.6+（标准版）
- Claude Code CLI（通过 Max 订阅认证）
- Python 3.10+（仅 CLI 工具需要）

## License

MIT
