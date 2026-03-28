import SwiftUI

struct ContentView: View {
    @StateObject private var ipmiManager = IPMIManager()
    
    @State private var globalSpeed: Double = 20
    @State private var fanSpeeds: [Double] = Array(repeating: 20, count: 6)
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：控制面板
            VStack {
                Form {
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
                .padding()
                .frame(width: 350)
            }
            
            Divider()
            
            // 右侧：传感器数据
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
            .layoutPriority(1) // 确保右侧获得最高的布局权重
            .id(ipmiManager.sensors.count) // 当数据数量变化时，强制刷新该区域
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onAppear {
            // 启动时自动获取一次数据
            ipmiManager.fetchSensors()
        }
    }
}
