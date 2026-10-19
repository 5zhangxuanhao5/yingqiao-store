# 映桥 · 开发者版

让华为平板成为 Mac 的独立扩展屏，支持键盘、触控板和触屏操作。本分支为 **0.3.14 开发者版**，仅在 GitHub 分发，不更新应用市场审核中的版本，也不替换映桥完整版。

[下载本版与源码](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/developer-v0.3.14-test.1) · [版本说明](docs/DEVELOPER_0314.md)

## 使用

Mac 下载 `Yingqiao-Mac-0.3.14.zip`，解压后放入“应用程序”。这是本机开发签名包，尚未经过 Apple 公证；系统提示时请依据 Apple 的单应用打开说明自行确认。

平板开发构建需自己的华为调试证书和设备 Profile。本人设备调试 HAP 不公开上传，以免包含设备签名资料。源码保留完整恢复方法；签名、配对令牌、TLS 私钥和用户数据不入库。

两端打开映桥后自动查找设备。使用数据线时，先在平板启用并授权 USB 调试，Mac 安装 DevEco Studio；本开发版通过 HDC 自动建立专用通道，不需要 USB 共享网络。无线与有线由软件在后台选择。未发现实际可达设备时，平板开启按钮置灰；离线设备不会作为可连接设备展示。

## 构建

Mac：`YQ_ORIGINAL_USB_TEST=1 bash mac/build.sh`。

平板：先准备独立构建工程及自己的调试签名，再显式运行 `tools/prepare-original-tablet-test.py --device-test-only --sdk <原厂SDK目录> --output <新隔离SDK目录> --project <独立工程目录>`，将 `DEVECO_SDK_HOME` 指向这个隔离目录构建。该模式保留经本人设备确认有效的纯平板触控板配置及 HDC 兼容通道，不修改系统安装的 SDK，不作为原厂 SDK 正式上架构建。依赖由 Release 中的 native-dependencies 归档恢复。

## 适配范围

已实测的基础设备为 MatePad Edge 与 MacBook Air。其他型号、系统版本及网络环境需要另行验证。USB 调试通道与普通消费者 USB 网络模式不同，不宣传免开发者设置的即插即用。
