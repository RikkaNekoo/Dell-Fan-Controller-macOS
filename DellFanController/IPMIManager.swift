import Foundation
import SwiftUI
import Combine
import SwiftIPMI

// 传感器数据模型
struct SensorRecord: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let unit: String
    let status: String
    let lc: String  // Lower Critical
    let lnc: String // Lower Non-Critical
    let unc: String // Upper Non-Critical
    let uc: String  // Upper Critical
}

@MainActor
final class IPMIManager: ObservableObject {
    enum FetchTimeoutError: LocalizedError {
        case sensorListTimeout(seconds: Int)

        var errorDescription: String? {
            switch self {
            case let .sensorListTimeout(seconds):
                return "sensorList timed out after \(seconds)s"
            }
        }
    }
    @AppStorage("ipmi_ip") var ip = "192.168.1.100"
    @AppStorage("ipmi_user") var user = "root"
    @AppStorage("ipmi_password") var password = "rikka"

    @Published var sensors: [SensorRecord] = []
    @Published var isFetching = false

    private func makeClient() -> IPMIClient {
        IPMIClient(
            host: ip,
            username: user,
            password: password,
            privilege: .administrator,
            cipherSuiteID: nil,
            timeout: 2.0,
            retries: 4,
            loggingEnabled: false
        )
    }

    private func formatThreshold(_ value: Double?) -> String {
        guard let value else { return "na" }
        return String(format: "%.3f", value)
    }

    private func unitDisplay(_ unit: String) -> String {
        unit == "degrees C" ? "°C" : unit
    }

    private func shouldKeep(_ row: SensorRow) -> Bool {
        let name = row.name
        if name.contains("Redundancy") { return false }
        if name.contains("Temp") || name.contains("Fan") || name.contains("Voltage") { return true }

        switch row.valueKind {
        case let .analog(_, unit):
            return unit == "degrees C" || unit == "RPM" || unit == "Volts"
        case .discrete, .unavailable:
            return false
        }
    }

    private func toRecord(_ row: SensorRow) -> SensorRecord {
        let value: String
        let unit: String

        switch row.valueKind {
        case let .analog(v, u):
            value = String(format: "%.3f", v)
            unit = unitDisplay(u)
        case let .discrete(raw, state):
            value = String(format: "raw=0x%02X state=0x%04X", raw, state)
            unit = "discrete"
        case .unavailable:
            value = "na"
            unit = ""
        }

        return SensorRecord(
            name: row.name,
            value: value,
            unit: unit,
            status: row.status,
            lc: formatThreshold(row.thresholds.lcr),
            lnc: formatThreshold(row.thresholds.lnc),
            unc: formatThreshold(row.thresholds.unc),
            uc: formatThreshold(row.thresholds.ucr)
        )
    }

    // 恢复自动温控
    func resetToAuto() {
        Task {
            let client = makeClient()
            do {
                try await client.connect()
                _ = try await client.raw(netFn: 0x30, command: 0x30, data: [0x01, 0x01])
                await client.close()
            } catch {
                await client.close()
                print("IPMI resetToAuto error: \(error)")
            }
        }
    }

    // 关闭自动温控（开启手动模式）
    private func enableManualMode(client: IPMIClient) async throws {
        _ = try await client.raw(netFn: 0x30, command: 0x30, data: [0x01, 0x00])
    }

    // 设置全局风扇转速 (0-100)
    func setAllFans(speed: Int) {
        Task {
            let client = makeClient()
            do {
                try await client.connect()
                try await enableManualMode(client: client)
                let clamped = UInt8(max(0, min(100, speed)))
                _ = try await client.raw(netFn: 0x30, command: 0x30, data: [0x02, 0xff, clamped])
                await client.close()
            } catch {
                await client.close()
                print("IPMI setAllFans error: \(error)")
            }
        }
    }

    // 设置单独风扇转速 (Index: 0~5 代表 Fan 1~6)
    func setFan(index: Int, speed: Int) {
        Task {
            let client = makeClient()
            do {
                try await client.connect()
                try await enableManualMode(client: client)
                let fanIndex = UInt8(max(0, min(0xff, index)))
                let clamped = UInt8(max(0, min(100, speed)))
                _ = try await client.raw(netFn: 0x30, command: 0x30, data: [0x02, fanIndex, clamped])
                await client.close()
            } catch {
                await client.close()
                print("IPMI setFan error: \(error)")
            }
        }
    }

    // 获取 iDRAC 传感器状态（结构化）
    func fetchSensors() {
        isFetching = true

        Task {
            let client = makeClient()
            do {
                try await client.connect()
                let rows: [SensorRow] = try await withThrowingTaskGroup(of: [SensorRow].self) { group in
                    group.addTask {
                        try await client.sensorList()
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                        throw FetchTimeoutError.sensorListTimeout(seconds: 10)
                    }

                    let first = try await group.next()
                    group.cancelAll()
                    return first ?? []
                }
                await client.close()

                var tempCount = 1
                let mapped = rows
                    .filter { shouldKeep($0) }
                    .map { row -> SensorRecord in
                        var adjusted = row
                        if adjusted.name == "Temp" {
                            adjusted.name = "CPU\(tempCount) Temp"
                            tempCount += 1
                        }
                        return toRecord(adjusted)
                    }

                sensors = mapped
                isFetching = false
            } catch {
                await client.close()
                sensors = []
                isFetching = false
                print("IPMI fetchSensors error: \(error)")
            }
        }
    }
}
