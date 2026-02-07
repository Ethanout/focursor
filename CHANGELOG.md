# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-02-XX

### Added
- **平滑鼠标跟随功能**：硬件加速的自定义鼠标图标，支持点击和拖拽动画
- **自动缩放逻辑**：可配置的自动放大，支持点击和长按触发策略
- **模式匹配源选择**：支持按名称前缀自动匹配缩放目标源
- **场景自适应**：在不同场景间自动切换合适的缩放源
- **多显示器支持**：完整的多显示器坐标和DPI缩放支持
- **高级动画系统**：多种缓动算法和可调节的动画参数
- **智能边界处理**：防止缩放时显示超出边界
- **自动鼠标源创建**：启用平滑鼠标时自动检测和创建鼠标源，无需手动操作

### Changed
- **重构缩放实现**：从 crop_filter 改为 sceneitem crop + scale，避免源尺寸变化
- **改进坐标系统**：使用双精度内部计算，消除浮点精度抖动
- **优化UI界面**：更清洁的设置界面，移除冗余按钮，合并功能到主开关
- **简化用户流程**：启用鼠标功能时自动创建源，一键完成设置

### Technical Improvements
- **Windows API 集成**：直接获取鼠标位置和状态
- **内存管理优化**：更好的资源管理和清理
- **错误处理增强**：更详细的日志和错误提示
- **性能优化**：减少不必要的计算和API调用

### Fixed
- **边缘像素抖动**：通过分离显示值和实际值解决
- **鼠标位置偏移**：添加DPI缩放和坐标系统修正
- **源尺寸变化问题**：改用sceneitem crop + scale方法

### Removed
- **旧的crop_filter实现**：替换为更稳定的sceneitem方法

---

## Development Notes

This version is based on the original [obs-zoom-to-mouse](https://github.com/Ethanout/obs-zoom-to-mouse) script by Ethanout, with extensive refactoring and feature additions focused on content creation workflows.

### Key Features Added:
1. Smooth cursor with hardware acceleration
2. Advanced auto-zoom with configurable timeouts and thresholds
3. Multiple center-point tracking strategies
4. Extended parameter ranges and cleaner UI
5. Pattern matching for source selection
6. Automatic source selection when name is empty
7. Multi-monitor DPI scaling support
8. Enhanced animation system with multiple easing types

### Compatibility:
- **OBS Studio**: 28.0.0+
- **Platform**: Windows (primary), may work on other platforms with modifications
- **Language**: Chinese UI (primary), with English comments