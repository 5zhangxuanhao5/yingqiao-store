# 0.3.1 测试版

## 下载

**[下载 Mac 测试版 ZIP](https://github.com/5zhangxuanhao5/yingqiao-store/releases/download/store-v0.3.1-test.1/Yingqiao-Mac-Test-0.3.1.zip)** · [小白逐步安装说明](https://github.com/5zhangxuanhao5/yingqiao-store/blob/main/docs/MAC_INSTALL.md)

文件名：Yingqiao-Mac-Test-0.3.1.zip。源码、原生依赖不是安装包。该包仍是未完成 Developer ID 公证的测试应用；遇到系统阻止打开时请反馈，不绕过系统保护。

## 修复

- USB发现把公开证书嵌入JSON时遗漏换行，Pad身份比较因此拒绝接受。现在完整转义所有控制字符，新增真实JSON解码往返测试，不能删除PEM中的换行。
- 局域网UDP发现不再在15秒后关闭；Mac发现平板后可发送无凭据的公开HELLO，唤起单播发现回复。两种机制都不赋予信任，首次LINK仍需Mac明确允许。
- USB探测失败保留同一Mac的已发现局域网路径；USB候选不覆盖已记住的真实局域网地址，避免备用路径在刷新时被清掉。
- Pad扩展屏/附近Mac卡片保持等高，从370缩到260；精简重复装饰，设备列表仍可滚动。
- 首次引导在可视区域居中，长说明仍可滚动。下载说明列出确切文件名、解压、放入应用程序、授权和首次连接步骤，仓库首页增加直接下载入口。

## 验证和边界

两端0.3.1(22)。Mac ARM/Intel编译及headless自检通过，Harmony测试签名构建通过，JSON证书换行/控制字符回归测试通过。Mac ZIP解压后逐文件比较和签名完整性检查通过。实际发现、连接和新布局仍需真机验收，未将编译当作实测成功。

个人版保持不变。开发USB仍需已授权HDC调试环境；普通消费者USB和官方SDK接纳禁转触摸配置仍未完成。多机型、正式签名/公证和商店审核尚未通过。设备绑定HAP、配对、私钥、Profile、账户状态不公开。
