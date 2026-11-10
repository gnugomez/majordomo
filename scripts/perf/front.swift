import CoreGraphics
import Foundation
// front <x> <y>: the on-screen windows (front to back) under the point.
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
  let b = w[kCGWindowBounds as String] as! [String: CGFloat]
  let r = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
  let layer = w[kCGWindowLayer as String] as! Int
  if r.contains(CGPoint(x: x, y: y)) && layer == 0 {
    print("\(w[kCGWindowOwnerName as String] ?? "") pid=\(w[kCGWindowOwnerPID as String] ?? 0) id=\(w[kCGWindowNumber as String] ?? 0) '\(w[kCGWindowName as String] ?? "")' \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))")
  }
}
