# 映桥：选择版本、安装与连接

下方开发构建步骤对应 **Mac 0.3.15 (36) + 平板 0.3.14 (35)**。两端需要分别安装；仅安装其中一端不能扩展屏。当前面向愿意使用开发工具的体验者，尚不是面向所有用户的一键安装版。

## 普通用户：从鸿蒙应用商城安装

1. 在鸿蒙平板上打开[映桥商店详情页](https://appgallery.huawei.com/app/detail?id=cn.edgelink.store)，或在应用市场搜索“映桥”。
2. 按商店提示安装。**商店版不需要开发者模式、USB 调试、DevEco 或自行签名。** 若浏览器没有唤起商店，直接使用应用市场搜索。
3. Mac 下载下方 Mac 安装包，解压放入“应用程序”；按照应用用途提示授予录屏、键鼠及系统要求的本地网络权限。
4. 两端打开映桥，使用能互相访问的局域网；选择附近设备并在 Mac 允许首次连接。
5. 想用普通有线连接时，平板须支持并开启“USB 共享网络”。插回线后系统可能不会保留此模式，需要重新开启；不要把商店版理解为普通线一插即用。

2026-10-21 已核对商店 0.3.11 为已上架。商店版与开发版签名及输入兼容配置不同；开发版的按压跨屏拖动验证不能直接套用于商店版。已有其中一版时，不要盲目覆盖；切换渠道可能需卸载并重新连接。

## 两台 Mac：使用单应用合并预览版

1. 在发送和接收的 Mac 上分别下载 [Yingqiao-Mac-Unified-0.4.0-test.6.zip](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/mac-unified-v0.4.0-test.6/Yingqiao-Mac-Unified-0.4.0-test.6.zip)。解压安装方法与下方 Mac 步骤相同，不需要同时安装旧“Mac接屏测试”。
2. 两台 Mac 在可互访的局域网中打开映桥，进入“Mac 互联”。接收电脑选择“接收 Mac 画面”，发送电脑选择“扩展到另一台 Mac”。
3. 发送电脑按说明完成录屏及键鼠权限；缺少授权时先设置再连接。接收电脑如果弹出本地网络访问请求，允许后重新发现。
4. 接收端选择发送电脑并连接，在发送端允许本次连接；接收端显示独立全屏桌面。
5. 已实测 Pro M5 Pro → Air M4，全屏为 2560×1664；随航断开、重连后仍独立。暂不据此保证反向组合、全部设备或长时间多屏稳定性。

两台 Mac 目前实测使用局域网。普通 USB-C 充电/数据线不等于可用的 Mac 间网络；需要系统实际建立有线网络才可能使用，当前未验证 Mac 间有线自动切换。这个预览版未做 Apple 公证，仍应阅读下方安全提示。其[源码与版本说明](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/mac-unified-v0.4.0-test.6)与默认分支开发基线分开归档。

## 开发者体验者：下面才是开发版构建流程

**Edge 上安装、运行 GitHub 调试版需要开发者模式保持开启。** USB 安装和 HDC 有线传屏还需开启 USB 调试并授权自己的 Mac；关闭开发者模式后，系统可能禁止调试应用运行。无线连接也不会把调试包变成商店签名包。只想正常下载安装的用户请选择上方商城版。

## 一、准备什么

- 一台 Mac、一台运行兼容 HarmonyOS 的华为平板。已实测设备包括 MacBook Pro 16 英寸（M5 Pro）、MacBook Air 13.6 英寸（M4）与 MatePad Edge（HarmonyOS 7）；未保证其他组合均可用。
- 一根可以传数据的 USB 线。只充电的线不能安装或建立 HDC 通道。
- Mac 上安装 [官方 DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 和工程所需 HarmonyOS SDK。此工程 target API 26、compatible API 24，原设备构建使用 API 26 工具链；不是 Android APK 工程。
- 本人的华为开发者账号、可用的真机调试签名；签名和设备授权按华为当前规则办理。不要向任何人发送账号密码、私钥或设备 Profile。
- 如果只运行已装好的平板版并使用无线，Mac 不需要编译环境；但有线 HDC 通道仍需官方 DevEco 中的工具。

先了解：公开 Release 没有作者本人设备绑定的已签名 HAP。**平板需要自行构建并签名**；不会因为下载 Mac ZIP 就自动安装平板。没有条件做调试签名的用户，目前不能按普通应用的方式直接安装这个开发版。

## 二、Mac 端下载安装

### 1. 下载正确的 ZIP

打开 [0.3.15 下载页](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/developer-v0.3.15-test.1)，找到页面下方 **Assets / 附件**，展开后下载 **Yingqiao-Mac-0.3.15.zip**。[也可直接点击这里下载](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/developer-v0.3.15-test.1/Yingqiao-Mac-0.3.15.zip)。

不要把 `Source code (zip)`、`yingqiao-store-source.tar.gz` 或 native-dependencies 当成可直接打开的 Mac 应用。

### 2. 解压与放置

1. 在访达中打开“下载”，双击 ZIP。
2. 把解压出的 **映桥.app** 拖入访达左侧“应用程序”。
3. 如已安装旧“映桥”，先退出旧程序再替换。不要替换名称不同的“映桥完整版”。
4. 从“应用程序”打开映桥。这个 ZIP 同时包含 Intel 和 Apple Silicon 架构，无需选择 M 系列版本。

这是本机开发签名包，未经过 Apple Developer ID 公证，其他 Mac 可能被系统拦截。确知来源后，请按 [Apple 官方的单应用打开说明](https://support.apple.com/zh-cn/102445)判断和处理；不要关闭整个系统的安全校验。若仍无法正常打开，保留错误文字反馈，不把安装成功视为已保证。

### 3. 按用途说明授予权限

先阅读映桥里的说明，再继续申请权限：

| 权限 | 为什么需要 | 常见设置位置 |
| --- | --- | --- |
| 本地网络（系统提供时） | 发现并连接你选择的平板 | 系统设置 → 隐私与安全 → 本地网络 |
| 录屏 / 屏幕与系统音频录制 | 把独立扩展桌面送往平板 | 系统设置 → 隐私与安全 → 录屏与系统录音（名称随系统版本变化） |
| 辅助功能 / 键鼠控制 | 接收平板的键盘、触控板和触屏操作 | 系统设置 → 隐私与安全 → 辅助功能或系统对应控制页面 |

以应用跳转出的具体页面为准。认证由本人在 Mac 完成，不要把密码发给开发者。如果列表里还没有映桥，先完成 macOS 的权限请求；不要给其他同名旧程序误授权。系统要求退出重开时，重开应用后再核对“屏幕共享”“键盘与触控板”均显示已允许。

## 三、平板端用自己的签名安装

### 1. 下载源码、依赖、校验文件

在同一 [Release](https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/developer-v0.3.15-test.1) 下载这三个文件，保留原文件名：

- `yingqiao-store-source.tar.gz`
- `yingqiao-store-native-dependencies.tar.gz`
- `SHA256SUMS`

建议在 Mac 的“下载”中新建 `yingqiao-dev` 文件夹，把三个文件放进去。打开终端，逐行执行：

```sh
cd "$HOME/Downloads/yingqiao-dev"
shasum -a 256 yingqiao-store-source.tar.gz yingqiao-store-native-dependencies.tar.gz
```

把两行结果分别与 `SHA256SUMS` 中的同名文件比较，一致再继续。该文件还列了其他附件，因此只下载两个归档时，不要直接对整份清单执行批量检查并误把“缺少其他文件”当成哈希不一致。

```sh
mkdir source
cd source
tar -xzf ../yingqiao-store-source.tar.gz
tar -xzf ../yingqiao-store-native-dependencies.tar.gz
```

解压后的 `harmony/` 是平板工程，`mac/` 是 Mac 工程。固定依赖按归档目录放回 `harmony/entry/src/main/cpp/vendor/` 和 `third_party/`；不要只解压源码就直接编译。已有 `source` 文件夹时，请换一个新的空目录，不覆盖自己正在修改的工程。

### 2. 准备平板调试连接

1. 平板“设置 → 关于平板”中按系统提示启用开发者选项；具体入口可能因系统版本不同而变化。
2. 在“系统和更新 → 开发者选项”启用 USB 调试。
3. 数据线连接 Mac，平板保持解锁，确认本人 Mac 的调试授权。Mac 如询问是否允许配件连接，也按本人意愿确认。
4. 暂时关闭“USB 共享网络”，避免它覆盖调试用的 USB 模式。

可在 Mac 终端验证：

```sh
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets
```

应出现实际设备。显示空列表时，先检查线材、解锁和调试授权，不要反复点击映桥的连接按钮。

### 3. 准备本版输入兼容配置

本开发版保留了实际设备上可跨屏按压拖动的输入配置；它不是原厂 SDK 默认接受的商店配置。以下工具只在新建目录中复制相关检查文件，其余链接到已安装 SDK，**不改写 DevEco 安装目录，不关闭签名校验**。这仍是实验流程，其他 SDK 版本可能不兼容。

在刚才的 `source` 目录执行：

```sh
python3 tools/prepare-original-tablet-test.py \
  --device-test-only \
  --sdk /Applications/DevEco-Studio.app/Contents/sdk \
  --output "$PWD/.sdk-device-test" \
  --project "$PWD/harmony"
```

需要 Python 3。`.sdk-device-test` 必须是未存在的新目录；重复执行时换一个新输出目录，不要删除系统 SDK。该脚本同时开启本版 HDC 开发通道。

### 4. 在 DevEco 配置本人签名

1. DevEco Studio 选择 **Open / 打开**，选中 `source/harmony`，不要选整个 source 根目录。
2. 等待工程同步和依赖安装；如提示所需 SDK 缺少，按 IDE 提示安装匹配版本。
3. 打开 **File / 文件 → Project Structure / 项目结构 → Signing Configs / 签名配置**。
4. 参照 [华为自动签名说明](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-auto)，登录自己的账号，选自己的调试设备并生成适用的调试签名；不要用作者的证书、Profile 或发布签名。
5. 应用配置后，本地 `harmony/build-profile.json5` 会有本人签名信息；**不要把它提交到公开仓库**。账号权限、包名或设备注册报错时先按官方错误处理，不保证其他账号能跳过华为的签名要求。

### 5. 在终端构建，安装到平板

签名配置保存后，回到终端中的 `source` 目录执行：

```sh
cd harmony
export DEVECO_SDK_HOME="$(cd ../.sdk-device-test && pwd)"
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  assembleHap --mode module -p product=default -p module=entry@default \
  -p buildMode=release --no-daemon
```

这里虽然选择 release 编译优化，**分发身份仍是自己的调试签名**，不是华为应用市场正式安装包。不要改用 `tools/build-harmony.sh` 复现这项实验：该脚本默认指回原厂 SDK，会丢失本次隔离配置。

成功后检查 `harmony/entry/build/default/outputs/default/` 中的 `entry-default-signed.hap`。只有 unsigned 文件说明签名尚未配置好，不能当作已可安装。只有一台平板接线时，在目前的 harmony 目录执行：

```sh
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc install -r \
  entry/build/default/outputs/default/entry-default-signed.hap
```

出现签名不一致时，不要直接卸载已有应用：卸载会清空它的连接记录。先确认旧包是不是同一调试签名或商店包，决定是否需要备份和重装；不要影响另一应用“映桥完整版”。调试版运行可能仍要求保留开发者模式，这是此安装方式的限制。

## 四、第一次连接

1. 两端打开“映桥”；平板先完成隐私说明。开发版不再显示电脑下载引导。
2. 无线：两端加入可互通的同一局域网或同一手机热点。有线：连接已授权调试的 USB 数据线，Mac DevEco 必须位于上述路径。
3. 平板首页“附近的 Mac”或 Mac 首页“附近的 Pad”应出现对端。未发现实际可达设备时，“开启扩展屏”应置灰。
4. 一台设备直接点“开启扩展屏”；多台时选择目标。首次连接在 Mac 确认“允许这台平板连接”，不用手动输入匹配码或 IP。
5. 进入后是独立扩展桌面。若方向不合习惯，在 Mac“系统设置 → 显示器 → 排列”中调整屏幕左右位置；不需要把扩展屏改成镜像。

## 五、怎么操作和结束

- 平板键盘：输入和组合键。
- 触控板：单指移动指针，按住拖窗，双指滚动，双指捏合缩放（取决于目标 Mac 应用）。
- 触屏：轻点即点击；单指上下滑动滚动页面；手指停住长按再移动，拖窗或拖选文字。如果一落指就移动，会按滚动处理。
- 平板侧滑：打开菜单，可退出全屏或结束会话。
- 点“结束会话”后，Mac 释放本次虚拟扩展屏，停止本次采集、编码和媒体发送；应用可继续发现设备。

## 六、检查有线无线接续

先保持两端无线可以互相连接，再接线开启扩展屏。拔下线后，应用应尝试通过无线继续同一个扩展桌面；插回已授权 USB 后，在后台重新评估通道。切换期间可能短暂停顿，恢复时间取决于实际网络和 USB 状态。

两条路不会为了“叠加带宽”同时重复传同一份画面；界面无需选 Wi-Fi 或 USB。校园网络若阻止两端互访，拔线后没有可用的无线线路，就无法保证接续。

## 七、常见问题

**只接线，找不到 Mac？** 确认装的是本文开发版，平板 USB 调试已授权，官方 DevEco 在固定目录，`hdc list targets` 能看到设备；仅充电不能建立 HDC 通道。本版不要求开 USB 共享网络。

**两台都连 ZJU Secure，却互相找不到？** 同名无线网络不等于允许客户端互访；组播过滤和设备隔离只是可能原因，不能只凭名称断定。先用同一手机热点对照；仍不行再检查应用、本地网络权限和防火墙。不用关闭整个防火墙或安装额外网络驱动。

**画面有了，键鼠不动？** 核对 Mac 的键鼠控制授权实际有效。只有“系统设置里开关亮着”不一定代表更新后的程序已获授权；按应用提示核对当前应用，系统要求重开时重开。

**按压拖动在边缘停止？** 检查是否真的按步骤使用本版实验输入配置构建，原厂默认构建或其他正式签名包不等同于此开发包；其他平板仍待验证。

**支持 iPad、Android、Windows 吗？** 本仓库的平板端是 HarmonyOS 工程；当前没有这些平台的可用配套应用。Mac 与 iPad 随航同时使用曾做过设备测试，但不能因此保证每个显示器组合都兼容。

反馈请提供设备型号、系统版本、映桥版本、连接方式、复现步骤与错误文字。请先遮住设备名、账号、内网 IP 等个人资料；不要上传 Profile、私钥、配对文件或整个应用数据目录。
