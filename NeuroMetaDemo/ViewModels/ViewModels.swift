import Combine
import CoreBluetooth
import Foundation
import SwiftUI
import NeuroMetaSDK

// MARK: - ViewModels

/// 扫描页面 ViewModel
@MainActor
final class ScanViewModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    private let sdk = NeuroMetaSDK.shared

    private func upsertDevice(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    func scan() {
        guard !isScanning else { return }

        guard sdk.isInitialized else {
            errorMessage = "SDK 未初始化"
            return
        }
        isScanning = true
        devices.removeAll()
        errorMessage = nil

        let deviceManager = sdk.deviceManager
        Task {
            do {
                let found = try await deviceManager.startScan(
                    timeout: 8.0,
                    onDeviceFound: { [weak self] device in
                        Task { @MainActor [weak self] in
                            self?.upsertDevice(device)
                        }
                    }
                )
                for device in found {
                    self.upsertDevice(device)
                }
                self.isScanning = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isScanning = false
            }
        }
    }
}

/// 设备 ViewModel
@MainActor
final class DeviceViewModel: ObservableObject {
    private static let minOtaBatteryLevel = 30

    @Published var connectionState: ConnectionState
    @Published var currentDevice: Device?
    @Published var realtimeValues: [Double] = []
    @Published var batteryLevel: Int = -1
    @Published var isWearing: Bool?
    @Published var filterPreset: String = "default"
    @Published var packetCount: Int = 0
    @Published var errorMessage: String?
    @Published var latestRawLog: String?
    @Published var otaStatus = SmartEEGOtaStatus()
    @Published var otaAwaitAck = false
    @Published var selectedFirmwareURL: URL?
    @Published private(set) var isConnectInFlight = false

    private let sdk = NeuroMetaSDK.shared
    private var realtimeListenerId: UUID?
    private var statusListenerId: UUID?
    private var unfilteredListenerId: UUID?
    private var otaCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let maxPoints = 250

    private var filteredProcessor: FilteredEEGProcessor {
        sdk.filteredEEGProcessor
    }

    init() {
        connectionState = sdk.deviceManager.connectionState
        observeConnectionState()
        observeCurrentDevice()
        observeOtaStatus()
    }

    @discardableResult
    func connect(device: Device, centralManager: CBCentralManager) -> Bool {
        guard sdk.isInitialized else { return false }
        let sdkState = sdk.deviceManager.connectionState
        guard !isConnectInFlight,
              connectionState.isDisconnected,
              sdkState.isDisconnected else {
            return false
        }
        errorMessage = nil
        isConnectInFlight = true
        currentDevice = device

        Task {
            do {
                try await sdk.deviceManager.connect(
                    deviceId: device.id,
                    centralManager: centralManager,
                    deviceName: device.name
                )
                await MainActor.run {
                    self.isConnectInFlight = false
                    self.startListening()
                }
            } catch {
                await MainActor.run {
                    self.isConnectInFlight = false
                    if self.sdk.deviceManager.connectionState.isDisconnected {
                        self.currentDevice = nil
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        return true
    }

    func disconnect() {
        stopListening()
        sdk.deviceManager.disconnect()
        clearDisconnectedDisplayState()
    }

    private func clearDisconnectedDisplayState() {
        currentDevice = nil
        realtimeValues.removeAll()
        batteryLevel = -1
        isWearing = nil
    }

    func startListening() {
        guard sdk.isInitialized else { return }
        let started = sdk.deviceManager.startListening()
        guard started else { return }

        // Android demo 的 DataProcessor 是 no-op，这里关闭 DataCollector 额外滤波以对齐链路
        sdk.dataCollector.setFilterConfig(.noFilter())

        filteredProcessor.reset()
        filteredProcessor.onFilteredData = { [weak self] packet in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.realtimeValues.append(contentsOf: packet.samples)
                if self.realtimeValues.count > self.maxPoints {
                    self.realtimeValues.removeFirst(self.realtimeValues.count - self.maxPoints)
                }
            }
        }

        realtimeListenerId = sdk.dataCollector.addRealtimeListener { [weak self] packet in
            if let samples = packet.channelData[0], !samples.isEmpty {
                self?.filteredProcessor.addSamples(samples)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.packetCount += 1
                self.batteryLevel = packet.batteryLevel
                self.isWearing = packet.wear
            }
        }

        statusListenerId = sdk.dataCollector.addStatusListener { [weak self] status in
            DispatchQueue.main.async {
                self?.batteryLevel = status.batteryLevel
                self?.isWearing = status.wear
            }
        }

        unfilteredListenerId = sdk.dataCollector.addUnfilteredListener { [weak self] packet in
            guard let samples = packet.channelData[0], !samples.isEmpty else { return }
            let firstSamples = samples.prefix(5).map { String(format: "%.1f", $0) }.joined(separator: ",")
            let message = "[RAW] seq=\(packet.sequenceNumber), ch=0, data=\(firstSamples)"
            DispatchQueue.main.async {
                self?.latestRawLog = message
            }
        }
    }

    func stopListening() {
        sdk.deviceManager.stopListening()
        if let id = realtimeListenerId { sdk.dataCollector.removeListener(id: id) }
        if let id = statusListenerId { sdk.dataCollector.removeListener(id: id) }
        if let id = unfilteredListenerId { sdk.dataCollector.removeListener(id: id) }
        realtimeListenerId = nil
        statusListenerId = nil
        unfilteredListenerId = nil
        filteredProcessor.onFilteredData = nil
        filteredProcessor.reset()
    }

    func setFilter(preset: String) {
        filterPreset = preset
        let config: FilterConfig
        switch preset {
        case "china": config = .china()
        case "usa": config = .usa()
        case "none": config = .noFilter()
        default: config = .default()
        }
        sdk.dataCollector.setFilterConfig(config)
    }

    func observeConnectionState() {
        sdk.deviceManager.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.connectionState = state
                if state == .connected {
                    self.currentDevice = self.sdk.deviceManager.currentDevice
                } else if state == .disconnected {
                    self.stopListening()
                    self.clearDisconnectedDisplayState()
                }
            }
            .store(in: &cancellables)
    }

    func observeCurrentDevice() {
        sdk.deviceManager.currentDevicePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                self?.currentDevice = device
            }
            .store(in: &cancellables)
    }

    func observeOtaStatus() {
        otaCancellable = sdk.deviceManager.smartEegOtaStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.otaStatus = status
            }
    }

    func startFirmwareUpgrade(fileURL: URL) {
        guard batteryLevel >= 0 else {
            errorMessage = "Battery level unavailable; wait for battery data before OTA"
            return
        }
        guard batteryLevel >= Self.minOtaBatteryLevel else {
            errorMessage = "Battery must be at least \(Self.minOtaBatteryLevel)% for OTA; current=\(batteryLevel)%"
            return
        }
        let awaitAck = otaAwaitAck
        Task {
            let options = SmartEEGOtaOptions(awaitAck: awaitAck)
            _ = await sdk.deviceManager.startSmartEegOta(fileURL: fileURL, options: options)
        }
    }

    func cancelFirmwareUpgrade() {
        _ = sdk.deviceManager.cancelSmartEegOta()
    }

    func refreshCurrentDevice() {
        currentDevice = sdk.deviceManager.currentDevice
    }

    @discardableResult
    func queryFirmwareVersion() -> Bool {
        sdk.deviceManager.querySmartEegFirmwareVersion()
    }
}

/// 录制 ViewModel
@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var filePath: String?
    @Published var recordCount: Int = 0

    private let sdk = NeuroMetaSDK.shared
    private var rawListenerId: UUID?
    private var timer: Timer?

    func startRecording() {
        guard sdk.isInitialized else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = documentsDir.appendingPathComponent("neurometa/eeg_\(timestamp).edf").path

        let recorder = sdk.edfRecorder
        recorder.onStarted = { [weak self] path in
            DispatchQueue.main.async { self?.filePath = path }
        }
        recorder.onStopped = { [weak self] _, count in
            DispatchQueue.main.async { self?.recordCount = count }
        }

        let ok = recorder.startRecording(outputPath: path)
        if ok {
            rawListenerId = sdk.dataCollector.addRawListener { [weak self] packet in
                self?.sdk.edfRecorder.onRawData(packet)
            }
            isRecording = true
            recordingDuration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingDuration += 1
                }
            }
        }
    }

    func stopRecording() {
        if let id = rawListenerId { sdk.dataCollector.removeListener(id: id) }
        rawListenerId = nil
        _ = sdk.edfRecorder.stopRecording()
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
}
