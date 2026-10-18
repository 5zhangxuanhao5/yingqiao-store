# 核心能力：有线与无线接续

这是正式发布硬门槛，未打通普通权限 USB 通道之前，不把局域网预览宣称成完整产品。

个人版已验证的 USB 通道使用 HDC 调试转发；它依赖开发者选项、设备授权和调试服务，不符合“商店下载安装后自然使用”的目标。上架版不内置或自动启动 HDC、不要求用户打开调试模式，也不修改系统 USB 设置。

[华为 USB 概述](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/usb-overview-V14)提供宿主访问所连接 USB 外设的能力。这不能证明普通平板应用可以在设备模式暴露自定义流接口，也不能证明 Mac 能以通用 USB 设备角色被平板访问。随后对官方API26 SDK的逐项检查发现：`@ohos.usbManager` 从API14公开了 `getAccessoryList / hasAccessoryRight / requestAccessoryRight / openAccessory / closeAccessory`，相关声明未标为systemapi。因而优先验证配件模式，而不是假设缺少公开接口。公开接口可编译仍不代表每台固件支持AOA或实际数据通路。

部分机型可[开启 USB 网络共享](https://consumer.huawei.com/cn/support/content/zh-cn11639869/)。可调查系统实际暴露并被 Mac 支持的 USB 网络接口，但这个设置并非所有型号、系统和 Mac 都相同；不能自动把 RNDIS、CDC-NCM 或 USB-C 接口名称当成可用性证据，不能要求关闭安全保护或安装未签名驱动。

当前代码层次：

- `shared/TransportPolicy.hpp`：只有正确配对身份、通过实际认证、支持普通用户使用且测量仍新鲜的线路参与选择。性能改善需超过20%，至少5秒切换间隔；拖动时推迟改善性切换，活动线路失效时可立即选可用备用线路。策略测试通过；**它尚未接入消费级 USB 适配器，不等于实际无缝切换完成**。
- `mac/Sources/StoreCapture.swift` 与 `main.swift`：异常断开时保留同一虚拟显示器至多10秒；正常结束立即释放，不保留采集或编码。新会话创建新密钥和计数。已编译，未在新软件的真实显示会话实测。
- 当前平板预览仅走已配对局域网。消费者 USB 检测、双路并存、切换通知与自动重连仍需集成及真机验证，首页明确提示状态。

发布验收必须包括：仅无线启动→插线后台测量→切换到更优有线→拔线无线接续→插回再评估；窗口位置、显示器ID、按住拖动、键盘释放、鼠标形态、全屏与系统边缘手势、显式结束均须检查。还要覆盖不传数据的充电线、USB2/3、差Wi-Fi、多路由、系统休眠／旋转／后台、iPad随航并存。发现不支持的线或机型时自动保持无线并清楚提示，不能让用户手选底层协议。

## 新增USB配件研究代码

`harmony/.../store/HarmonyAccessory.ets` 使用公开配件接口，只在未来明确调用时请求对应配件访问授权；没有加入首页启动连接流程，不在后台申请权限。Mac的`mac/USB/AccessoryControl.cpp`只提供普通IOKit选定设备适配，不调用seize、不自动枚举或启动模式切换，尚未链接到GUI。

`usb/AccessoryProtocol.hpp`按[AOSP官方AOA说明](https://source.android.com/docs/core/interaction/accessories/aoa)实现有授权门控的协议探测和启动请求序列；`usb/StreamMux.hpp`提供控制／视频分流、分片解析、队列边界和公平调度。它仍需接入真实bulk端点、TLS流桥接、身份认证、测速和切换状态机。Android/AOSP文档只定义参考协议，不能证明HarmonyOS固件完全兼容。

特别注意AOA会让设备重新枚举，并可能与MTP传文件互斥。实现不得抢占正在工作的USB接口；首次使用需明确提示并取得系统访问授权。不能为追求“零操作”而偷偷打断用户文件传输。此轮没有对任何真实USB设备发送控制请求。
