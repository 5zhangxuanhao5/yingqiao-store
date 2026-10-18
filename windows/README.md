# Windows 路线（尚未实现）

Windows 真扩展屏可使用微软官方 [IddCx 间接显示驱动](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/indirect-display-driver-model-overview)，由驱动提供独立显示器及 DirectX 表面，用户态服务使用 Media Foundation 硬件编码，再接入同样的配对、传输与输入协议。它不是把 macOS 应用重新打包成 EXE。

还缺 WDK工程、驱动/安装器签名、GPU与系统矩阵、Windows主机实测。不能要求普通用户开启测试签名或关闭 Secure Boot 来安装正式产品。本目录只提供无修改的能力调查脚本；它不是可工作的扩展屏客户端。
