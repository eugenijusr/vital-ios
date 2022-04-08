import Foundation

public extension DevicesManager {
  
  func bloodPressureReader(for device: ScannedDevice, queue: DispatchQueue) -> BloodPressureReadable {
    switch device.deviceModel.brand {
      case .omron:
        return BloodPressureReader1810(manager: manager, queue: queue)
      default:
        fatalError("\(device.deviceModel.brand) not supported")
    }
  }
  
  func glucoseMeter(for device: ScannedDevice, queue: DispatchQueue) -> GlucoseMeterReadable {
    switch device.deviceModel.brand {
      case .accuCheck, .contour:
        return GlucoseMeter1808(manager: manager, queue: queue)
      default:
        fatalError("\(device.deviceModel.brand) not supported")
    }
  }
}
