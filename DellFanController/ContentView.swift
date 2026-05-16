import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var ipmiManager = IPMIManager()
    @State private var globalSpeed: Double = 20
    @State private var fanSpeeds: [Double] = Array(repeating: 20, count: 6)

    var body: some View {
        #if os(iOS)
        IOSRootView(
            ipmiManager: ipmiManager,
            globalSpeed: $globalSpeed,
            fanSpeeds: $fanSpeeds
        )
        #else
        MacRootView(
            ipmiManager: ipmiManager,
            globalSpeed: $globalSpeed,
            fanSpeeds: $fanSpeeds
        )
        .frame(minWidth: 1000, minHeight: 600)
        #endif
    }
}

#if os(iOS)
private struct IOSRootView: View {
    @ObservedObject var ipmiManager: IPMIManager
    @Binding var globalSpeed: Double
    @Binding var fanSpeeds: [Double]

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        GeometryReader { geo in
            let useSplitLayout = isPad && geo.size.width > geo.size.height

            NavigationStack {
                Group {
                    if useSplitLayout {
                        HStack(spacing: 0) {
                            IOSControlPanel(
                                ipmiManager: ipmiManager,
                                globalSpeed: $globalSpeed,
                                fanSpeeds: $fanSpeeds
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Divider()

                            IOSSensorPanel(ipmiManager: ipmiManager)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        List {
                            IOSControlSections(
                                ipmiManager: ipmiManager,
                                globalSpeed: $globalSpeed,
                                fanSpeeds: $fanSpeeds
                            )

                            Section {
                                IOSSensorListContent(ipmiManager: ipmiManager)
                            } header: {
                                IOSSensorHeader(ipmiManager: ipmiManager)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("Dell Fan Controller")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
        }
        .onAppear {
            ipmiManager.fetchSensors()
        }
    }
}

private struct IOSControlPanel: View {
    @ObservedObject var ipmiManager: IPMIManager
    @Binding var globalSpeed: Double
    @Binding var fanSpeeds: [Double]

    var body: some View {
        Form {
            IOSControlSections(
                ipmiManager: ipmiManager,
                globalSpeed: $globalSpeed,
                fanSpeeds: $fanSpeeds
            )
        }
    }
}

private struct IOSControlSections: View {
    @ObservedObject var ipmiManager: IPMIManager
    @Binding var globalSpeed: Double
    @Binding var fanSpeeds: [Double]

    var body: some View {
        Section(header: Text("iDRAC 连接设置").font(.headline)) {
            TextField("IP 地址", text: $ipmiManager.ip)
            TextField("用户名", text: $ipmiManager.user)
            SecureField("密码", text: $ipmiManager.password)
        }
        .padding(.bottom, 10)

        Section(header: Text("全局控制").font(.headline)) {
            HStack {
                Text("所有风扇:")
                TextField("", value: $globalSpeed, formatter: NumberFormatter())
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                Text("%")

                Slider(value: $globalSpeed, in: 0...100, step: 1)

                Button("应用") {
                    ipmiManager.setAllFans(speed: Int(globalSpeed))
                    for i in 0..<6 {
                        fanSpeeds[i] = globalSpeed
                    }
                }
            }
            Button("恢复自动温控") {
                ipmiManager.resetToAuto()
            }
            .foregroundColor(.red)
        }
        .padding(.bottom, 10)

        Section(header: Text("独立风扇控制").font(.headline)) {
            ForEach(0..<6, id: \.self) { index in
                HStack {
                    Text("Fan \(index + 1):")
                        .frame(width: 50, alignment: .leading)

                    TextField("", value: $fanSpeeds[index], formatter: NumberFormatter())
                        .frame(width: 40)
                        .textFieldStyle(.roundedBorder)
                    Text("%")

                    Slider(value: $fanSpeeds[index], in: 0...100, step: 1)

                    Button("应用") {
                        ipmiManager.setFan(index: index, speed: Int(fanSpeeds[index]))
                    }
                }
            }
        }
    }
}

private struct IOSSensorPanel: View {
    @ObservedObject var ipmiManager: IPMIManager

    var body: some View {
        VStack {
            IOSSensorHeader(ipmiManager: ipmiManager)
                .padding([.top, .horizontal])

            List {
                IOSSensorListContent(ipmiManager: ipmiManager)
            }
            .listStyle(.plain)
        }
    }
}

private struct IOSSensorHeader: View {
    @ObservedObject var ipmiManager: IPMIManager

    var body: some View {
        HStack {
            Text("传感器状态")
                .font(.headline)
            Spacer()
            Button(action: {
                ipmiManager.fetchSensors()
            }) {
                if ipmiManager.isFetching {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Text("刷新状态")
                }
            }
            .disabled(ipmiManager.isFetching)
        }
    }
}

private struct IOSSensorListContent: View {
    @ObservedObject var ipmiManager: IPMIManager

    var body: some View {
        if ipmiManager.sensors.isEmpty {
            Text(ipmiManager.isFetching ? "正在获取传感器数据..." : "暂无传感器数据")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
        } else {
            ForEach(ipmiManager.sensors.indices, id: \.self) { idx in
                let sensor = ipmiManager.sensors[idx]
                VStack(alignment: .leading, spacing: 4) {
                    Text(sensor.name).font(.headline)
                    HStack(spacing: 10) {
                        Text("当前值: \(sensor.value) \(sensor.unit)")
                        Text("状态: \(sensor.status)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    Text("阈值（严重下限/警告下限/警告上限/严重上限）：\(sensor.lc) / \(sensor.lnc) / \(sensor.unc) / \(sensor.uc)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
#endif

#if os(macOS)
private struct MacRootView: View {
    @ObservedObject var ipmiManager: IPMIManager
    @Binding var globalSpeed: Double
    @Binding var fanSpeeds: [Double]

    var body: some View {
        HStack(spacing: 0) {
            MacControlPanel(
                ipmiManager: ipmiManager,
                globalSpeed: $globalSpeed,
                fanSpeeds: $fanSpeeds
            )
            Divider()
            MacSensorPanel(ipmiManager: ipmiManager)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            ipmiManager.fetchSensors()
        }
    }
}

private struct MacControlPanel: View {
    @ObservedObject var ipmiManager: IPMIManager
    @Binding var globalSpeed: Double
    @Binding var fanSpeeds: [Double]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Text("iDRAC 连接设置").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledTextField(label: "IP 地址", text: $ipmiManager.ip)
                        LabeledTextField(label: "用户名", text: $ipmiManager.user)
                        LabeledSecureField(label: "密码", text: $ipmiManager.password)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("全局控制").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        MacFanRow(label: "所有风扇", value: $globalSpeed) {
                            ipmiManager.setAllFans(speed: Int(globalSpeed))
                            for i in 0..<6 {
                                fanSpeeds[i] = globalSpeed
                            }
                        }

                        Button("恢复自动温控") {
                            ipmiManager.resetToAuto()
                        }
                        .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("独立风扇控制").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<6, id: \.self) { index in
                            MacFanRow(label: "Fan \(index + 1)", value: $fanSpeeds[index]) {
                                ipmiManager.setFan(index: index, speed: Int(fanSpeeds[index]))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 360, idealWidth: 380, maxWidth: 440)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 60, alignment: .trailing)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct LabeledSecureField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 60, alignment: .trailing)
            SecureField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct MacFanRow: View {
    let label: String
    @Binding var value: Double
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .frame(width: 70, alignment: .leading)
                Spacer(minLength: 4)
                TextField("", value: $value, formatter: NumberFormatter())
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text("%")
                Button("应用", action: action)
            }
            Slider(value: $value, in: 0...100, step: 1)
        }
    }
}

private struct MacSensorPanel: View {
    @ObservedObject var ipmiManager: IPMIManager

    var body: some View {
        VStack {
            HStack {
                Text("传感器状态")
                    .font(.headline)
                Spacer()
                Button(action: {
                    ipmiManager.fetchSensors()
                }) {
                    if ipmiManager.isFetching {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Text("刷新状态")
                    }
                }
                .disabled(ipmiManager.isFetching)
            }
            .padding([.top, .horizontal])

            Table(ipmiManager.sensors) {
                TableColumn("名称", value: \.name)
                TableColumn("当前值", value: \.value)
                TableColumn("单位", value: \.unit)
                TableColumn("状态", value: \.status)
                TableColumn("下限(严重)", value: \.lc)
                TableColumn("下限(警告)", value: \.lnc)
                TableColumn("上限(警告)", value: \.unc)
                TableColumn("上限(严重)", value: \.uc)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .id(ipmiManager.sensors.count)
    }
}
#endif
