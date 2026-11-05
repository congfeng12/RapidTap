# RapidTap 连点器 技术文档

> 项目：RapidTap（macOS 原生连点器）
> 文档版本：v1.0
> 更新日期：2026-11-03
> 适用代码：`Sources/` 全部源码

---

## 1. 项目背景

需要一个可自定义的鼠标左键连点工具：

- 自定义**触发键**（不是固定的 F6），按下即触发连点；
- 触发键**全局生效**，前台可以是任意应用或游戏；
- 连点频率可调；
- 点击节奏不能是完全固定的机械周期（拟人化）。

macOS 不允许普通进程直接"按键"，模拟输入必须通过 Core Graphics 事件系统（`CGEvent`），且需要用户授予**辅助功能（Accessibility）**权限。因此方案是原生 Swift + AppKit + CGEvent，编译为 `.app`。

## 2. 功能范围

| 功能 | 实现位置 |
|------|----------|
| 全局触发键录制 / 拦截 | `HotKeyMonitor.swift` |
| 按住连点 / 按一下切换 | `MainViewController.swift` + `ClickEngine.swift` |
| 频率可调（1~60 次/秒） | `Config.swift` / `ClickEngine.runLoop()` |
| 拟人化节奏 | `ClickEngine.runLoop()` |
| 坐标微抖动 | `ClickEngine.performClick()` |
| 配置持久化 | `Settings`（UserDefaults + JSON） |
| 权限引导 / 自愈 / 授权记录 | `MainViewController.refreshPermission()` + `Settings.hasBeenAuthorized` |
| 命令行诊断 | `Diagnose.swift` |

明确不做（YAGNI）：坐标锁定、录制回放宏、脚本化序列、多配置预设、鼠标侧键触发。

## 3. 技术选型

| 方案 | 结论 | 原因 |
|------|------|------|
| Swift + AppKit + CGEvent | **采用** | 原生、无运行时依赖、可直接打包 `.app`，系统 API 权限链路最短 |
| Python + pyobjc | 弃用 | 本机系统 Python 未安装 pyobjc；打包与签名更麻烦 |
| Electron / Tauri | 弃用 | 体积大，全局输入注入仍需 native 桥接 |
| Java (JNativeHook) | 弃用 | 需 JVM，全局热键与事件注入能力弱于 CGEvent |

构建环境：macOS 27.2 / arm64 / Swift 6.4.2（Command Line Tools，无需完整 Xcode），部署目标 macOS 13.0。

## 4. 整体架构

```
┌──────────────────────────────┐
│ MainViewController            │  界面、参数调节、权限状态轮询（0.2s）
│  ├─ 触发键录制 / 显示          │
│  ├─ 频率 / 拟人化参数          │
│  └─ 开始、停止、测试单击        │
└───────────┬──────────────────┘
            │ 读配置（线程安全快照）
┌───────────▼──────────┐   ┌──────────────────────────┐
│ Settings             │   │ HotKeyMonitor            │
│ UserDefaults + JSON  │   │ CGEventTap(.cgSessionEventTap) │
└───────────▲──────────┘   │ 命中触发键 → 吞事件 + 回调      │
            │              └──────────────────────────┘
┌───────────┴──────────┐
│ ClickEngine          │  独立 Thread(.userInteractive)，循环注入点击
│  CGEvent(hidSystemState).post(.cghidEventTap)
└──────────────────────┘
```

线程模型：

- **主线程**：AppKit 界面、事件 tap 的回调注册（tap 的 run loop source 挂在 `CFRunLoopGetMain()`，回调本身只做键码比较后 `DispatchQueue.main.async` 派发，保证不阻塞事件流）。
- **连点线程**：每次 `start()` 新建一个 `Thread`，`qualityOfService = .userInteractive`；`stop()` 置位标志位，线程在当次周期结束后退出。
- **配置**：`Settings` 内部用 `NSLock` 保护，连点线程每次循环取一次值快照，避免读到中间态。

## 5. 关键实现

### 5.1 全局触发键与拦截

```swift
CGEvent.tapCreate(tap: .cgSessionEventTap,
                  place: .headInsertEventTap,
                  options: .defaultTap,          // 可修改/吞事件
                  eventsOfInterest: keyDown | keyUp,
                  callback: rapidTapEventCallback,
                  userInfo: ...)
```

- `.defaultTap` 才能"吞掉"事件（返回 `nil`），`.listenOnly` 只能旁听。触发键被吞后前台应用收不到，避免游戏里同时触发原按键功能。
- 回调必须是 C 函数指针，不能捕获上下文，实例通过 `refcon`（`Unmanaged.passUnretained(self).toOpaque()`）取回。
- 过滤 `keyboardEventAutorepeat != 0`，避免长按触发键时系统重复事件把"切换模式"反复启停。
- 监听可能被系统因超时/用户输入禁用（`tapDisabledByTimeout` / `tapDisabledByUserInput`），回调里需要重新 `tapEnable`。
- 录制模式下吞掉所有 `keyDown`，避免按键误输入到前台应用；`Esc`（键码 53）作为取消。

### 5.2 连点引擎

单次循环伪代码：

```
base = 1000 / cps                              // 毫秒
wait = base ; hold = pressDurationMs
if humanize:
    wait  = base ± (base * jitterPercent / 100)
    hold  = random(16...52) 且 ≤ base * 0.45    // 高频时避免拖慢实际频率
    if random(0..<70) == 0: wait += random(55...160)   // ≈1.4% 概率长停顿
hold = clamp(hold, 2, wait - 1)
post mouseDown → sleep(hold) → post mouseUp → sleep(wait - hold)
```

关键点：

- **按压时长必须压到周期的 45% 以内**，否则 60 次/秒时会出现 hold > 周期，实际频率被显著拖慢。
- 按下与抬起都设置 `mouseEventClickState = 1`，避免被识别为双击。
- 事件源使用 `CGEventSource(stateID: .hidSystemState)`，投递到 `.cghidEventTap`（HID 层），兼容性优于合成事件源。
- 落点取 `CGEvent(source: nil)?.location`（当前光标位置），不锁定坐标。

### 5.3 拟人化设计

| 维度 | 做法 | 目的 |
|------|------|------|
| 间隔 | ±jitterPercent（0~45%，默认 22%） | 消除固定周期 |
| 按压时长 | 16~52ms 随机 | 消除固定脉宽 |
| 停顿 | ≈1.4% 概率 +55~160ms | 模拟人手换气/走神 |
| 启动 | 8~50ms 随机延迟 | 避免每次都在按键同一时刻开始 |
| 落点 | 可选 ±1.2px | 避免完全相同的坐标序列 |
| 事件源 | `hidSystemState` | 事件更接近硬件层 |

**边界**：以上只能消除用户态固定周期特征，无法对抗驱动层/内存/行为模型级反作弊；在联网游戏中使用有封号风险，文档与界面均有明确提示。

### 5.4 配置持久化

`Config` 为 `Codable` 值类型，存储在：

```
~/Library/Application Support/RapidTap/config.json
```

写入策略：`Settings.update` 在锁内修改内存快照，随后**立即原子写入**（`.atomic` 选项，先写临时文件再替换）。选择文件而非 `UserDefaults`，是因为 `UserDefaults` 落盘是异步的：

| 场景 | UserDefaults | 独立文件（原子写） |
|------|--------------|--------------------|
| 拖动频率滑杆连续修改 | 合并异步落盘，进程被强杀可能丢失最后一次 | 每次改动同步落盘 |
| `kill -9` / 崩溃 | 未落盘部分丢失 | 已写入的改动全部保留 |
| 后续加字段 | 需保证整份解码成功 | `decodeIfPresent` 逐字段回退，不整体重置 |

读取顺序：

1. 配置文件存在且可解码 → 直接使用；
2. 否则读旧版本 `UserDefaults`（键 `rapidtap.config.v1`）→ 迁移写入文件并删除旧键，避免双数据源；
3. 都没有 → 写入默认配置。

界面控件初始化与写入都经同一模型，保证状态一致。

另用独立键 `rapidtap.authorizedOnce` 记录「是否成功授权过」，用于区分「从未授权」和「授权后失效」，后者界面会给出针对性的恢复提示。

### 5.5 权限模型

| 能力 | 所需权限 |
|------|----------|
| 创建键盘事件 tap | 辅助功能（部分系统还需输入监控） |
| 投递鼠标事件 | 辅助功能 |
| 读取光标位置 | 无需 |

流程：

1. 启动时 `AXIsProcessTrusted()` 为 false → 自动调用 `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` 注册应用并弹系统提示；
2. 界面上每 0.2s 轮询权限，授权后自动 `monitor.start()`，**无需重启应用**；
3. 「去授权」按钮直接打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`。

### 5.6 授权持久化（稳定签名）

TCC 以代码签名的「指定要求」识别应用：

| 签名方式 | 指定要求 | 重新编译后 |
|----------|----------|------------|
| ad-hoc（`codesign --sign -`） | `cdhash H"..."` | cdhash 变化 → 被当成新应用 → 授权失效 |
| 本地自签名证书 | `identifier "com.rapidtap.mac" and certificate leaf = H"..."` | 保持不变 → 授权继续有效 |

因此 `setup-signing.sh` 生成自签名证书 `RapidTap Local Signer`，导入专用钥匙串 `~/Library/Keychains/rapidtap-signing.keychain-db`（需 `set-key-partition-list` 允许 codesign 无交互使用私钥），`build.sh` 优先用它签名，找不到时才回退 ad-hoc。

实测：连续两次 `./build.sh` 的指定要求完全一致（`certificate leaf = H"20db2a4f..."`），重新编译后应用仍显示「已授权」。

> 该证书只用于本机签名，不写入系统信任设置；删除方式 `security delete-keychain ...`。

### 5.7 界面设计（对齐 macOS HIG / 系统设置）

整体按 macOS「系统设置」的分组表单（grouped form）组织，而不是把控件平铺在窗口里。

| 维度 | 做法 | 原因 |
|------|------|------|
| 背景层次 | 窗口 `underPageBackgroundColor`（#F6F6F6 系），卡片 `controlBackgroundColor`（白） | 系统设置同款「灰底白卡」，分组一眼可辨 |
| 卡片 | 自绘 `CardView`：圆角 10pt，只填充 `controlBackgroundColor`，**不描边** | 与系统设置一致，靠底色差分层（亮色 #F6F6F6→#FFFFFF、暗色 #282828→#1E1E1E，均约 10 级），描边会显生硬 |
| 分隔线 | 1pt，直接使用系统 `separatorColor`（亮色为黑 10% 透明），左侧缩进 38pt 与文字起点对齐 | 之前手动把 alpha 调到 0.28~0.35，比系统重约 3 倍，是「线条很丑」的根因；缩进对齐文字更接近系统设置 |
| 字体层级 | 标题 22 semibold / 行标题 13 / 副标题与说明 11 / 脚注 11 tertiary | 遵循 macOS 字号阶梯，避免全篇一个字号 |
| 图标 | SF Symbols：keyboard、hand.tap、speedometer、wand.and.stars、slider.horizontal.3、cursorarrow、shield | 系统矢量图标，自动适配深浅色与缩放 |
| 开关 | `NSSwitch` 替代 `NSButton(checkboxWithTitle:)` | HIG 对「立即生效的设置项」推荐开关 |
| 主操作 | `bezelColor = .controlAccentColor`，运行中切 `.systemRed` + 变化图标（play/stop） | 强调色跟随系统设置，状态可辨 |
| 窗口 | `.fullSizeContentView` + 透明标题栏 + 隐藏标题，顶部内边距 38pt 让开红绿灯 | 内容与标题栏连成一体，避免标题重复 |
| 深色模式 | 全部使用语义色（labelColor/secondaryLabelColor/…），自绘视图在 `viewDidChangeEffectiveAppearance` 里重绘 | 不硬编码 RGB，切换外观即时生效 |
| 主题切换 | 「外观」分组的三档分段控件：浅色 / 深色 / 跟随系统 → 映射为 `NSApp.appearance`（`aqua` / `darkAqua` / `nil`） | `nil` 保持跟随系统；显式主题覆盖系统偏好，选择随配置持久化 |
| 无障碍 | 开关/滑杆补 `setAccessibilityLabel`，装饰图标 `setAccessibilityElement(false)` | VoiceOver 能正确朗读控件用途 |

程序化同步控件状态（`selectedSegment`、`doubleValue`、`state`）时，控件可能回调 action，而此刻 `selectedSegment` 还是 -1，会走默认分支把「跟随系统」写回配置。`MainViewController` 用 `isSyncingUI` 标志在同步期间忽略 action，避免启动即覆盖用户设置。

界面结构：品牌头 → 权限卡片 → 触发分组（按键/模式）→ 连点分组（频率/拟人化/幅度/坐标抖动）→ 运行状态卡片 → 风险脚注。窗口高度由内容自适应（保持左上角不动）。

### 5.8 应用图标

原图 1254×1254，纯黑背景且无 alpha，图标本体（圆角方形）内部还包含光标投影等纯黑像素，因此**不能用亮度阈值整体抠黑**，否则图标内部会被打洞。

处理流程（一次性生成，产物已入库）：

1. **漫水填充去背**：从画布四边向内填充亮度 ≤ 0.04 的像素，只清除与边缘连通的黑色；图标内部的投影与边缘不连通，得以保留；
2. **边缘柔化**：与外部相邻的边界像素按亮度给半透明（`luma / 0.22` 截断到 0~1），保留原始抗锯齿过渡，避免硬锯齿；
3. **重新排版**：裁到内容边界后等比缩放到 856px，居中放入 1024×1024 透明画布。实测 Calculator / Notes / Chrome 的图标内容均为画布的 83%，本图标与之一致，Dock 里大小不会突兀；
4. **生成 icns**：`iconutil` 打包 16~1024 共 10 档；`Info.plist` 声明 `CFBundleIconFile = AppIcon`，`build.sh` 负责拷贝进包。

> 校验：`NSWorkspace.shared.icon(forFile:)` 渲染结果正常、1024/32/16 三档均无绿色杂边或黑色残边，图标内部格影完整保留。

### 5.9 开机自启动

使用 macOS 13 起的 `SMAppService.mainApp`，而不是旧的 `LSSharedFileList` / 手写 LaunchAgent：

| 维度 | 做法 |
|------|------|
| 状态来源 | 直接读 `SMAppService.mainApp.status`（`.enabled` / `.requiresApproval` / `.notRegistered` / `.notFound`），不额外存配置，避免两处状态打架 |
| 开启 | `register()`，系统在 BTM（后台任务管理）中登记，出现在「系统设置 → 通用 → 登录项」 |
| 关闭 | `unregister()`，BTM 中标记为 `disabled`，用户可再开 |
| 失败处理 | 捕获错误、开关回弹，副标题同步真实状态 |
| 待批准 | `status == .requiresApproval` 时副标题提示去系统设置允许，开关保持关闭态 |

> 注意：登录项记录的是应用**路径**，移动/改名 `.app` 后需要重新开关一次。

## 6. 验证记录

| 用例 | 方法 | 结果 |
|------|------|------|
| 编译与打包 | `./build.sh`（swiftc + 本地稳定签名） | 通过，产物 `RapidTap.app`（arm64） |
| 环境诊断 | `RapidTap --diagnose` | 权限已授权、事件监听可创建、HID 事件源可用 |
| 端到端点击 | 独立测试窗口（floating）+ 自动发送 F6 启停，统计收到的 `mouseDown` | 2.4 秒收到 26 次（设定 12 次/秒，拟人化后约 11 cps），停止后不再计数 |
| 触发键录制 | 界面「重新设置」后按 Tab | 配置写入 `triggerKeyCode = 48`，界面显示 Tab，重启后保持 |
| 参数持久化 | 调整频率/模式/坐标抖动后重启 | 全部保持（6 次/秒、按住模式、坐标抖动开启） |
| 窗口布局 | 多屏（内置 2056×1329 + MateView 2560×1707） | 在鼠标所在屏居中，520pt 宽，无约束警告 |
| 授权持久化 | 连续两次 `./build.sh` 后比对 `codesign -d -r-` | 指定要求完全一致；重启应用仍显示「已授权」 |
| 配置持久化（写入） | 通过 AX 逐个操作界面控件（复选框/分段控件/两个滑块），每次操作后读配置文件 | 每项改动都在 0.4s 内写入文件，无需退出应用 |
| 界面（浅色） | 截图检查分组、间距、强调色、开关状态 | 灰底白卡层次正确，卡片背景 #FFFFFF / 窗口 #F3F4F4 |
| 界面（深色） | 临时强制 `.darkAqua` 截图 | 语义色自动切换：背景 #252323 / 卡片 #282828，无硬编码颜色问题 |
| 界面控件绑定 | AX 操作开关、滑杆、主按钮 | 开关切换、滑杆拖动均即时写入配置文件；开始/停止按钮 1.2 秒点击 8 次（6 次/秒） |
| 主题切换 | AX 依次选择浅色 / 深色 / 跟随系统 | 即时生效并写入 `theme` 字段；深色下背景 #252322、卡片 #282828 |
| 主题持久化 | 选深色后强杀重启 | 重启仍为深色，未被默认值覆盖（验证了程序化同步不会误写配置） |
| 应用图标 | 生成后按 1024/32/16 三档检查，并用 NSWorkspace 渲染包内图标 | 背景透明、无黑边/绿边，内部投影保留；内容占比 83%，与系统图标一致 |
| 开机自启动 | AX 打开开关后检查 BTM | `sfltool dumpbtm` 出现 `2.com.rapidtap.mac`，Disposition `[enabled, allowed, notified]`，路径指向 RapidTap.app |
| 开机自启动关闭 | 再次关闭开关 | 副标题回到"登录后不会自动打开"，BTM 中该项变为 `[disabled, allowed, notified]` |
| 自启动状态持久 | 开启后重启应用 | 开关与副标题仍为开启（状态来自系统，而非应用配置） |
| 配置持久化（恢复） | 改完后 `kill -9` 强杀进程，重新启动 | 频率 30 次/秒、幅度 ±8%、按一下切换、坐标抖动关闭全部还原；触发键 Tab 保持不变 |
| 旧配置迁移 | 首次启动读取 UserDefaults 旧键 | 迁移到配置文件并删除旧键，当前值（Tab/6 次/秒/按住模式）完整保留 |

未自动化验证：真机联网游戏内的反作弊表现（无法也不应在测试环境验证）。

## 7. 风险与限制

| 风险 | 说明 | 缓解 |
|------|------|------|
| 权限失效 | ad-hoc 签名下重新编译会改变 cdhash | 默认使用本地稳定签名身份；界面记录并提示「授权已失效」的恢复方式 |
| 触发键全局拦截 | 选 Tab/空格会影响其它应用 | 界面提示建议 F6–F12 |
| 合成事件被忽略 | 密码框等安全输入场景系统会丢弃事件 | 文档说明，属系统保护 |
| 反作弊检测 | 用户态注入无法保证绕过专业反作弊 | 界面 + 文档明确风险，不承诺绕过 |
| 高频资源占用 | 60 次/秒的线程唤醒 | 单线程 + `usleep`，实测 CPU 占用可忽略 |
| 多屏窗口位置 | 曾在非活动屏幕打开 | 按鼠标所在显示器居中 |

## 8. 后续可扩展（当前不做）

- 点击目标从"鼠标左键"扩展到任意鼠标键/键盘键；
- 固定坐标点击与坐标锁定；
- 侧键/组合键触发；
- 多套配置预设与快捷键切换；
- 菜单栏常驻（`LSUIElement`）与开机自启。
