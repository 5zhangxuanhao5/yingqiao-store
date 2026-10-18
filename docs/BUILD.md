# 恢复构建

本仓库是独立公开开发预览，没有个人版Git对象历史。所需 SDK 不随源码分发。

## Mac

在具备 Xcode 和 macOS SDK 的 Mac 上运行 `bash mac/build.sh`。它仅在 `mac/build/` 生成 arm64、x86_64 和 universal 本地预览，用 ad-hoc 签名；只运行 `--self-test` 的纯地址策略检查，不打开窗口、监听网络、生成身份、请求权限或安装系统组件。GitHub测试分发必须披露未完成Developer ID签名／公证的现状，并提供校验及Apple官方单应用确认说明；真实系统验证仍不可省略。最低部署目标13.0代表编译目标，不能代表所有这类Mac已通过功能测试。

## HarmonyOS

安装 DevEco Studio API26 SDK。此版本 compatibleAPI24。原版官方 SDK 构建，不应用个人版的本地 easyGo schema 扩展。

先下载本版本 Release 的 `yingqiao-store-native-dependencies.tar.gz` 与 SHA-256，在仓库根解压；`DEPENDENCIES.json` 记录各文件哈希。内容仅 OpenSSL/Opus 的头文件和arm64静态库，不含配对、签名或设备资料。参考许可证见LICENSES。将来应补可复现的源码构建脚本，此依赖包是当前恢复字节的固定输入。

运行 `bash tools/build-harmony.sh`，只编译未签名HAP。签名配置必须由正式开发者自己在AGC与DevEco完成，不复用本机个人版Profile，不把调试权限当发行能力。不运行HDC、不安装到设备。

## 策略验证

`clang++ -std=c++17 -Wall -Wextra -Werror tests/policy_test.cpp -o policy-test`，再运行测试。它不连接设备或网络，仅测试比例选择、硬件回退、线路选择和显示器租约策略。

`node tools/test-pairing.cjs` 用SDK提供的TypeScript编译器在内存中检查纯配对解析函数。设置`ETS_TYPESCRIPT_PATH`可覆盖编译器路径。它不读取剪贴板、真实配对或摄像头，不发网络请求。

`python3 tools/check-source.py` 校验本次源码清单及不携带签名／配对资料的边界。

## 云端兼容检查范围

GitHub Actions 在 macOS 15 的 Apple Silicon、Intel 标准托管环境分别编译两种 Mac 架构，并仅执行无界面的自检。在 Ubuntu 24.04、Windows Server 2022 编译并执行可移植的屏幕选档、通道策略和 USB 协议模拟。Windows 检查不代表已实现 Windows 扩展屏服务；Mac 部署目标13.0不代表已在macOS13运行。托管环境没有华为平板，不能证明真实 USB 重枚举、视频流畅度、触控板兼容或拔插接续。HarmonyOS 的官方SDK编译在本地隔离工程完成，正式签名与真机云测尚待接入。

Linux和Mac还会将真实的 `probe.cpp` 与测试专用NAPI／硬件能力替身一起编译，调用实际模块初始化并从导出表执行 `storeProfile`。这可发现“函数编译了但未导出”的桥接错误；替身不构成真实解码器测试，也不会进入产品构建。

## USB离线研究检查命令

`clang++ -std=c++17 -Wall -Wextra -Werror tests/usb_test.cpp -o usb-test`测试控制请求序列、同意门控、流分片及公平调度；不接触硬件。Mac IOKit适配可使用 `clang++ -target arm64-apple-macos13.0 -std=c++17 -Wno-deprecated-declarations -c mac/USB/AccessoryControl.cpp` 编译，也对x86_64做编译检查；对象文件不被GUI链接，不运行设备枚举或模式切换。
