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
