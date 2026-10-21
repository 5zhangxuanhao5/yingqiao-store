# 平板后台保留扩展桌面候选 test.9

2026-10-21。Mac 0.4.0-test.9（build 48），HarmonyOS 源码候选 0.3.15（build 48）。此候选在独立工程实现，**尚未安装、尚未完成锁屏/切应用真机验收**。不要把编译和模拟测试当成设备验收；不改变默认分支推荐的稳定版本，也未更新华为分发。

## 改动

- 平板已建立扩展屏后，申请鸿蒙 `MULTI_DEVICE_CONNECTION` 长时任务。只增加 `KEEP_BACKGROUND_RUNNING` 和 `multiDeviceConnection` 声明；没有借用音频、录音或定位保活。系统拒绝时显示提示并保留原前台使用方式。
- 进入后台或窗口隐藏后，向支持 `background-retain-v1` 的 Mac 发送已认证的 `PARK`，释放键鼠、轴监听与光标锁，停止媒体连接。Mac 停止采集、编码和上传，继续持有同一块虚拟显示器。已认证的原生待命心跳用于延续保留状态。
- 返回前台后，等待新的有效 Surface、窗口焦点和本地连接就绪，自动接续原显示器，保持全屏意图。Surface 销毁和重建会释放并重新取得 NativeWindow，不使用旧解码目标。
- 显式“结束会话”、Mac 点击结束、应用正常销毁都会执行结束清理；若进程退出时结束消息未能送达，Mac 通过失联宽限回收桌面。后台没有媒体连接时，通过原来的加密待命通道发送带会话 ID 的结束请求，Mac 同时校验请求所属 Pad 进程。其他 Pad 不能抢占保留桌面。
- 待命心跳失效后设宽限时间回收孤立桌面；返回前台超过 30 秒仍未就绪则退出恢复流程。系统强制终止应用/禁止后台运行、网络完全断开不保证无限保留。后台任务是否会被这台 Edge 的系统策略取消仍须实测。
- 保留 test.7 多型号媒体协商、test.8 监听失败恢复和就绪状态判断。安装中的完整版及当前 Pro、Air、Edge 软件未替换。

## 验证与限制

- 本地 Apple Silicon / Intel 通用 Mac 编译与无窗口自检通过；包括保留桌面的归属、心跳续约和失联到期。
- 官方 SDK 的 HarmonyOS ArkTS、C++ 编译与未签名 HAP 打包通过。
- `tools/test-background-extension.cjs`：任务申请/结束竞争、重复退后台、拒绝申请、旧 Mac 不支持、恢复与显式结束。
- `tests/session_end_policy_test.cpp`：PARK 仅用于已协商能力的扩展会话，旧版和明确结束继续 STOP；原 HANDOVER 语义保留。
- 发现/配对回归测试通过。云端构建结果以本标签对应 Actions 为准。
- HAP 是编译产物，未签名，不能直接安装；开发者触控板兼容构建仍按既有 `prepare-original-tablet-test.py` 流程准备隔离 SDK，不改官方 SDK 或设备分类。没有在这一轮宣称原始触控板、锁屏保留或后台恢复真机通过。

官方接口依据：[backgroundTaskManager](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/js-apis-resourceschedule-backgroundtaskmanager-V14)。

## 后续设备验收

在不影响当前工作时，经同意再更新 Mac 与 Edge：

1. 已连接扩展屏时切回鸿蒙桌面，确认 Mac 的虚拟屏和原窗口仍在、采集/发送已停。
2. 回到映桥，确认无需再点击开启就恢复原桌面及输入。
3. 锁屏至少 2 分钟，再解锁回到映桥，重复确认；并观察系统是否取消长时任务。
4. 从 Mac 结束后台会话，确认平板不自行重建。再从平板启动、结束，确认后台任务释放。
5. 同时保留 Sidecar/Air，对照前台输入、跨屏拖动、USB/局域网接续和待命占用。
