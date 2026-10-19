# 映桥 · Yingqiao

**把鸿蒙平板变成 Mac 的独立扩展屏。** 在平板上放文档、浏览器或聊天窗口，用平板的键盘、触控板和触屏继续操作 Mac。

[下载 Mac 开发版](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/Yingqiao-Mac-0.3.15.zip) · [详细安装教程](docs/INSTALL.md) · [全部下载文件](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/developer-v0.3.15-test.1) · [反馈问题](https://github.com/5zhangxuanhao5/yingqiao-store/issues)

> **当前是开发者预览。** Mac 为 **0.3.15 (36)**，平板为 **0.3.14 (35)**，两端版本号不同是正常的。本轮只精简了 Mac 首页。平板暂不提供通用安装包，需要自己的华为调试签名及 DevEco Studio 构建安装；不是下载 HAP 后点开即装。下方教程写出了完整步骤与限制。

## 可以做什么

- **独立扩展桌面**：窗口能在 Mac 与平板之间移动，平板显示自己的桌面内容。
- **键盘、触控板和触屏控制**：支持键盘输入、指针移动、按压拖窗、双指滚动和触屏点击/滑动/长按拖动。
- **无线与有线自动接续**：后台选择可用线路；拔线时在无线仍可达的条件下接续，保留扩展桌面。切换可能短暂停顿，不承诺所有网络零中断。
- **从任意一端开始**：两端打开后自动发现设备；一台直接连接，多台选择目标。首次连接由 Mac 确认，不需要手填 IP 或匹配码。
- **全屏与及时结束**：平板全屏显示，侧滑打开菜单；结束后释放扩展屏并停止本次画面采集、编码和传输，保留设备发现。

这个公开分支只介绍本地扩展屏，不包含异地远控，也不是个人使用的“映桥完整版”。

## 先下载哪个文件

| 目标 | 文件或入口 | 说明 |
| --- | --- | --- |
| 在 Mac 上安装 | [Yingqiao-Mac-0.3.15.zip](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/Yingqiao-Mac-0.3.15.zip) | 解压后是“映桥.app”；Intel/Apple Silicon 通用开发包，未做 Apple 公证 |
| 在平板上安装 | [平板构建与签名教程](docs/INSTALL.md#三平板端用自己的签名安装) | 当前没有面向所有设备的已签名 HAP 下载，不分发作者的设备 Profile |
| 下载本版源码 | [yingqiao-store-source.tar.gz](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/yingqiao-store-source.tar.gz) | Mac 0.3.15 + Pad 0.3.14；不是 Mac 安装包 |
| 恢复编译依赖 | [yingqiao-store-native-dependencies.tar.gz](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/yingqiao-store-native-dependencies.tar.gz) | 编译平板或 Mac 时使用，解压到源码根目录 |
| 校验附件 | [SHA256SUMS](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/SHA256SUMS) | 安装包/源码/依赖校验；逐文件源码哈希在 SOURCE_MANIFEST.json |

## 两种连接方式

**无线**：Mac 和平板加入能互相访问的局域网或同一手机热点，两端打开映桥即可查找。校园/公司网络可能隔离设备或拦截组播；连接同一个 Wi-Fi 名称不一定能互通，遇到找不到设备时可用同一手机热点对照。

**有线开发通道**：使用支持数据传输的 USB 线，平板开启并授权 USB 调试，Mac 安装官方 DevEco Studio。此版通过已有 HDC 调试通道连接，**不需要 USB 共享网络**；它依然需要开发者模式，不是免设置的消费者 USB 即插即用。无线同时可达时，保留线路自动选择与接续。

## 安装和使用

请按 [完整安装教程](docs/INSTALL.md) 操作，顺序是：**准备两端 → 安装 Mac → 用本人签名安装平板 → 授权 → 首次连接 → 测试拔插接续**。不要只装 Mac 就等待另一端自动出现。

触屏：轻点是点击；单指滑动滚动页面；停住长按后再移动，可拖窗或拖选文字。触控板保持普通鼠标逻辑：单指移动、按住拖动、双指滚动。平板侧滑可退出全屏或结束会话。

## 已验证范围

当前设备验证来自 **MacBook Air + MatePad Edge（HarmonyOS 7）**。开发配置下跨屏按压拖动和有线传屏已由真实设备确认；其他型号、系统版本和网络仍需验证。源码的 Mac 最低构建目标是 macOS 13、平板 compatible API 24 / target API 26，不能据此声称这些系统全部已验收。当前没有可用的 Windows 扩展屏客户端。

原厂 SDK 不接受本开发包用于关闭鼠标转触摸的特定配置。实验构建工具在**新建的独立 SDK 副本目录**准备配置，不修改 DevEco 安装目录；不据此宣称通过官方商店工具链验证。详见 [开发配置边界](docs/TRACKPAD_TEST_021.md)。

## 开发与隐私

[构建说明](docs/BUILD.md) · [本版说明](docs/DEVELOPER_0315.md) · [历史版本](https://github.com/5zhangxuanhao5/yingqiao-store/releases)

公开归档包含源码、固定依赖和版本校验资料，不包含真实配对令牌、TLS 私钥、签名密码、设备 Profile、录音或用户运行资料。请勿在 Issue 中上传这些内容。项目使用 AI 辅助开发；功能结果以各版本设备验证记录为准。
