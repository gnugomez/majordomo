import CoreGraphics
import Foundation
import ApplicationServices
// winfo <pid>: lists on-screen windows of the process; also reports accessibility trust.
let pid = Int32(CommandLine.arguments[1])!
print("AXIsProcessTrusted=\(AXIsProcessTrusted())")
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
  let b = w[kCGWindowBounds as String] as! [String: CGFloat]
  let id = w[kCGWindowNumber as String] as! Int
  let name = w[kCGWindowName as String] as? String ?? ""
  let layer = w[kCGWindowLayer as String] as! Int
  print("window id=\(id) layer=\(layer) name='\(name)' x=\(Int(b["X"]!)) y=\(Int(b["Y"]!)) w=\(Int(b["Width"]!)) h=\(Int(b["Height"]!))")
}
