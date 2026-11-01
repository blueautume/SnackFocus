# 开发预览归档

此目录保留贪吃蛇开发过程中的截图、视频和动画，按阶段理解。

- [snake-stationary-wave.gif](snake-stationary-wave.gif)：经典形态的直行 / U 弯慢放诊断，实际前进、固定中段波形、同速斑纹；00 / 14 / 27 PNG 为对应关键帧。
- [snake-appearance-selection.png](snake-appearance-selection.png)：加入经典 / 现代选择后的历史开局页；该截图早于四档速度功能。当前应用提供禅意、舒缓、适中、激进，默认舒缓。
- [snake-anatomy.mp4](snake-anatomy.mp4)、[snake-motion.mp4](snake-motion.mp4)：早期像素头尾、身体摆动与食物动画录屏。
- `snake-texture-flow.gif`、`snake-texture-phase-*.png`：早期固定轮廓纹理试验，后续演进为当前经典波浪效果。
- 其余 PNG 保存地图选择、游戏中、接近填满、休息提示和重开确认等阶段的界面。

文件来自开发会话的 autonomous-snake 预览目录，复制 SHA-256 见 [WorkspaceOrigin.json](../WorkspaceOrigin.json)。

## 中英界面适配验证（2026-11-01）

- [英文精选](snake-bilingual-en.png)、[中文精选](snake-bilingual-zh-Hans.png)：320 点窄视口滚底后的开局、375 点四列开局、窄视口重开确认和休息卡片、横向视口底部控件及 iPad 宽度开局。
- 这些是 iOS 26.3 模拟器内真实 `ContentView`、实际 Fusion Pixel 字体在临时 UIKit 视口中的渲染。视口尺寸为 320×568、375×667、390×844、667×375、768×1024 点；320 点为合成布局压力检查，横向与 iPad 尺寸也使用合成视口，并非相应物理设备截图。
- 以常规字号核对中英两种语言的开局、运行、暂停、重开确认和铺满休息提示，共 50 个主状态，并补拍超出屏幕的滚动区域。完整估时、按钮和正文均无水平截断；窄屏速度区域自动两列，较宽视口四列。
- 不注入 SwiftUI locale，分别以 `AppleLanguages` / `AppleLocale` 的 en / en_US 与 zh-Hans / zh_CN 启动，也正确显示相应语言。
- [原始检查记录](snake-bilingual-layout-checks.txt)保留视口、安全区、滚动尺寸、字体加载及系统语言选择；本地化资源和实际字宽可用 `Scripts/check-snake-localization.sh` 回归检查。
