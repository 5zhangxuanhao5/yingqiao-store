# 0.2.1 触控板配置恢复候选

用户确认0.2.0画质/流畅度和拔线接续正常，但按压拖动失效。诊断有24个按压触摸移动、坐标不变；原始鼠标位移只在松开后到达。

仅恢复个人版已验证的 tablet.multiModalInputOptions.mouse2TouchEventMode=disabled；不更改传输、码率、权限、设备分类或输入实现。Mac继续0.2.0(18)，Edge候选0.2.1(19)。

官方API26.0.0.105 schema不接受此字段。默认源码仍使用官方可构建的空profile；开发者必须显式运行 tools/prepare-original-tablet-test.py --device-test-only --sdk <官方SDK根> --output <新隔离目录> --project <独立测试工程>，随后将DEVECO_SDK_HOME指向隔离目录构建。只复制modulecheck并扩展一个严格字段，其余文件链接官方SDK；不修改安装的SDK、不绕过权限/签名校验。这是个人版测试打包流程的恢复，不能作为AppGallery正式包或官方SDK兼容通过的证据。无私人签名/profile包含在公开仓库。

实际按压拖动、双指滚动和屏幕边缘行为仍待本版本设备验收。商店正式输入配置仍是发布阻塞项。
