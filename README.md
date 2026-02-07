
# Focursor - OBS Smooth Mouse Zoom Plugin

English | [中文](#中文说明)

An enhanced OBS script plugin inspired by [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse), providing smooth mouse pointer zoom and follow features.

## ✨ Main Features

### 🎯 Core Functions
- **Smart Zoom Follow**: Automatically zooms the display area as the mouse moves
- **Smooth Animation**: Supports various easing algorithms for zoom animations
- **Hardware-accelerated Cursor**: Custom mouse cursor, supports click and drag animations

### 🔧 Advanced Features
- **Auto Zoom**: Configurable auto-zoom logic, supports click and long-press triggers
- **Mode Matching**: Automatically matches zoom target sources by name prefix
- **Scene Adaptation**: Automatically switches to the appropriate zoom source between scenes

### 🎨 Visual Effects
- **Smooth Mouse Follow**: Configurable mouse smoothness and zoom follow
- **Click Feedback**: Zoom animation on mouse click

## 📦 Installation

1. Download the `focursor.lua` file
2. Copy the file to the OBS scripts directory:
   ```
   %APPDATA%\obs-studio\plugins\frontend-tools\scripts\
   ```
3. Enable the script in OBS and configure the parameters

### Optional: Copy Icon Files
If you want to use a custom mouse cursor, you can set it in the plugin options

## 🎮 Usage

1. **Basic Usage**:
   - Set the zoom target source (leave blank to auto-select the first window/display capture)
   - Configure the mouse source name and icon path
   - Click "Enable Smooth Mouse" (if no matching source is found, it will be created automatically)

2. **Hotkey Settings**:
   - Add hotkeys for the script in OBS settings
   - Supports toggling zoom state

3. **Advanced Configuration**:
   - Adjust animation parameters for the best experience
   - Configure multi-monitor support parameters

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

## 中文说明

一个基于 [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) 的增强版 OBS 脚本插件，提供平滑的鼠标指针缩放和跟随功能。

### ✨ 主要特性

#### 🎯 核心功能
- **智能缩放跟随**：鼠标移动时自动缩放显示区域
- **平滑动画**：支持多种缓动算法的缩放动画
- **硬件加速鼠标**：自定义鼠标图标，支持点击和拖拽动画

#### 🔧 高级功能
- **自动缩放**：可配置的自动放大逻辑，支持点击和长按触发
- **模式匹配**：支持按名称前缀自动匹配缩放目标源
- **场景自适应**：在不同场景间自动切换合适的缩放源

#### 🎨 视觉效果
- **平滑鼠标跟随**：可配置的鼠标平滑度和缩放跟随
- **点击反馈**：鼠标点击时的缩放动画

### 📦 安装方法

1. 下载 `focursor.lua` 文件
2. 将文件复制到 OBS 脚本目录：
   ```
   %APPDATA%\obs-studio\plugins\frontend-tools\scripts\
   ```
3. 在 OBS 中启用脚本并配置参数

#### 可选：复制图标文件
如果您想使用自定义鼠标图标，可以在插件的选项中进行设置

### 🎮 使用方法

1. **基本使用**：
   - 设置缩放目标源（留空自动选择第一个窗口/显示器采集）
   - 配置鼠标源名称和图标路径
   - 点击"启用平滑鼠标"（如果找不到匹配源会自动创建）

2. **快捷键设置**：
   - 在 OBS 设置中为脚本添加热键
   - 支持切换缩放状态

3. **高级配置**：
   - 调整动画参数以获得最佳体验
   - 配置多显示器支持参数

### 📄 许可证

本项目采用 Apache License 2.0 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📞 支持

如果您在使用过程中遇到问题，请：
1. 检查 OBS 脚本日志
2. 提交详细的 Issue 描述
3. 提供您的 OBS 版本和系统信息