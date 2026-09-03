# 网吧经营模拟

2005 年怀旧网吧独立游戏，Godot 4.7（GDScript）。仓库：[knightmiao/internet-cafe-godot](https://github.com/knightmiao/internet-cafe-godot)

用 Godot 打开 **`godot/project.godot`**，不要打开仓库根目录。

```
internet-cafe-godot/
├── README.md                 本说明
├── docs/                     策划与设计（不进引擎）
│   ├── 游戏策划文档.md
│   ├── 网吧-模拟经营游戏制作-会议记录.txt
│   └── ui/
│       ├── 界面布局设计.md    当前布局规范（像素风两栏）
│       ├── 布局草图-像素风.html
│       └── sketches/         早期草图
└── godot/                    Godot 工程根目录
    ├── project.godot
    ├── scenes/               场景
    ├── scripts/              游戏逻辑
    ├── assets/               游戏内素材
    │   ├── backgrounds/      大厅背景
    │   ├── characters/       老板等角色图
    │   └── ui/topbar/        顶栏图标与木纹底
    └── tools/                截图等开发脚本
```

`.import` 是引擎为贴图生成的导入配置，与对应 png 放在一起，不要手改。`.godot/` 缓存不入库。
