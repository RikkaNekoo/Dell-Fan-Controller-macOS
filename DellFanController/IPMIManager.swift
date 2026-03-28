import Foundation
import SwiftUI
import Combine

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

class IPMIManager: ObservableObject {
    @AppStorage("ipmi_ip") var ip = "192.168.1.100"
    @AppStorage("ipmi_user") var user = "root"
    @AppStorage("ipmi_password") var password = "rikka"
    
    @Published var sensors: [SensorRecord] = []
    @Published var isFetching = false
    
    // 执行终端命令
    private func execute(arguments: [String]) -> String {
        guard let path = Bundle.main.path(forResource: "ipmitool", ofType: nil) else {
            return "Error: 找不到 ipmitool。请确保它已添加到 Xcode 的 Resources 中。"
        }
        
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Exception: \(error.localizedDescription)"
        }
    }
    
    private func baseArgs() -> [String] {
        return ["-I", "lanplus", "-H", ip, "-U", user, "-P", password]
    }
    
    // 恢复自动温控
    func resetToAuto() {
        _ = execute(arguments: baseArgs() + ["raw", "0x30", "0x30", "0x01", "0x01"])
    }
    
    // 关闭自动温控（开启手动模式）
    private func enableManualMode() {
        _ = execute(arguments: baseArgs() + ["raw", "0x30", "0x30", "0x01", "0x00"])
    }
    
    // 设置全局风扇转速 (0-100)
    func setAllFans(speed: Int) {
        enableManualMode()
        let hexSpeed = String(format: "0x%02x", speed)
        _ = execute(arguments: baseArgs() + ["raw", "0x30", "0x30", "0x02", "0xff", hexSpeed])
    }
    
    // 设置单独风扇转速 (Index: 0~5 代表 Fan 1~6)
    func setFan(index: Int, speed: Int) {
        enableManualMode()
        let hexIndex = String(format: "0x%02x", index)
        let hexSpeed = String(format: "0x%02x", speed)
        _ = execute(arguments: baseArgs() + ["raw", "0x30", "0x30", "0x02", hexIndex, hexSpeed])
    }
    // 获取 iDRAC 传感器状态
    func fetchSensors() {
        isFetching = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.execute(arguments: self.baseArgs() + ["sensor"])
            let lines = result.components(separatedBy: .newlines)
            var parsedSensors: [SensorRecord] = []
            var tempCount = 1

            for line in lines {
                if line.contains("Redundancy") {
                    continue
                }
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 9 else { continue }
                var name = parts[0]
                let isTarget = name.contains("Temp") || name.contains("Fan") || name.contains("Voltage")
                guard isTarget else { continue }
                let value = parts[1]
                var unit = parts[2]
                let status = parts[3]
                if name == "Temp" {
                    name = "CPU\(tempCount) Temp"
                    tempCount += 1
                }
                if unit == "degrees C" {
                    unit = "°C"
                }
                let record = SensorRecord(
                    name: name,
                    value: value,
                    unit: unit,
                    status: status,
                    lc: parts[5],
                    lnc: parts[6],
                    unc: parts[7],
                    uc: parts[8]
                )
                parsedSensors.append(record)
            }

            DispatchQueue.main.async {
                self.sensors = parsedSensors
                self.isFetching = false
            }
        }
    }
}
