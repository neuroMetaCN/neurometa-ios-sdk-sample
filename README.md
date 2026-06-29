# NeuroMeta SDK 集成测试 Demo (iOS)

本项目是 `NeuroMeta iOS SDK` 的官方集成示例，演示如何在 iOS 应用中接入 EEG 脑电数据采集功能。

## 📋 功能清单

| 功能 | 状态 | 说明 |
|-----|------|------|
| SDK 初始化 | ✅ | License 授权验证 |
| 蓝牙设备扫描 | ✅ | 扫描 EEG Sensor / SmartEEG 设备 |
| 蓝牙设备连接 | ✅ | BLE 连接管理 |
| 实时数据采集 | ✅ | 250Hz 原始采样 → 50Hz 滤波输出 |
| 实时波形显示 | ✅ | SwiftUI Path 绘制 |
| EDF 文件录制 | ✅ | 标准 EDF 格式输出 |
| 设备状态监测 | ✅ | 电池电量 & 佩戴状态 |

---

## 🚀 快速开始

### 1. 添加 SDK 依赖

项目通过 Swift Package 引用本地二进制包 `./binary`，用于对外发布 Demo 时隐藏 SDK 源码。

```swift
// 在 Xcode 中：
// File → Add Package Dependencies → Add Local → 选择 ./binary 目录
```

或直接在 `Package.swift` 中添加本地依赖：

```swift
dependencies: [
    .package(path: "./binary")
]
```

> 如需更新 SDK 二进制：可从 `neuroMetaCN/neurometa-ios-sdk` 的 GitHub Actions 下载 `NeuroMetaSDK-Release-xcframework` artifact，或在 SDK 仓库的 macOS/Xcode 环境执行 `scripts/build_binary_package.sh` 后替换本项目的 `binary/` 目录。

### 2. 配置 Info.plist

```xml
<!-- 蓝牙权限 -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>用于连接并读取 NeuroMeta 脑电设备数据。</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>用于连接并读取 NeuroMeta 脑电设备数据。</string>
```

### 3. 准备 License

开发环境可直接使用内置的开发 License：

```swift
let license = License.createDev(bundleId: Bundle.main.bundleIdentifier ?? "com.neurometa.demo")
```

正式环境从 JSON 文件加载：

```swift
let license = try License.fromBundle(fileName: "neurometa_license.json")
```

License JSON 格式：

```json
{
  "appKey": "your_app_key",
  "packageName": "your.bundle.id",
  "deviceTypes": ["EEG_SENSOR", "SMART_EEG"],
  "features": ["DATA_COLLECT", "EDF_RECORD", "FILTER"],
  "issueDate": "2026-01-30",
  "expireDate": "2027-01-30",
  "signature": "YOUR_LICENSE_SIGNATURE"
}
```

> ⚠️ **注意**: 请联系 NeuroMeta 获取正式授权 License

---

## 📖 SDK 对接流程

```
┌──────────────────────────────────────────────────────────────────┐
│                        SDK 对接流程图                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│   │ 1. 权限配置  │ ──▶ │ 2. SDK初始化 │ ──▶ │ 3. 注册监听器│       │
│   └─────────────┘     └─────────────┘     └─────────────┘       │
│                                                 │                │
│                                                 ▼                │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│   │ 6. 数据处理  │ ◀── │ 5. 数据接收  │ ◀── │ 4. 扫描连接  │       │
│   └─────────────┘     └─────────────┘     └─────────────┘       │
│         │                                                        │
│         ▼                                                        │
│   ┌─────────────┐     ┌─────────────┐                           │
│   │ 7. 波形显示  │     │ 8. EDF录制  │  (可选)                    │
│   └─────────────┘     └─────────────┘                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📝 详细步骤

### Step 1: 权限配置

iOS 蓝牙权限通过 `Info.plist` 声明，系统会在首次使用时自动弹窗请求授权，无需手动申请。

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>用于连接并读取 NeuroMeta 脑电设备数据。</string>
```

---

### Step 2: SDK 初始化

```swift
import NeuroMetaSDK

let sdk = NeuroMeta.shared

func initSDK() {
    do {
        let license = License.createDev(bundleId: Bundle.main.bundleIdentifier ?? "")
        try sdk.initialize(
            license: license,
            config: .development(appKey: "demo_key")
        )
        print("SDK 初始化成功")
        startListening()  // 注册数据监听器
    } catch {
        print("SDK 初始化失败: \(error)")
    }
}
```

---

### Step 3: 注册数据监听器

SDK 提供多种监听器，按需注册：

```swift
func setupDataListeners() {
    let dataCollector = sdk.dataCollector

    // 监听器 1: 实时滤波数据 (推荐用于 UI 显示)
    dataCollector.addRealtimeListener { packet in
        // 已滤波 + 降采样，适合波形绑制
        guard let samples = packet.channelData[0] else { return }
        updateChart(samples)
    }

    // 监听器 2: 未滤波原始数据 (用于调试/科研)
    dataCollector.addUnfilteredListener { packet in
        // 原始 250Hz 数据
        guard let samples = packet.channelData[0] else { return }
        print("原始数据: \(samples.prefix(5))")
    }

    // 监听器 3: 设备状态 (电池 + 佩戴)
    dataCollector.addStatusListener { status in
        updateBatteryUI(status.batteryLevel)
        updateWearUI(status.wear)
    }
}
```

**监听器类型对比：**

| 监听器 | 采样率 | 滤波状态 | 典型用途 |
|-------|-------|---------|---------| 
| `addRealtimeListener` | 50Hz | ✅ 已滤波 | UI 波形显示 |
| `addUnfilteredListener` | 250Hz | ❌ 未滤波 | 调试/科研分析 |
| `addFilteredListener` | 250Hz | ✅ 已滤波 | 特征提取 |
| `addStatusListener` | - | - | 电池/佩戴状态 |

---

### Step 4: 扫描 & 连接设备

```swift
import CoreBluetooth

let centralManager = CBCentralManager(delegate: nil, queue: .main)

// 开始扫描
func startScan() async {
    do {
        let devices = try await sdk.deviceManager.startScan(
            timeout: 8.0,
            onDeviceFound: { device in
                print("发现设备: \(device.displayName)")
            }
        )
        print("扫描完成，共 \(devices.count) 个设备")
    } catch {
        print("扫描失败: \(error)")
    }
}

// 连接设备
func connectDevice(_ device: Device) async {
    do {
        try await sdk.deviceManager.connect(
            deviceId: device.id,
            centralManager: centralManager,
            deviceName: device.name
        )
        print("连接成功，开始接收数据")
        // 数据会自动推送到已注册的监听器
    } catch {
        print("连接失败: \(error)")
    }
}
```

默认扫描过滤已包含 `eeg / sensor / neuro / smarteeg / em09e`。`SmartEEG-XXXX` 与 `EM09E-XXXXXX` 会被识别为 `SMART_EEG`，Demo 无需单独切换模式。

---

### Step 5: 实时数据处理 (滤波)

如需对原始数据进行二次滤波处理：

```swift
let filteredProcessor = sdk.filteredEEGProcessor

// 设置滤波回调
filteredProcessor.onFilteredData = { packet in
    DispatchQueue.main.async {
        // packet.samples: 滤波 + 降采样后的数据
        updateChartData(packet.samples)
    }
}

// 将原始数据送入滤波器
dataCollector.addRealtimeListener { packet in
    if let samples = packet.channelData[0] {
        filteredProcessor.addSamples(samples)
    }
}
```

---

### Step 6: EDF 文件录制

```swift
func startRecording() {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
    let timestamp = dateFormatter.string(from: Date())

    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let path = documentsDir.appendingPathComponent("neurometa/eeg_\(timestamp).edf").path

    let recorder = sdk.edfRecorder
    recorder.onStarted = { path in
        print("录制开始: \(path)")
    }
    recorder.onStopped = { path, count in
        print("录制完成: \(count) 条记录")
    }

    let ok = recorder.startRecording(outputPath: path)
    if ok {
        // 注册原始数据监听器，将数据传给录制器
        dataCollector.addRawListener { packet in
            recorder.onRawData(packet)
        }
    }
}

func stopRecording() {
    _ = sdk.edfRecorder.stopRecording()
}
```

---

### Step 7: 资源释放

在页面销毁时释放资源：

```swift
func cleanup() {
    // 停止录制
    _ = sdk.edfRecorder.stopRecording()

    // 断开设备
    sdk.deviceManager.disconnect()

    // 可选: 销毁 SDK (通常在 App 级别管理)
    // sdk.destroy()
}
```

---

## 📂 项目结构

```
neurometa-ios-demo/
├── NeuroMetaDemo/
│   ├── App/
│   │   └── NeuroMetaDemoApp.swift            ← 应用入口
│   ├── ViewModels/
│   │   └── ViewModels.swift                  ← ViewModel (扫描/设备/录制)
│   ├── Views/
│   │   ├── ContentView.swift                 ← 主界面 (完整示例)
│   │   └── Views.swift                       ← 辅助视图
│   └── Info.plist                            ← 权限配置
├── NeuroMetaDemo.xcodeproj/                  ← Xcode 工程文件
├── binary/
│   ├── NeuroMetaSDK.xcframework/             ← SDK 二进制框架
│   └── Package.swift                         ← Swift Package 配置
└── README.md                                 ← 本文档
```

---

## ⚠️ 常见问题

### Q1: 扫描不到设备？
- 确认蓝牙已开启
- 确认已授予蓝牙权限
- 确认设备已开机且在范围内
- **BLE 不支持模拟器**，必须使用真机调试

### Q2: 连接失败？
- 检查设备是否已被其他手机连接
- 尝试重启设备后重新扫描
- 查看 Xcode Console 中的错误详情

### Q3: 数据不显示？
- 确认设备已正确佩戴（检查 `DeviceStatus.wear`）
- 确认已注册 `addRealtimeListener`
- 确认 UI 更新在主线程 (`DispatchQueue.main.async`)

### Q4: EDF 文件无法打开？
- 确保录制时间 > 1 秒
- 检查文件路径是否可写
- 使用 EDFbrowser 等专业工具打开

---

## 📞 技术支持

- **SDK 版本**: v1.0.0
- **最低 iOS 版本**: iOS 15.0+
- **开发工具**: Xcode 15.0+
- **设备要求**: 真实 iPhone 设备 (BLE 功能)
- **联系方式**: sdk-support@neurometa.com.cn

---

## 📜 License

Copyright © 2026 NeuroMeta. All rights reserved.
