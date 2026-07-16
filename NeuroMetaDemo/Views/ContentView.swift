import Combine
import CoreBluetooth
import NeuroMetaSDK
import SwiftUI
import UIKit

/// 主页面 - 统一仪表盘风格
struct ContentView: View {
    @ObservedObject private var scanVM = ScanViewModel()
    @ObservedObject private var deviceVM = DeviceViewModel()
    @ObservedObject private var recordingVM = RecordingViewModel()
    @State private var centralManager = CBCentralManager(delegate: nil, queue: .main)
    @State private var showingFirmwarePicker = false

    // 状态
    @State private var currentTime: String = ""
    @State private var logs: [LogMessage] = []

    // 定时器
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 颜色常量
    let backgroundDark = Color(red: 0.04, green: 0.04, blue: 0.04) // #0A0A0A
    let surfaceDark = Color(red: 0.1, green: 0.1, blue: 0.1) // #1A1A1A
    let textPrimary = Color.white
    let textSecondary = Color.gray
    let accentGreen = Color(red: 0.0, green: 1.0, blue: 0.0) // #00FF00
    let accentRed = Color(red: 0.9, green: 0.22, blue: 0.21) // #E53935

    private var isConnectionIdle: Bool {
        deviceVM.connectionState == .disconnected
    }

    private var canStartScan: Bool {
        isConnectionIdle && !scanVM.isScanning && !deviceVM.isConnectInFlight
    }

    private var canSelectDevice: Bool {
        isConnectionIdle && !scanVM.isScanning && !deviceVM.isConnectInFlight
    }

    private var connectionStateText: String {
        switch deviceVM.connectionState {
        case .disconnected:
            return "DISCONNECTED"
        case .scanning:
            return "SCANNING"
        case .connecting:
            return "CONNECTING"
        case .connected:
            return "CONNECTED"
        case .disconnecting:
            return "DISCONNECTING"
        case .reconnecting:
            return "RECONNECTING"
        }
    }

    private var connectionStateColor: Color {
        switch deviceVM.connectionState {
        case .connected:
            return accentGreen
        case .disconnected:
            return textSecondary
        case .scanning, .connecting, .disconnecting, .reconnecting:
            return accentRed
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                // Status Cards
                statusCards

                // Devices Section
                devicesSection

                // Realtime EEG Area
                eegSection

                // Main Buttons
                buttonsSection

                // Firmware OTA
                otaSection

                // Console Log
                consoleLogSection

                // EDF Recording Footer
                recordFooter
            }
            .padding()
        }
        .background(backgroundDark.edgesIgnoringSafeArea(.all))
        .preferredColorScheme(.dark)
        .onAppear {
            updateTime()
            initSDK()
            setupLogObservers()
        }
        .onReceive(timer) { _ in
            updateTime()
        }
        .onReceive(deviceVM.$connectionState.dropFirst()) { state in
            switch state {
            case .connected:
                logMessage("Connected to \(deviceVM.currentDevice?.displayName ?? "device")", type: .success)
            case .disconnected:
                logMessage("Disconnected", type: .info)
            case .connecting:
                logMessage("Connecting...", type: .info)
            default:
                break
            }
        }
        .onReceive(deviceVM.$errorMessage.dropFirst().compactMap { $0 }) { message in
            logMessage("Connection failed: \(message)", type: .error)
        }
        .onReceive(deviceVM.$latestRawLog.dropFirst().compactMap { $0 }) { message in
            logMessage(message, type: .info)
        }
        .onReceive(scanVM.$errorMessage.dropFirst().compactMap { $0 }) { message in
            logMessage("Scan failed: \(message)", type: .error)
        }
        .onReceive(deviceVM.$otaStatus.dropFirst()) { status in
            if let error = status.error {
                logMessage("OTA \(status.state): \(error)", type: .error)
            } else {
                logMessage("OTA \(status.state): \(status.progress)%", type: .info)
            }
        }
        .sheet(isPresented: $showingFirmwarePicker) {
            FirmwareDocumentPicker { url in
                deviceVM.selectedFirmwareURL = url
                showingFirmwarePicker = false
                logMessage("Selected firmware: \(url.lastPathComponent)", type: .info)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentTime)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(textPrimary)

            Text("NEUROMETA")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(textPrimary)
                .tracking(2)
                .padding(.top, 4)

            Text("EEG DATA ACQUISITION SDK")
                .font(.system(size: 12))
                .foregroundColor(textSecondary)
                .tracking(1.5)
        }
        .padding(.bottom, 8)
    }

    private var statusCards: some View {
        HStack {
            // BATTERY
            VStack(alignment: .leading) {
                Text("BATTERY")
                    .font(.system(size: 10))
                    .foregroundColor(textSecondary)
                    .tracking(1)

                Text(deviceVM.batteryLevel >= 0 ? "\(deviceVM.batteryLevel)%" : "--")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(batteryColor)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // STATUS
            VStack(alignment: .leading) {
                Text("STATUS")
                    .font(.system(size: 10))
                    .foregroundColor(textSecondary)
                    .tracking(1)

                Text(
                    deviceVM.isWearing == nil
                    ? "--"
                    : (deviceVM.isWearing == true ? "WEARING" : "NOT WORN")
                )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(
                        deviceVM.isWearing == nil
                        ? textSecondary
                        : (deviceVM.isWearing == true ? accentGreen : accentRed)
                    )
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // CONNECTION
            VStack(alignment: .leading) {
                Text("CONNECTION")
                    .font(.system(size: 10))
                    .foregroundColor(textSecondary)
                    .tracking(1)

                Text(connectionStateText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(connectionStateColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(surfaceDark)
        .cornerRadius(8)
        .padding(.bottom, 8)
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DEVICES")
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                    .tracking(1)

                Spacer()

                Text("\(scanVM.devices.count) FOUND")
                    .font(.system(size: 12))
                    .foregroundColor(accentRed)
                    .tracking(1)
            }
            .padding(.bottom, 4)

            if scanVM.isScanning {
                HStack(spacing: 8) {
                    ActivityIndicator(color: UIColor(red: 0.9, green: 0.22, blue: 0.21, alpha: 1.0))
                    Text("SCANNING...")
                        .font(.system(size: 11))
                        .foregroundColor(textSecondary)
                        .tracking(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            if !scanVM.devices.isEmpty {
                ForEach(scanVM.devices) { device in
                    DeviceItemView(device: device, isConnected: deviceVM.currentDevice?.id == device.id, accentGreen: accentGreen)
                        .onTapGesture {
                            guard canSelectDevice else { return }
                            if deviceVM.connect(device: device, centralManager: centralManager) {
                                logMessage("Connecting to \(device.id)...", type: .info)
                            }
                        }
                        .opacity(canSelectDevice ? 1.0 : 0.45)
                }
            } else {
                if !scanVM.isScanning {
                 Text("NO DEVICES")
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var eegSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("REALTIME EEG")
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                    .tracking(1)

                Spacer()

                Text("-- Hz LIVE") // 真实环境需要接入 deviceVM.samplingRate
                    .font(.system(size: 12))
                    .foregroundColor(accentGreen)
                    .tracking(0.5)
            }

            Text("CH1 · FP1")
                .font(.system(size: 12))
                .foregroundColor(textSecondary)
                .padding(.bottom, 4)

            // 实时波形图
            CyberWaveformView(values: deviceVM.realtimeValues, accentColor: accentGreen)
                .frame(height: 200)
                .background(surfaceDark)
                .cornerRadius(4)
        }
        .padding(.bottom, 8)
    }

    private var buttonsSection: some View {
        VStack(spacing: 16) {
            if deviceVM.connectionState != .connected {
                Button(action: {
                    guard canStartScan else { return }
                    logMessage("Scanning for devices...", type: .info)
                    scanVM.scan()
                }) {
                    Text("SCAN DEVICES")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(canStartScan ? accentRed : textSecondary.opacity(0.4))
                        .cornerRadius(4)
                }
                .disabled(!canStartScan)
            } else {
                Button(action: {
                    logMessage("Disconnecting...", type: .info)
                    deviceVM.disconnect()
                }) {
                    Text("DISCONNECT")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(accentRed)
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(accentRed, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var otaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FIRMWARE OTA")
                .font(.system(size: 12))
                .foregroundColor(textSecondary)
                .tracking(1)

            Toggle(isOn: $deviceVM.otaAwaitAck) {
                Text("Await device ACK")
                    .font(.system(size: 13))
                    .foregroundColor(textSecondary)
            }

            Text(deviceVM.selectedFirmwareURL?.lastPathComponent ?? "No firmware selected")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(textSecondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button(action: { showingFirmwarePicker = true }) {
                    Text("Select Firmware")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(textSecondary, lineWidth: 1)
                        )
                }

                Button(action: {
                    if let url = deviceVM.selectedFirmwareURL {
                        deviceVM.startFirmwareUpgrade(fileURL: url)
                    }
                }) {
                    Text("Start OTA")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(deviceVM.selectedFirmwareURL == nil ? textSecondary.opacity(0.4) : accentRed)
                        .cornerRadius(4)
                }
                .disabled(deviceVM.selectedFirmwareURL == nil)
            }

            Button(action: { deviceVM.cancelFirmwareUpgrade() }) {
                Text("Cancel OTA")
                    .font(.system(size: 13))
                    .foregroundColor(accentRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accentRed, lineWidth: 1)
                    )
            }

            Text("\(deviceVM.otaStatus.state) \(deviceVM.otaStatus.progress)% (\(deviceVM.otaStatus.sentChunks)/\(deviceVM.otaStatus.totalChunks))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(deviceVM.otaStatus.error == nil ? accentGreen : accentRed)
        }
        .padding(16)
        .background(surfaceDark)
        .cornerRadius(8)
        .padding(.bottom, 8)
    }

    private var consoleLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CONSOLE LOG")
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                    .tracking(1)

                Spacer()

                Button(action: { logs.removeAll() }) {
                    Text("CLEAR")
                        .font(.system(size: 12))
                        .foregroundColor(accentRed)
                        .tracking(1)
                        .padding(4)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { log in
                        Text(log.formattedText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(log.color)
                            .lineSpacing(4)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .background(surfaceDark)
            .cornerRadius(4)
        }
        .padding(.bottom, 16)
    }

    private var recordFooter: some View {
        VStack {
            if deviceVM.connectionState == .connected {
                Button(action: {
                    if recordingVM.isRecording {
                        recordingVM.stopRecording()
                        logMessage("Recording stopped", type: .info)
                    } else {
                        recordingVM.startRecording()
                        logMessage("Recording started", type: .success)
                    }
                }) {
                    Text(recordingVM.isRecording ? "Stop Recording" : "Record EDF")
                        .font(.system(size: 14))
                        .foregroundColor(recordingVM.isRecording ? accentRed : textSecondary)
                }
                .padding(16)

                if recordingVM.isRecording {
                    Text("Recording: \(recordingVM.recordingDuration)s")
                        .font(.system(size: 12))
                        .foregroundColor(accentGreen)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var batteryColor: Color {
        if deviceVM.batteryLevel > 50 { return accentGreen }
        if deviceVM.batteryLevel > 20 { return Color.orange }
        if deviceVM.batteryLevel >= 0 { return accentRed }
        return textSecondary
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        currentTime = formatter.string(from: Date())
    }

    private func initSDK() {
        logMessage("Initializing SDK...", type: .info)
        do {
            let sdk = NeuroMeta.shared
            let license = License.createDev(bundleId: Bundle.main.bundleIdentifier ?? "com.neurometa.demo")
            try sdk.initialize(license: license, config: .development(appKey: "demo_key"))
            logMessage("SDK initialized successfully", type: .success)
        } catch {
            logMessage("SDK init failed: \(error)", type: .error)
        }
    }

    private func logMessage(_ text: String, type: LogType) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let msg = LogMessage(timestamp: timestamp, text: text, type: type)
        // 确保在主线程更新 UI
        DispatchQueue.main.async {
            self.logs.append(msg)
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
    }

    private func setupLogObservers() {}
}

// MARK: - Models

struct LogMessage: Identifiable {
    let id = UUID()
    let timestamp: String
    let text: String
    let type: LogType

    var formattedText: String {
        return "[\(timestamp)] \(text)"
    }

    var color: Color {
        switch type {
        case .info: return Color.gray
        case .success: return Color(red: 0.0, green: 1.0, blue: 0.0) // #00FF00
        case .error: return Color(red: 0.9, green: 0.22, blue: 0.21) // #E53935
        }
    }
}

enum LogType {
    case info, success, error
}

// MARK: - Components

struct DeviceItemView: View {
    let device: Device
    let isConnected: Bool
    let accentGreen: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isConnected ? accentGreen : .white)
                Text(device.id)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            Spacer()
            if isConnected {
                Text("CONNECTED")
                    .font(.system(size: 10))
                    .foregroundColor(accentGreen)
            } else {
                Text("RSSI: \(device.rssi)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .cornerRadius(4)
    }
}

struct ActivityIndicator: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = color
        view.hidesWhenStopped = false
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        uiView.color = color
        uiView.startAnimating()
    }
}

struct FirmwareDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct CyberWaveformView: View {
    let values: [Double]
    let accentColor: Color
    private let maxDisplayPoints = 250      // 5s @ 50Hz
    private let displayRange: Double = 100.0  // 与 Android chart 的 Y 轴范围一致 (-100~100)

    var body: some View {
        GeometryReader { geo in
            let displayValues = Array(values.suffix(maxDisplayPoints))
            if displayValues.count > 1 {
                Path { path in
                    let w = geo.size.width
                    let h = geo.size.height
                    let midY = h / 2.0
                    // 固定 250 点横轴：前 5 秒逐步铺满，5 秒后滑动窗口
                    let step = w / CGFloat(max(maxDisplayPoints - 1, 1))
                    let scale = (h * 0.45) / displayRange

                    let first = min(max(displayValues[0], -displayRange), displayRange)
                    path.move(to: CGPoint(x: 0, y: midY - first * scale))
                    for i in 1..<displayValues.count {
                        let v = min(max(displayValues[i], -displayRange), displayRange)
                        path.addLine(to: CGPoint(x: CGFloat(i) * step, y: midY - v * scale))
                    }
                }
                .stroke(accentColor, lineWidth: 1.5)
            } else {
                // 网格线背景
                VStack {
                    Spacer()
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                    }
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    Spacer()
                }
            }
        }
        .clipShape(Rectangle())
    }
}

// 供预览使用
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
