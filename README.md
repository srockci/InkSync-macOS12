# InkSync-macOS12

macOS 12 (Monterey) 兼容版 [InkSync](https://github.com/srockci/InkSync) — 将 Apple Reminders 同步到墨水屏云端（zectrix-s3-epaper）。

> 这是 [srockci/InkSync](https://github.com/srockci/InkSync) 的 macOS 12 兼容分支。所有功能与上游保持一致，唯一改动是 **最低支持 macOS 12.0**，而非 13.0。

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — 禁止任何商业用途。如需商用请联系作者获取授权。

## 与上游的区别

唯一源代码改动：`FlowLayout.swift` 用 `LazyVGrid`（自适应列宽）重写，替代上游的 `Layout` 协议实现（macOS 13+）。

| | 上游 InkSync | 本仓库 InkSync12 |
|---|---|---|
| 最低 macOS | 13.0 (Ventura) | 12.0 (Monterey) |
| FlowLayout | `Layout` 协议，紧凑流动 | `LazyVGrid` 自适应列，按列对齐换行 |
| 周期备忘、云同步、补发、API Key 加密等 | ✅ | ✅（完全一致）|

UI 上对**小标签场景**（设备列表映射、设置页标签）几乎看不出差别。如果你在 Ventura 以下使用 Mac，请用本仓库。

## 功能特性

完整功能列表请参考 [srockci/InkSync#readme](https://github.com/srockci/InkSync#readme)。

简要：
- **菜单栏常驻**，轻量不打扰
- **双向同步**：Apple Reminders ↔ 墨水屏云端
- **设备-列表映射**，灵活控制每个设备的同步范围
- **冲突解决策略**：时间戳优先 / Apple 优先 / 设备优先
- **周期备忘录**：按天/周/月/工作日/自定义间隔自动生成 Reminders，**支持休眠/关机后唤醒自动补发**（最多 7 天）
- **生成日志**：记录每次触发的成功/失败状态，支持 CSV 导出，补发条目单独标识
- **失败通知中心**
- **首次启动引导**
- **关闭窗口后自动从 Dock 隐藏**
- **菜单高度自适应内容**

## 同步流程

```
拉取（先状态同步）  →  重新拉取本地  →  推送（后条目同步）
  云端→本地完成状态     拉取后最新状态     本地→云端条目
```

### 推送匹配优先级

1. **cloudId 精确匹配**：本地有 `cloudId` 且云端存在 → 更新
2. **标题匹配收养**：本地无 `cloudId` 但云端有同名条目 → 收养（防重复）
3. **创建新条目**：都没有 → 创建

每条云端条目在单次同步中只被收养一次，避免 cloudId 映射互相覆盖。

### 拉取匹配

- 找到本地匹配项时回填 `cloudId`，下次推送走精确匹配
- 云端有完成状态但本地没有 → 标记本地完成
- 拉取不创建已完成条目到本地

## 周期备忘录

支持：每天 / 每周（多选星期）/ 每月（多选日期，支持最后一天）/ 工作日 / 自定义（分钟/小时/天/周/月）。

- 触发时间：小时 + 分钟
- 生效范围：开始日期 + 可选结束日期
- 高级选项：同名条目处理（跳过/覆盖/追加序号）、自动完成、标签
- **容错**：5 分钟容错窗口，**休眠/关机后唤醒时自动补发**（默认 72 小时窗口，可设置 0–168h）
- 触发流程：写入 Apple Reminders → 现有同步引擎自动推送到云端

## 云端 API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/devices` | 设备列表 |
| GET | `/todos?deviceId=xxx` | 设备下的待办 |
| POST | `/todos` | 新建待办 |
| PUT | `/todos/{id}` | 更新待办 |
| PUT | `/todos/{id}/complete` | 标记完成 |
| PUT | `/todos/{id}/incomplete` | 取消完成 |
| DELETE | `/todos/{id}` | 删除待办 |

请求头：`X-API-Key: <your_key>`

## 配置

- API 地址：设置 → 云端账户
- API Key：同上（ChaChaPoly 对称加密存储）
- 冲突策略：设置 → 同步策略
- 设备映射：设置 → 设备映射
- 周期规则：菜单栏 → 周期备忘
- 补发窗口：设置 → 周期备忘（0 关闭，默认 72 小时，上限 168 小时）

## 权限

- Reminders（EventKit）：用于读写本地待办
- 通知：用于同步完成/失败/冲突/补发提示

## 安全

- API Key 使用 ChaChaPoly 对称加密存储于 `~/Library/Application Support/InkSync/secrets.dat`
- 加密密钥通过 HKDF 从 **Bundle ID** 派生
- 本仓库 Bundle ID 为 `com.inksync.app.mac12`，与上游（`com.inksync.app`）完全隔离
- 不用 Keychain，避免未签名应用的反复授权弹窗

## 开发与构建

```bash
xcodebuild -project InkSync12.xcodeproj -scheme InkSync12 -configuration Release build
```

或在 Xcode 中打开 `InkSync12.xcodeproj`。

**最低支持：macOS 12.0**

构建产物：
```
~/Library/Developer/Xcode/DerivedData/InkSync12-*/Build/Products/Release/InkSync12.app
```

复制到 `/Applications`：

```bash
rm -rf /Applications/InkSync12.app
cp -R ~/Library/Developer/Xcode/DerivedData/InkSync12-*/Build/Products/Release/InkSync12.app /Applications/
xattr -dr com.apple.quarantine /Applications/InkSync12.app
```

首次启动如果弹「无法验证开发者」，右键 → 打开 → 弹出框里再点「打开」一次。

## 文件结构

```
InkSync12/
├── InkSync12.xcodeproj
├── InkSync/
│   ├── InkSyncApp.swift           # App 入口、AppDelegate
│   ├── StatusBarController.swift  # 菜单栏
│   ├── MenuPopoverView.swift      # 弹窗
│   ├── SettingsWindow.swift       # 设置
│   ├── OnboardingWindow.swift     # 引导
│   ├── SyncEngine.swift           # 同步核心
│   ├── SyncLogWindow.swift        # 同步日志窗口
│   ├── SyncLogStore.swift         # 日志存储
│   ├── SyncModels.swift           # 同步日志模型
│   ├── EventKitManager.swift      # Reminders 增删改查
│   ├── EKReminder+TodoItem.swift  # EKReminder → TodoItem 转换
│   ├── EventKitError.swift        # EventKit 错误类型
│   ├── APIClient.swift            # API 协议
│   ├── RealAPIClient.swift        # 真实 API
│   ├── SecureStorage.swift        # ChaChaPoly 加密存储
│   ├── CloudIdStore.swift         # 本地→云端 ID 映射
│   ├── MappingManager.swift       # 设备-列表映射管理
│   ├── MappingConfig.swift        # 映射模型
│   ├── MappingConfigView.swift    # 映射设置 UI
│   ├── AppConfig.swift            # 用户偏好设置
│   ├── TodoItem.swift             # TodoItem 模型
│   ├── Models.swift               # 同步状态等模型
│   ├── FlowLayout.swift           # ⚠️ LazyVGrid 实现（macOS 12 兼容）
│   ├── SystemSettings.swift       # 系统设置快捷入口
│   ├── NotificationManager.swift  # 系统通知
│   └── Recurring/                 # 周期备忘录
│       ├── RecurringReminder.swift
│       ├── RecurrenceRule.swift
│       ├── GenerationLog.swift
│       ├── RecurringReminderStore.swift
│       ├── RecurringGenerationLogger.swift
│       ├── RecurrenceScheduler.swift
│       ├── RecurringEngine.swift
│       ├── RecurringRemindersView.swift
│       ├── RecurringReminderEditView.swift
│       ├── RecurringLogView.swift
│       └── RecurringWindowControllers.swift
├── Assets.xcassets/               # 应用图标（根目录）
└── LICENSE
```
