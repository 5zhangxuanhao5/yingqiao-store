# 原版扩展屏基线移植

用户于2026-10-18要求“把原版去掉远控搬过来”。本候选恢复原版持续认证的本地连接和USB/局域网接续流程，已有画面核心并不另写。Mac与Pad界面保留原风格；独立测试名、bundle、配置、端口与虚拟屏身份保持隔离。

来源为已验收个人版的single-app-20261015与mic-source-compare-20261015/project；只读这些目录，不修改、替换或复用个人运行配置。

逐字保留的源码：StandbyCoordinator、LocalIngress、Input、Gesture、Cursor、ExtensionDisplayLayout及采集生命周期工具。Pad LocalAvailability和native availability仅修改独立发现服务名称与端口。Pad本地接续函数按原版恢复。NativeCapture保留现有H264回退差异，正常HEVC编码、ACK、帧窗口、硬解与渲染路径沿用原版。恢复live topology与RATE能力后只发布实际可处理的协议。

## 测试USB与消费者USB

个人版USB使用HDC调试反向转发。为了对照原版体验，本机测试构建显式启用ORIGINAL_USB_TEST；Mac使用已安装官方DevEco中的HDC，动态选择唯一USB连接设备，建立49561/49562到同端口映射，不存序列号、不动个人48561/48562规则。它仍需预先授权的调试连接，不能作为华为应用市场普通USB能力交付。

默认公开构建不启用该标志，不运行HDC。RNDIS/lwIP普通USB研究源码和所有版本保留在本仓库，但不再在这个原版对照构建中替代连接流程。当前消费级USB自动恢复及多机型适配仍未通过，应用市场提交继续暂停。

本地开发：Mac以`YQ_ORIGINAL_USB_TEST=1 bash mac/build.sh`编译；Pad CMake参数为`-DYINGQIAO_ORIGINAL_USB_TEST=ON`。签名Profile与配对私钥不进入仓库。

Gesture.swift沿用原版的非公开CGEvent手势封包；CGVirtualDisplay本身同样是非公开Mac接口。编译和当前设备验收不能代表其他系统兼容或正式分发已获审核。
