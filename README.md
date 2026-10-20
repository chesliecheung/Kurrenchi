# Kurrenchi

Kurrenchi 是一款为 Apple silicon MacBook 设计的原生 macOS 电池健康与充电策略工具。它默认常驻菜单栏，详细数据和控制能力集中在独立的 **Energy Studio** 仪表盘中。

> Kurrenchi 是独立项目，与 AlDente、AppHouseKitchen 或 Apple 无关联，也未使用其品牌、图形或专有代码。

## 设计与体验

- 启动时不弹出主窗口，仅显示菜单栏状态
- 独有的 Energy Studio 高斯玻璃视觉体系与无横幅浮岛布局
- 自定义应用图标与菜单栏闪电图标
- 24 小时电量、温度和功耗趋势图
- 原生 SwiftUI，不使用 Electron

## 功能

- 20%–100% 自定义充电上限
- Sailing 航行缓冲区，减少微量反复启停
- 自定义高温暂停充电阈值
- 手动强制放电与临时充至 100%
- 调低上限时自动放电
- 引导式电池校准流程
- 睡眠前安全状态处理
- 电池健康度、循环次数、温度、双向电流、容量、电压和序列号监测
- 登录启动、菜单栏显示定制与控制组件管理
- 在应用内安全安装或卸载后台 Helper 组件

## 安装

从 [Releases](../../releases) 下载 DMG，将 `Kurrenchi.app` 拖入 `Applications` 文件夹。首次启用硬件控制时，应用会请求管理员权限安装本地 Helper。

当前发布包使用开发者本地签名。用于公开分发时仍需要 Developer ID 签名与 Apple 公证。

## macOS 27 与 M4 说明

新版本 Apple silicon 固件可能要求私有 entitlement 才能访问直接充电 SMC 键。Kurrenchi 会检测能力并在界面中明确显示当前后端：

- **直接 SMC**：停止充电时仍可由适配器给整机供电。
- **适配器兼容模式**：达到上限后切断适配器输入，此时电脑会消耗电池。
- **监测模式**：只读取数据，不执行硬件写入。

第三方进程无法在 Mac 完全关机后继续运行，因此 Kurrenchi 不承诺在关机状态维持软件充电策略。使用 Kurrenchi 硬件控制时，建议关闭系统“优化电池充电”，避免两套策略同时决策。

## 构建

要求 macOS 15+、Apple silicon 与 Xcode 16+。

```bash
swift test
scripts/package-app.sh
scripts/package-dmg.sh
```

指定签名身份：

```bash
KURRENCHI_SIGN_IDENTITY="Developer ID Application: …" scripts/package-app.sh
KURRENCHI_SIGN_IDENTITY="Developer ID Application: …" scripts/package-dmg.sh
```

## 安全边界

- Helper 只操作充电开关相关 SMC 键，不修改电池容量、循环次数、序列号或固件。
- 任何控制状态在 20% 电量时都会恢复适配器输入，防止兼容模式继续耗尽电池。
- Helper 未安装时，应用保持只读监测模式。

## 开源许可与致谢

项目主体采用 MIT License。SMC 传输层参考并改编自 MIT 许可的 `MlayKlayer/battery-limiter` 与 `SMCKit`，完整第三方声明位于 `Sources/KurrenchiShared/LICENSE-MIT.txt`。
