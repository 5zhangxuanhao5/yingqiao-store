# 映桥 · Yingqiao

**把鸿蒙平板或另一台 Mac 变成独立扩展屏。** 在平板上放文档、浏览器或聊天窗口，用平板的键盘、触控板和触屏继续操作 Mac。

[鸿蒙应用商城下载](https://appgallery.huawei.com/app/detail?id=cn.edgelink.store) · [Mac 合并预览版下载](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/mac-unified-v0.4.0-test.6/Yingqiao-Mac-Unified-0.4.0-test.6.zip) · [安装教程](docs/INSTALL.md) · [版本选择与下载](docs/downloads.md) · [反馈问题](https://github.com/5zhangxuanhao5/yingqiao-store/issues)

> **映桥已上架鸿蒙应用商城。** 2026-10-21 核对：商店公开页面为 **0.3.11**。商店版不需要开启开发者模式；GitHub 平板开发版需要开发者模式、USB 调试和本人的调试签名，两者安装方式与输入兼容配置不同。
>
> **Mac 互联现为合并预览版 0.4.0-test.6（build 45）**：一个应用提供“平板扩展屏”和“Mac 互联”。已在 MacBook Pro（M5 Pro）→ MacBook Air（M4）实测。默认分支保留 Mac 0.3.15 + Pad 0.3.14 开发基线；合并版源码请下载对应 Release，不能把默认分支当作 0.4.0 源码。

## 一个实际使用例子：一台 Pro，三块扩展屏

以 **MacBook Pro 为主机，保留 Pro 内屏作为主显示器**，可以把文档、浏览器和聊天窗口分开放到其他设备：

| 设备 | 连接方式与用途 |
| --- | --- |
| MatePad Edge | 通过映桥成为独立扩展屏，还能用平板的键盘、触控板和触屏操作 Mac |
| MacBook Air | 通过映桥的“Mac 互联”作为另一块全屏扩展屏 |
| iPad Pro | 继续使用 Apple 随航，再增加一块扩展屏 |

这样就是 **Pro 内屏 + Edge + Air + iPad Pro，共四块屏幕**，窗口可以按工作需要分别摆放。Edge 和 Air 使用映桥，iPad Pro 使用系统随航；设备不是在重复显示同一幅画面。实际可用数量与流畅度仍取决于主机、系统版本和网络条件，不能由这个例子推定所有型号都已通过四屏长时间验收。

## 先选适合自己的版本

| 版本 | 如何安装 | 开发者模式与 USB |
| --- | --- | --- |
| 鸿蒙应用商城版 0.3.11 | 在兼容鸿蒙平板上点击上方商店链接；或在应用市场搜索“映桥” | 安装和局域网使用不需要开发者模式。普通有线通道需要系统提供 USB 网络，当前须手动开启“USB 共享网络”，不是只插线即用 |
| GitHub 平板开发版 0.3.14 | 按教程用本人华为账号和设备签名构建安装 | **需要开启并保留开发者模式**；安装及 HDC 有线连接还需 USB 调试和电脑授权。HDC 通道不需要 USB 共享网络 |
| Mac 合并预览版 0.4.0-test.6 | 两台 Mac 分别安装同一 ZIP，选择发送或接收；也保留平板扩展入口 | Mac 不需要鸿蒙开发者模式。Mac→Mac 已实测局域网；普通 USB-C 充电/数据线不能视为已建立网络 |

商店链接是正式详情页，不是邀请码。鸿蒙设备能否直接唤起应用市场取决于浏览器与系统设置；若只显示网页预览，请从应用市场搜索安装。平板运行系统、设备类型和可下载范围以商店实际显示为准。

商店版和开发者版不是同一个签名包，不能保证保留数据相互覆盖；切换渠道可能需要卸载并重新允许连接。开发版实测的触控板跨屏按压拖动，不等于商店版也已通过该项验证。两版均不包含异地远控，也不是“映桥完整版”。

## 可以做什么

- **独立扩展桌面**：窗口能在 Mac 与平板之间移动，平板显示自己的桌面内容。
- **键盘、触控板和触屏控制**：支持键盘输入、指针移动、按压拖窗、双指滚动和触屏点击/滑动/长按拖动。
- **无线与有线自动接续**：后台选择可用线路；拔线时在无线仍可达的条件下接续，保留扩展桌面。切换可能短暂停顿，不承诺所有网络零中断。
- **从任意一端开始**：两端打开后自动发现设备；一台直接连接，多台选择目标。首次连接由 Mac 确认，不需要手填 IP 或匹配码。
- **全屏与及时结束**：平板全屏显示，侧滑打开菜单；结束后释放扩展屏并停止本次画面采集、编码和传输，保留设备发现。

这个公开分支只介绍本地扩展屏，不包含异地远控，也不是个人使用的“映桥完整版”。

## GitHub 开发基线下载（需要自行签名的平板版）

| 目标 | 文件或入口 | 说明 |
| --- | --- | --- |
| 在 Mac 上安装 | [Yingqiao-Mac-0.3.15.zip](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/Yingqiao-Mac-0.3.15.zip) | 解压后是“映桥.app”；Intel/Apple Silicon 通用开发包，未做 Apple 公证 |
| 在平板上安装开发版 | [平板构建与签名教程](docs/INSTALL.md#三平板端用自己的签名安装) | 当前没有面向所有设备的已签名 HAP 下载，不分发作者的设备 Profile |
| 下载本版源码 | [yingqiao-store-source.tar.gz](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/yingqiao-store-source.tar.gz) | Mac 0.3.15 + Pad 0.3.14；不是 Mac 安装包 |
| 恢复编译依赖 | [yingqiao-store-native-dependencies.tar.gz](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/yingqiao-store-native-dependencies.tar.gz) | 编译平板或 Mac 时使用，解压到源码根目录 |
| 校验附件 | [SHA256SUMS](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/SHA256SUMS) | 安装包/源码/依赖校验；逐文件源码哈希在 SOURCE_MANIFEST.json |

## GitHub 平板开发版的连接方式

**无线**：Mac 和平板加入能互相访问的局域网或同一手机热点，两端打开映桥即可查找。校园/公司网络可能隔离设备或拦截组播；连接同一个 Wi-Fi 名称不一定能互通，遇到找不到设备时可用同一手机热点对照。

**有线开发通道**：使用支持数据传输的 USB 线，平板开启并授权 USB 调试，Mac 安装官方 DevEco Studio。此版通过已有 HDC 调试通道连接，**不需要 USB 共享网络**；它依然需要开发者模式，不是免设置的消费者 USB 即插即用。无线同时可达时，保留线路自动选择与接续。

## 安装和使用

请按 [完整安装教程](docs/INSTALL.md) 操作，顺序是：**准备两端 → 安装 Mac → 用本人签名安装平板 → 授权 → 首次连接 → 测试拔插接续**。不要只装 Mac 就等待另一端自动出现。

触屏：轻点是点击；单指滑动滚动页面；停住长按后再移动，可拖窗或拖选文字。触控板保持普通鼠标逻辑：单指移动、按住拖动、双指滚动。平板侧滑可退出全屏或结束会话。

## 已验证范围

已尝试的设备包括 **MacBook Pro 16 英寸（M5 Pro）、MacBook Air 13.6 英寸（M4）和 MatePad Edge（HarmonyOS 7）**。

| 实测组合 | 已确认的范围 |
| --- | --- |
| MacBook Air → MatePad Edge | 开发版独立桌面、键盘/触控板/触屏、有线传屏及可达无线下的接续 |
| MacBook Pro → MatePad Edge | 开发配置下扩展屏、触控板按压跨屏拖动；有线与无线发现/接续分轮测试 |
| MacBook Pro → MacBook Air | 合并预览版 test.6：2560×1664 全屏独立桌面；iPad 随航断开及接回后，Air 保持显示，用户确认两个桌面独立 |

这是上述设备和相应版本的实测记录，不是所有 Mac/鸿蒙平板、所有组合长时间同时运行的认证。其他型号、系统版本和网络仍需验证。源码的 Mac 最低构建目标是 macOS 13、平板 compatible API 24 / target API 26，不能据此声称这些系统全部已验收。当前没有可用的 Windows 扩展屏客户端。

原厂 SDK 不接受本开发包用于关闭鼠标转触摸的特定配置。实验构建工具在**新建的独立 SDK 副本目录**准备配置，不修改 DevEco 安装目录；不据此宣称通过官方商店工具链验证。详见 [开发配置边界](docs/TRACKPAD_TEST_021.md)。

## 开发与隐私

[构建说明](docs/BUILD.md) · [本版说明](docs/DEVELOPER_0315.md) · [历史版本](https://github.com/5zhangxuanhao5/yingqiao-store/releases)

公开归档包含源码、固定依赖和版本校验资料，不包含真实配对令牌、TLS 私钥、签名密码、设备 Profile、录音或用户运行资料。请勿在 Issue 中上传这些内容。项目使用 AI 辅助开发；功能结果以各版本设备验证记录为准。
