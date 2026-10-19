> 当前分支：**0.3.12 开发者版，仅 GitHub 分发**。基于已验收触控板配置的 0.3.2，设备发现与首页调整见 [本版说明](docs/DEVELOPER_0312.md)。不影响应用市场审核版本或映桥完整版。

# 映桥

把华为平板变成 Mac 的另一块屏幕，支持键盘、触控板和触摸操作。

## 下载与安装

### [下载 Mac 0.3.2 测试版（ZIP）↓](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/store-v0.3.2-test.1/Yingqiao-Mac-0.3.2.zip)

[查看版本说明与所有附件](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/store-v0.3.2-test.1)

**普通用户只需下载 `Yingqiao-Mac-0.3.2.zip`。** 下载后双击解压，把“映桥”拖进 Mac 的“应用程序”。源码和依赖是开发资料，不是安装包。

- 第一次安装：阅读 [Mac 逐步安装说明](docs/MAC_INSTALL.md)。
- 不知道该下载哪个文件：阅读 [下载文件对照](docs/downloads.md)。
- GitHub 自动生成的 **Source code (zip / tar.gz)** 是源码，不能直接安装。原生依赖附件也不是 Mac 应用。

测试包包含 Intel 与 Apple Silicon 通用应用，最低构建目标为 macOS 13；这不代表所有系统、Mac 和平板型号均已验证。当前应用尚未完成正式 Developer ID 签名、公证和 AppGallery 审核。若 macOS 阻止打开，请保留提示并反馈，不关闭系统安全保护或运行绕过检查的命令。Windows 安装包尚未提供。

## 开始使用

1. 在 Mac 安装并打开“映桥”，在平板打开同名应用，先让两台设备连接同一局域网。
2. 首次使用先阅读权限用途说明，再由 macOS 请求录屏和辅助功能授权；设备发现不需要先取得这两项权限。
3. 在平板的“附近的 Mac”选择电脑，或者在 Mac 的“附近的 Pad”选择平板。首次连接需要在 Mac 上点“允许连接”，不用扫码、填 IP 或输入匹配码。
4. 点击“开启扩展屏”。没有可连接设备时按钮不可用；发现多台时选择这次使用的设备。
5. 点击“结束会话”后停止采集、编码和传屏，保留设备发现。

当前版本独立于个人版安装，保留原版界面、画面和输入核心，提供局域网扩展屏，不提供异地远控。0.3.0 的首次使用与附近设备调整见 [版本说明](docs/FIRST_RUN_NEARBY_030.md)；0.3.2 更名与发布准备状态见 [版本说明](docs/NAME_RELEASE_032.md)。

## 已实现与待验证

- 独立应用标识与本机配置目录，保留已安装的个人版。
- 自动发现与显式首次连接确认；保存连接信息，之后无需手动填写。
- 按实际屏幕比例和硬件解码能力选择尺寸、编码与帧率。
- 精确校验连接证书、使用每会话视频密钥，限制为本地扩展屏用途。
- 后台比较可用线路，异常断开保留显示器以尝试接续；显式结束时释放。

**消费级 USB 即插即用、真正无缝的有线／无线切换、真实多机型矩阵、正式签名／公证及上架审核仍是交付门槛。** 目前开发用 USB 对照通道依赖单独的测试环境，不能当作普通用户只插线即可使用的承诺。普通 USB 研究源码保留，但不以编译或策略测试代替实机验收。

- [本次真机测试范围](docs/DEVICE_TEST.md)
- [原版核心移植范围](docs/ORIGINAL_EXTENSION_PORT.md)
- [屏幕规格与待测矩阵](docs/compatibility-catalog.json)
- [USB 与接续发布门槛](docs/USB_AND_HANDOVER.md)
- [上架准备与未完成项](docs/APPGALLERY_READINESS.md)
- [隐私说明与联系方式](docs/PRIVACY.md)
- [Windows 开发状态](windows/README.md)
- [源码恢复与构建](docs/BUILD.md)

当前独立项目从个人版 v2026.10.16-mac227-edge227 的干净源码发展而来，仅记录来源哈希；个人版仍在原私有仓库保留完整历史。本公开仓库不导入其 Git 对象历史、个人配对资料或任何签名身份。
