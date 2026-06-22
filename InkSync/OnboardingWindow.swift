import SwiftUI
import EventKit

struct OnboardingView: View {
    @ObservedObject var appConfig: AppConfig
    @ObservedObject var mappingManager: MappingManager
    let apiClient: APIClient
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var apiVerified = false
    @State private var isVerifying = false
    @State private var verifyError: String?
    @State private var selectedStrategy: ConflictStrategy = .timestampPriority
    @State private var tempMappings: [String: [String]] = [:]

    private let steps = ["API 配置", "冲突策略", "设备映射", "完成"]

    var body: some View {
        VStack(spacing: 0) {
            progressIndicator
            Divider()
            stepContent
            Divider()
            navigationButtons
        }
        .frame(width: 480, height: 480)
    }

    private var progressIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("\(step + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        )

                    Text(steps[step])
                        .font(.caption2)
                        .foregroundStyle(step <= currentStep ? .primary : .secondary)
                }

                if step < 3 {
                    Rectangle()
                        .fill(step < currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 18)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            apiConfigStep
        case 1:
            conflictStrategyStep
        case 2:
            deviceMappingStep
        case 3:
            completionStep
        default:
            EmptyView()
        }
    }

    private var apiConfigStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("云端账户配置")
                    .font(.headline)

                Text("请输入您的 API Key 以连接到墨水屏云端服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("输入 API Key", text: $apiKey)
                    .textContentType(nil)
                    .textFieldStyle(.roundedBorder)

                if let error = verifyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("验证连接") {
                    verifyApiKey()
                }
                .disabled(apiKey.isEmpty || isVerifying)
            }

            if isVerifying {
                HStack {
                    ProgressView()
                    Text("验证中...")
                        .foregroundStyle(.secondary)
                }
            }

            if apiVerified {
                Label("验证成功", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(24)
    }

    private var conflictStrategyStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("冲突解决策略")
                    .font(.headline)

                Text("当本地和远程同时修改同一事项时的解决方式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(ConflictStrategy.allCases, id: \.self) { strategy in
                    Button {
                        selectedStrategy = strategy
                    } label: {
                        HStack {
                            Image(systemName: selectedStrategy == strategy ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selectedStrategy == strategy ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(strategy.displayName)
                                    .foregroundStyle(.primary)
                                Text(strategyDescription(strategy))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(selectedStrategy == strategy ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedStrategy == strategy ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var deviceMappingStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("设备与列表映射")
                    .font(.headline)

                Text("为每台设备分配要同步的 Reminders 列表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(mappingManager.devices) { device in
                        deviceMappingRow(for: device)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            Task {
                await mappingManager.loadDevices()
            }
        }
    }

    private func deviceMappingRow(for device: Device) -> some View {
        let assigned = tempMappings[device.id] ?? []
        let availableForDevice = mappingManager.availableLists.filter { list in
            let currentDevice = mappingManager.config.device(for: list.calendarIdentifier)
            return currentDevice == nil || currentDevice == device.id
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(device.alias)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            FlowLayout(spacing: 4) {
                ForEach(assigned, id: \.self) { listId in
                    if let list = mappingManager.availableLists.first(where: { $0.calendarIdentifier == listId }) {
                        HStack(spacing: 4) {
                            Text(list.title)
                                .font(.caption)
                            Button {
                                tempMappings[device.id]?.removeAll { $0 == listId }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                    }
                }

                Menu {
                    ForEach(availableForDevice, id: \.calendarIdentifier) { list in
                        Button(list.title) {
                            addListToDevice(list.calendarIdentifier, deviceId: device.id)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var completionStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("设置完成")
                .font(.title.weight(.semibold))

            Text("InkSync 将开始同步您的提醒事项到墨水屏设备")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("点击下方按钮隐藏到菜单栏")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("上一步") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
            }

            Spacer()

            if currentStep < 3 {
                Button("下一步") {
                    if currentStep == 0 {
                        appConfig.apiKey = apiKey
                    } else if currentStep == 1 {
                        appConfig.conflictStrategy = selectedStrategy
                    } else if currentStep == 2 {
                        applyTempMappings()
                    }
                    withAnimation {
                        currentStep += 1
                    }
                }
                .disabled(currentStep == 0 && !apiVerified)
            } else {
                Button("隐藏到菜单栏") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func verifyApiKey() {
        isVerifying = true
        verifyError = nil

        Task {
            let testClient = RealAPIClient(apiKey: apiKey)
            do {
                _ = try await testClient.fetchDevices()
                await MainActor.run {
                    apiVerified = true
                    isVerifying = false
                }
            } catch let error as APIError {
                await MainActor.run {
                    verifyError = error.errorDescription ?? "验证失败"
                    isVerifying = false
                }
            } catch {
                await MainActor.run {
                    verifyError = "验证失败: \(error.localizedDescription)"
                    isVerifying = false
                }
            }
        }
    }

    private func applyTempMappings() {
        for (deviceId, listIds) in tempMappings {
            for listId in listIds {
                mappingManager.assignList(listId, to: deviceId)
            }
        }
    }

    private func addListToDevice(_ listId: String, deviceId: String) {
        if tempMappings[deviceId] == nil {
            tempMappings[deviceId] = []
        }
        if !tempMappings[deviceId]!.contains(listId) {
            tempMappings[deviceId]!.append(listId)
        }
    }

    private func completeOnboarding() {
        appConfig.hasCompletedOnboarding = true
        mappingManager.saveConfig()
        onComplete()
    }

    private func strategyDescription(_ strategy: ConflictStrategy) -> String {
        switch strategy {
        case .timestampPriority:
            return "以最后修改时间为准"
        case .applePriority:
            return "始终以 Apple Reminders 为准"
        case .devicePriority:
            return "始终以墨水屏设备为准"
        }
    }
}

final class OnboardingWindowController: NSWindowController {
    convenience init(
        appConfig: AppConfig,
        mappingManager: MappingManager,
        apiClient: APIClient,
        onComplete: @escaping () -> Void
    ) {
        let onboardingView = OnboardingView(
            appConfig: appConfig,
            mappingManager: mappingManager,
            apiClient: apiClient,
            onComplete: onComplete
        )

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "InkSync 设置向导"
        window.styleMask = [.titled, .closable, .resizable]
        window.minSize = NSSize(width: 480, height: 480)
        window.maxSize = NSSize(width: 480, height: 480)
        window.center()

        self.init(window: window)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}