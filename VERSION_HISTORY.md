# Version history

## store-v0.1.13-test.1

Mac-only correction: 0.1.12 real-device testing exposed an empty USB address passed to the LAN parser, causing an out-of-range trap during discovery. Reject empty/scope-only/NUL addresses, guard USB address export, and exercise the actual path in the headless self-test. Correct the loopback NWListener creation to use its already specified local endpoint without a second port override. Harmony remains the separately installed 0.1.12 diagnostic client. USB DHCP/streaming and cable handover remain unaccepted.

## store-v0.1.12-test.2

Preserve imported lwIP line endings explicitly so the Git archive matches the audited SHA-256 bytes. The test.1 candidate exposed Git normalization of upstream CRLF after manifest generation; it is not an accepted recovery archive and was not installed. Application sources/binaries are otherwise unchanged from the 0.1.12 candidate.

## store-v0.1.12-test.1

Candidate: retain the user-improved 0.1.11 media core, add a consumer-mode USB RNDIS adapter using IOUSBHost and BSD-licensed lwIP, a local-source-port-gated TLS bridge, USB public-identity discovery, and authenticated measured-path selection. Hardware verified RNDIS initialization and device receive counter, but no DHCP/ARP response yet; USB streaming and real handover are not accepted. No HDC provider, private WAN runtime, system driver, microphone permission or privileged helper is added. Original personal applications remain outside the build/install scope.

## store-v0.1.11-test.1

User rejected 0.1.10 clarity and asked why the proven personal version was better. Retire the simplified capture/video sender. Port the accepted NativeCapture, bounded lifecycle, timing, cursor monitor, initial layout, and VideoSender LAN implementation, retaining raw-frame permits, two in-flight hardware encodes, measured window, timed encrypted framing and independent cursor records. Remove RTC provider branches and unsupported advertised capabilities; retain isolated TLS identity and one-click approval. Restore HiDPI=1 at half-size logical display mode and full panel pixel output. Add H.264 codec selection around the original HEVC path for capability fallback. Real M4 encoder setup passed at 3120x2080 for HEVC and AVC; this is not display/performance acceptance. Consumer USB, first discovery on multicast-suppressed campus networks and full hot-plug Sidecar recovery remain open.

## store-v0.1.10-test.1

0.1.9 produced real 3120x2080 HEVC frames, but the user still reported stutter. Observed Pad decode P95 about 12ms, input queue below 1ms, render-submission ACK P95 about 159ms. The fixed three-frame window constrained throughput. Restore baseline-plus-bounded-jitter window sizing from the personal-edition approach, with a 4-12 frame cap and tests for initial capacity, invalid/duplicate/cumulative ACK and high-delay bounds. Keep HEVC optional-property fallback. Smoothness is not yet accepted; this is still LAN, not consumer USB.

## store-v0.1.9-test.1

0.1.8 failed on the real Mac: HEVC returned -12900 for MaxFrameDelayCount=0, which had incorrectly been treated as a mandatory property. Preserve real-time/reorder settings; optional unsupported frame-delay hints no longer reject the session. A regression calls the same production settings helper with -12900 for the optional property and checks mandatory failures are still rejected. Preserve actual session failure text instead of overwriting it with normal stop text. Pad numeric diagnostic fields now use supported string log formatting. Real native-size streaming acceptance remains pending.

## store-v0.1.8-test.1

Prefer actual panel dimensions when the hardware capability probe supports them. Bound frame admission using the existing Pad render-submission ACKs, allow no encoder frame delay, and tune bitrate from measured ACK age. This bounds pre-encode production rather than discarding encoded reference frames. Fresh native-profile regression and frame-window invalid/duplicate/cumulative ACK self-tests pass. Remove numeric-code UI as requested; first connection uses explicit Mac approval and pins the selected certificate thereafter, without out-of-band numeric identity verification. Previously approved addresses are probed without a saved preset host. Campus-network initial automatic discovery and consumer USB remain open gates.

## store-v0.1.6-test.1

Pad network information supplies directed subnet broadcast addresses in addition to limited broadcast. Log bounded probe stages and errors, and retain Mac receive-stage diagnostics. Mac own-address request/reply passed without credential fields; actual Pad discovery remains unverified. No consumer USB claim: read-only AOA GetProtocol request stalled on the currently connected Edge after HDC ownership was released.

## store-v0.1.5-test.1

Real Pad diagnostic showed mDNS start success with no serviceFound events. Add five foreground LAN broadcast probes over 10 seconds, closing the discovery socket after 15 seconds. Mac replies with public certificate/name/protocol and echoed nonce only, with private-address, input-size, peer-count and rate limits. TLS approval and pinned certificate trust remain unchanged. Consumer USB remains unimplemented, not substituted by HDC.

## store-v0.1.4-test.1

Observed 0.1.3 readiness callback did not reach ready although Bonjour records were visible on Mac; Pad acceptance was still unverified. Place Mac async setup on the main actor and explicitly schedule Bonjour on the main run loop. Keep the restored dashboard and one-time TLS-code approval flow, with the public project owned by 5zhangxuanhao5. Real device discovery acceptance remains a separate result.

## store-v0.1.3-test.1

Move the public project to 5zhangxuanhao5/yingqiao-store, preserve all history and tags, restore the accepted personal-edition dashboard theme and tablet card layout. Replace QR/manual configuration with mDNS/Bonjour discovery, strict pinned TLS bootstrap and one-time Mac approval after comparing a TLS-exporter-derived code. Remember approved credentials locally. Consumer USB remains incomplete and AppGallery submission is paused. Device deployment evidence is recorded separately; private profiles stay outside public archives.

## store-v0.1.2-test.1

Owner requested a pause in AppGallery publication and named test installation on current Mac and MatePad. Rename both launchers to 映桥测试版, bump independent packages to 0.1.2 (3), preserve personal identities/configuration, and document local-only test scope. Consumer USB remains unfinished. Device-bound signing profiles stay outside public source and releases.

## store-v0.1.1-dev.1

Huawei app registered as 映桥; reviewer draft saved, not submitted. Match tablet launcher name to the registered name; bump isolated package versions. Add operator and authorized public support/privacy email with a current-data-processing explanation. Correct baseline commit vs annotated tag identity. No installation on current devices, no new USB integration, no AppGallery approval or notarization.

## store-v0.1.0-dev.1

Independent public-source prototype. First-run companion installation guide, explicit local pairing, capability-based geometry selection, local-only media policy, Mac13 dual-architecture build, bounded display retention implementation. USB accessory research adapters/fixtures added but not integrated or hardware-proven; no new real-device stream certification, no Windows extension service, no formal AppGallery release. Personal edition remains unchanged in its original private history.

## store-v0.1.14-test.1

0.1.13真实USB传屏成功，拔线自动恢复局域网且窗口保留；用户确认恢复后正常，停顿主要在切换时。移植个人版保留显示器的直接接续逻辑，避免重复设置模式及600ms等待。新增仅会话期间运行的100ms轻量断线状态读取，不重置帧率统计；明确结束时取消。增加本机断开到首帧渲染确认的耗时记录。USB状态发送失败时保留重试。修复Windows检出换行导致源码清单验证失败的问题。新版本实际接续耗时仍待安装测试，不承诺零停顿。

## store-v0.1.15-test.1

0.1.14实机观察到局域网自动切至普通USB：原扩展屏复用，Mac停止旧流至新流渲染确认约278ms，显示器接续约0.05ms；不包含物理拔线发现时间。进一步修复恢复时仍可能选中“测速缓存有效、实际媒体已经断开”的原线路：已知失败的活动线路不参与本次恢复，即使刚刚切换或断线时正按住拖动。增加对应共享生产策略回归。仅更新Pad和共享策略；Mac继续使用0.1.14原二进制。

## store-v0.1.16-test.1

0.1.14又记录到一次自动接续耗时1207ms、显示器接续1.1ms。代码检查确认新AUTH可能赶在旧采集Stop完成之前，被busy分支拒绝，随后平板必须等待一秒重试。Mac仅对已经核对令牌、用途与尺寸参数的请求保留一个等待槽，最多等待两秒，每10ms检查旧采集释放；不再通过断开重试消耗一秒。显式结束和会话代次变化使等待请求失效，其他请求继续有界拒绝。平板沿用0.1.15。实际拔线效果仍待验收。

0.1.16同时约束健康线路的优化切换：必须连续三组不同时间的认证测速都确认另一条线路更好，重复读取同一测速不会累计次数。已断线恢复不等待该门槛。此改动针对实测USB仍连接时两条健康线路反复优选导致的额外停顿；增加生产策略测试，平板同步更新到0.1.16。

## store-v0.2.0-test.1

按用户要求以原版扩展屏为基线，保留现有界面与媒体/输入核心，恢复原版LocalAvailability持续TLS备用控制、StandbyCoordinator及Pad接续函数，不再运行周期短连接测速与RNDIS优选替代流程。统一独立49561/49562/49563端口，保留测试版独立身份。恢复原版Input/Gesture、动态屏幕拓扑协议和码率请求应用。

原版USB依赖授权的HDC反向转发，只在显式ORIGINAL_USB_TEST开发构建开启；没有复制设备序列号，不打包开发工具，不当成普通消费者USB。RNDIS研究源码及失败历史保留；上架门槛仍需单独解决。0.1.14拔线未获得恢复确认，0.1.15/16未安装，不宣称失败候选已修复。

## docs-v2026.10.21

- 核对鸿蒙应用商城公开详情页：映桥 0.3.11 已上架，加入正式商店链接。
- 分开说明商店安装、Edge 开发者模式/调试签名和两种 USB 通道。
- 补充 MacBook Pro M5 Pro、MacBook Air M4、MatePad Edge 的分版本实测范围。
- 增加 Mac 合并预览版 test.6 下载和使用步骤；记录 2026-10-20 随航断开/重连后的用户确认，不把预览称为全机型稳定版。
- 仅更新文档和仓库简介，不修改应用、签名、安装或现有设备状态。

## docs-v2026.10.21.2

- 移除下载入口中的开发者姓名提示。
- 增加 Pro 为主机、Edge 与 Air 为映桥扩展屏、iPad Pro 通过随航扩展的四屏使用例子。
- 明确该例子的连接分工和设备兼容边界；应用程序不变。

## docs-v2026.10.21.3

增加独立 Mac 0.4.0-test.7 候选下载及验证边界。保留已实测 test.6 下载；没有安装或更新用户电脑上的软件。
