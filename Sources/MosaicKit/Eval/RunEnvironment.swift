import Foundation

/// # 一次性能测量的环境元数据
///
/// **不记录环境的性能数字不可用于发布判定。** 同一份代码在 debug 下慢 18 倍
/// （本项目实测），在低电量模式下被限频，在发热后被降频，在模拟器上跑的是 Mac 的
/// CPU。所以「P95 = 79ms」这句话如果不带环境，等于什么都没说。
///
/// Release Gate 会读它：环境不满足 policy 要求时判 **STALE 而不是 FAIL** ——
/// 因为那不是「性能不达标」，是「这批数字没有资格参与判定」。
public struct RunEnvironment: Codable, Equatable, Sendable {

    public enum DeviceClass: String, Codable, Sendable {
        case mac
        case simulator
        case physicalDevice
    }

    public let deviceClass: DeviceClass
    /// 例：`iPhone18,4`。用 sysctl 的原始标识而不是营销名 —— 营销名会重复。
    public let deviceModel: String
    public let osVersion: String
    /// `release` / `debug`。性能结论只接受 release。
    public let buildConfiguration: String
    public let thermalState: String
    public let lowPowerMode: Bool
    /// 这批数字测的是哪一层延迟。三层预算不同，混判必然出错。
    public var measuredLayer: MeasuredLatencyLayer
    /// 云端 provider 的区域标签。**地理相关的延迟必须带它**，否则数字不可比。
    public var providerRegion: String?
    public let capturedAt: Date

    /// 显式构造。测试与「手工记录一次外部测量」都需要它 ——
    /// 隐式 memberwise init 是 internal，跨模块用不了。
    public init(deviceClass: DeviceClass,
                deviceModel: String,
                osVersion: String,
                buildConfiguration: String,
                thermalState: String,
                lowPowerMode: Bool,
                measuredLayer: MeasuredLatencyLayer = .firstResult,
                providerRegion: String? = nil,
                capturedAt: Date = Date()) {
        self.deviceClass = deviceClass
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.buildConfiguration = buildConfiguration
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
        self.measuredLayer = measuredLayer
        self.providerRegion = providerRegion
        self.capturedAt = capturedAt
    }

    public static func capture(layer: MeasuredLatencyLayer = .firstResult,
                               providerRegion: String? = nil,
                               now: Date = Date()) -> RunEnvironment {
        RunEnvironment(deviceClass: currentDeviceClass(),
                               deviceModel: hardwareIdentifier(),
                               osVersion: currentOSVersion(),
                               buildConfiguration: currentBuildConfiguration(),
                               thermalState: currentThermalState(),
                               lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                               measuredLayer: layer,
                               providerRegion: providerRegion,
                               capturedAt: now)
    }

    private static func currentDeviceClass() -> DeviceClass {
        #if targetEnvironment(simulator)
        return .simulator
        #elseif os(macOS)
        return .mac
        #else
        return .physicalDevice
        #endif
    }

    /// `hw.machine` 在真机上给 `iPhone18,4`；在模拟器上给宿主机架构，
    /// 所以模拟器要读 `SIMULATOR_MODEL_IDENTIFIER`，否则会把 Mac 的型号
    /// 当成 iPhone 的型号记下来。
    private static func hardwareIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated)(simulator)"
        }
        #endif
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    /// 用 Foundation 而不是 `UIDevice` —— **内核不引 UIKit**（平台无关边界）。
    private static func currentOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static func currentBuildConfiguration() -> String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    private static func currentThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// 这批数字有没有资格参与发布判定。
    ///
    /// **环境不合格不是「性能不达标」**，所以 Gate 判 STALE 而不是 FAIL ——
    /// 补救动作是「换台机器重测」，不是「去优化代码」。
    public func disqualification(requiredDeviceClass: DeviceClass,
                                 requiredBuildConfiguration: String) -> String? {
        if buildConfiguration != requiredBuildConfiguration {
            return "这批数字来自 \(buildConfiguration) 构建，判定要求 \(requiredBuildConfiguration)"
        }
        if deviceClass != requiredDeviceClass {
            return "这批数字来自 \(deviceClass.rawValue)，判定要求 \(requiredDeviceClass.rawValue)"
        }
        if lowPowerMode { return "测量时开着低电量模式，CPU 被限频" }
        if thermalState != "nominal" { return "测量时设备热状态为 \(thermalState)，已降频" }
        return nil
    }
}
