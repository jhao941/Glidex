import Foundation

enum DevicePrinter {
    static func printDevices(_ devices: [BootedSimulatorRecord], logger: Logger) {
        if devices.isEmpty {
            logger.warn("no booted simulators found")
            return
        }

        for (index, device) in devices.enumerated() {
            logger.info("device[\(index)] name=\(device.name) udid=\(device.udid)")
            logger.info("  runtime=\(device.runtime)")
            logger.info("  type=\(device.deviceType)")
            logger.info("  source=\(device.source)")
            if let screenSize = device.screenSize {
                logger.info("  screen_size_points=\(Int(screenSize.width))x\(Int(screenSize.height))")
            }
            if let nativeResolution = device.nativeResolution {
                logger.info("  native_resolution=\(Int(nativeResolution.width))x\(Int(nativeResolution.height))")
            }
            if let scale = device.scale {
                logger.info("  scale=\(scale)")
            }
            if let dataPath = device.dataPath {
                logger.info("  data_path=\(dataPath)")
            }
        }

        if let selected = devices.first {
            logger.info("selected_target=\(selected.name) (\(selected.udid))")
        }
    }
}
