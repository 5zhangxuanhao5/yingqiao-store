import CoreGraphics
import Foundation

// Restore only the pre-creation layout. Do not force a layout on later user edits.
struct ExtensionDisplayLayout {
 let main: CGDirectDisplayID
 let screens: [(CGDirectDisplayID, CGRect)]
 static func snapshot(excluding: CGDirectDisplayID? = nil) -> Self? {
  var ids = [CGDirectDisplayID](repeating: 0, count: 32), count: UInt32 = 0
  guard CGGetActiveDisplayList(32, &ids, &count) == .success else { return nil }
  let screens = ids.prefix(Int(count)).filter { $0 != excluding }.map { ($0, CGDisplayBounds($0)) }
  guard !screens.isEmpty else { return nil }
  return Self(main: CGMainDisplayID(), screens: screens)
 }
 static func refreshConfiguration() throws {
  var transaction: CGDisplayConfigRef?
  guard CGBeginDisplayConfiguration(&transaction) == .success, let transaction else {throw NSError(domain:"DisplayRefresh",code:1)}
  let result=CGCompleteDisplayConfiguration(transaction,.forSession)
  guard result == .success else {throw NSError(domain:"DisplayRefresh",code:Int(result.rawValue))}
 }
 func placeExtension(_ owned: CGDirectDisplayID) throws {
  guard CGDisplayIsActive(main) != 0, CGDisplayIsActive(owned) != 0 else { return }
  let retained = screens.filter { $0.0 != owned && CGDisplayIsActive($0.0) != 0 }
  let width = CGDisplayBounds(owned).width
  let left = retained.map { $0.1.minX }.min() ?? 0
  var transaction: CGDisplayConfigRef?
  guard CGBeginDisplayConfiguration(&transaction) == .success, let transaction else {
   throw NSError(domain: "DisplayLayout", code: 1)
  }
  var result = CGConfigureDisplayMirrorOfDisplay(transaction, owned, kCGNullDirectDisplay)
  for (id, bounds) in retained where result == .success {
   result = CGConfigureDisplayOrigin(transaction, id, Int32(bounds.minX), Int32(bounds.minY))
  }
  if result == .success {
   result = CGConfigureDisplayOrigin(transaction, owned, Int32(left - width), 0)
  }
  guard result == .success else { CGCancelDisplayConfiguration(transaction);throw NSError(domain: "DisplayLayout", code: Int(result.rawValue)) }
  result = CGCompleteDisplayConfiguration(transaction, .forSession)
  guard result == .success else { throw NSError(domain: "DisplayLayout", code: Int(result.rawValue)) }
 }
}
