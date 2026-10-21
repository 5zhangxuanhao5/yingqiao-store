# 下载与版本选择

- **鸿蒙应用商城版 0.3.11**：[打开映桥商店页](https://appgallery.huawei.com/app/detail?id=cn.edgelink.store)。已于 2026-10-21 核对上架；不需要开发者模式。未唤起商店时，在平板应用市场搜索“映桥”。
- **Mac 单应用合并预览版**：[下载 0.4.0-test.6 ZIP](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/mac-unified-v0.4.0-test.6/Yingqiao-Mac-Unified-0.4.0-test.6.zip) · [配套源码/校验](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/mac-unified-v0.4.0-test.6)。包含平板扩展与 Mac 互联，Pro→Air 已实测；仍为预览。
- **GitHub 平板开发版**：需要开发者模式、本人调试签名；有线使用 HDC 调试通道，需要 USB 调试。与商城版不是同一签名/输入配置。

商店版的普通 USB 连接需手动开启 USB 共享网络；开发版 HDC 通道不需要共享网络。两者均不能笼统承诺只插线即用。详见 [完整安装教程](INSTALL.md)。

- **Mac 多机型兼容候选 test.7**：[候选下载与兼容范围](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/mac-unified-v0.4.0-test.7)。新增媒体能力和缩放协商；只通过编译/模拟，未安装到现有设备，完整协商需要两台 Mac 都使用 test.7。

## 保留的开发基线

当前可运行开发版：Mac0.3.15(36) + Pad0.3.14(35)。

| 文件 | 用途 |
| --- | --- |
| [Yingqiao-Mac-0.3.15.zip](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/Yingqiao-Mac-0.3.15.zip) | Mac应用，解压后放入应用程序 |
| yingqiao-store-source.tar.gz | 同一Release中的源码归档，不能直接当应用安装 |
| yingqiao-store-native-dependencies.tar.gz | 与源码配套的原生依赖，解压到源码根目录 |
| SHA256SUMS | 同名附件SHA-256校验 |
| SOURCE_MANIFEST.json | 归档内逐文件源码SHA-256清单 |

[打开完整Release附件页](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/developer-v0.3.15-test.1) · [详细安装步骤](INSTALL.md)

没有通用签名平板HAP。作者设备绑定的调试包不公开；平板安装需要使用本人账号、设备和调试签名构建。无需下载旧“完整版”或使用商店安装包替代本开发包。Mac包为本地开发签名，未做Apple公证；支持范围与安全提示见安装教程。
