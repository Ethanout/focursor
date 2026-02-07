# Focursor — OBS Smooth Mouse Zoom Plugin

English | [中文](#中文说明)

An enhanced OBS script plugin inspired by [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse), providing smooth mouse pointer zoom and follow features.

**Note: This plugin only supports the Windows platform.**

## Quick overview

- Platform: Windows only
- Status: Testing / experimental
- License: Apache-2.0 (code)

## Note & Warning
This script is in the testing phase and may make destructive changes to sources in your scenes, and may cause unexpected behavior. Please back up your OBS scene collection before use.

## ⚠️ Known Issues

- **Please be sure to disable Auto Zoom before exiting OBS.** Exiting OBS while the plugin is in a zoom-in state may break the plugin and damage your scenes. If this happens, uninstall the script, remove plugin-added sources and any plugin-modified sources (e.g. the zoomed window), then reinstall.

## ✨ Main Features

### 🎯 Core Functions
- Smart Zoom Follow — automatically zooms the display area as the mouse moves
- Smooth Animation — supports multiple easing algorithms for zoom
- Custom Cursor — supports cursor images and click/drag visual feedback

### 🔧 Advanced
- Auto Zoom — configurable auto-zoom logic (click or long-press triggers)
- Mode Matching — match zoom targets by name prefix
- Scene Adaptation — switch zoom source between scenes automatically

## 📦 Installation

1. Download `focursor.lua` from this repository
2. Copy `focursor.lua` to your OBS scripts directory (optional):
   ```
   %APPDATA%\obs-studio\plugins\frontend-tools\scripts\
   ```
3. In OBS add the script: Tools -> Scripts -> click "+" and select `focursor.lua`
4. Configure the script parameters inside OBS

### Optional: copy icon files
If you want to use the bundled icons, copy the files from the `icons/` folder into a reachable location and set the path in the script options.

## 🎮 Usage

1. Install the OBS Script Plugin
   - In OBS: Tools -> Scripts -> "+" → add `focursor.lua`

2. Basic Usage
   - Set the zoom target source (leave blank to auto-select the first window/display capture)
   - Configure the mouse source name and icon path
   - Click "Enable Smooth Mouse" (if no matching source is found, it will be created automatically)

3. Hotkey Settings
   - Add hotkeys for the script in OBS Settings → Hotkeys
   - Use hotkeys to toggle zoom state or trigger actions

4. Advanced Configuration
   - Adjust animation/easing parameters for smoother results
   - Configure multi-monitor settings and source matching rules

## 📄 License

This project is licensed under the Apache License 2.0 — see the [LICENSE](LICENSE) file for details.
The included cursor icon (`icons/cursor.png`) is licensed under CC BY 4.0. Source: https://icon-icons.com/icon/cursor-the-application/2337

## 🤝 Contributing

Contributions are welcome. Please open Issues or Pull Requests with details and repro steps.

## 📞 Support

If you encounter problems:
1. Check the OBS script log for errors
2. Open an Issue with details (OBS version, OS, steps to reproduce)
3. Attach logs and a minimal repro if possible

---

## 中文说明

一个基于 [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) 的增强版 OBS 脚本插件，提供平滑的鼠标指针缩放和跟随功能。

**注意：本插件仅支持 Windows 平台。**

## 概要

- 平台：仅支持 Windows
- 状态：测试 / 实验性
- 代码许可：Apache-2.0

## 注意与警告

本脚本处于测试阶段，可能会对场景中的源造成破坏性更改，并导致不可预期的行为。使用前请备份 OBS 场景集合。

### ⚠️ 已知问题

- **请在务必退出obs前关闭自动放大。**因为在放大（zoom-in）状态下退出 OBS 可能导致插件和场景损坏。若发生此问题，请卸载脚本，删除插件添加的源及插件修改的源（例如被放大的窗口），然后重新安装。

### ✨ 主要特性

#### 🎯 核心功能
- 智能缩放跟随 — 鼠标移动时自动缩放显示区域
- 平滑动画 — 支持多种缓动算法
- 自定义光标 — 支持自定义光标图片及点击/拖拽反馈

#### 🔧 高级功能
- 自动缩放 — 可配置的自动放大逻辑（点击或长按触发）
- 模式匹配 — 按名称前缀匹配缩放目标
- 场景自适应 — 在场景间自动切换缩放源

### 📦 安装方法

1. 下载 `focursor.lua` 文件
2. 可将 `focursor.lua` 放入 OBS 脚本目录（可选）：
   ```
   %APPDATA%\obs-studio\plugins\frontend-tools\scripts\
   ```
3. 在 OBS 中添加脚本：工具 -> 脚本 -> 点击 "+"，选择 `focursor.lua`
4. 在脚本界面中配置参数

#### 可选：复制图标文件
如果需要使用自带图标，请将 `icons/` 中的文件复制到可访问位置，并在脚本选项中设置路径。

### 🎮 使用方法

1. 安装 OBS 脚本插件
   - 在 OBS 中：工具 -> 脚本 -> "+" → 添加 `focursor.lua`

2. 基本使用
   - 设置缩放目标源（留空自动选择第一个窗口/显示器采集）
   - 配置鼠标源名称和图标路径
   - 点击“启用平滑鼠标”（若未找到匹配源会自动创建）

3. 快捷键设置
   - 在 OBS 设置 → 快捷键 中为脚本添加热键
   - 使用热键切换缩放或触发操作

4. 高级配置
   - 调整动画/缓动参数以获得更平滑的体验
   - 配置多显示器和源匹配规则

### 📄 许可证

本项目代码采用 Apache License 2.0，详见 [LICENSE](LICENSE)
项目中包含的光标图标（`icons/cursor.png`）采用 CC BY 4.0 协议，出处： https://icon-icons.com/icon/cursor-the-application/2337

## 🤝 贡献

欢迎贡献：请提交 Issue 或 Pull Request，并附带复现步骤。

## 📞 支持

如遇问题：
1. 查看 OBS 脚本日志中的错误信息
2. 提交 Issue，说明 OBS 版本、系统信息和复现步骤
3. 尽量附上日志和最小复现示例