#
# Native room-scan plugin: RoomPlan (iOS 16+ LiDAR) + ARKit fallback.
#
Pod::Spec.new do |s|
  s.name             = 'room_scan'
  s.version          = '0.1.0'
  s.summary          = 'Native room-scan plugin for FieldFleet.'
  s.description      = <<-DESC
RoomPlan-backed room scanning on iOS 16+ LiDAR devices with an ARKit
plane-tap fallback for older hardware. Surfaces a MethodChannel + EventChannel
and a UIKit platform view consumed by the Flutter app.
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'FieldFleet' => 'engineering@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  # System frameworks. RoomPlan is iOS 16+ — Swift auto-links it from the
  # `import RoomPlan` in our source, guarded by `@available(iOS 16, *)`
  # and `canImport(RoomPlan)`. We add it as a weak framework so older
  # devices load the binary without crashing.
  s.weak_frameworks  = ['RoomPlan']
  s.frameworks       = ['ARKit', 'SceneKit', 'UIKit']

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'ENABLE_BITCODE' => 'NO',
  }
end
