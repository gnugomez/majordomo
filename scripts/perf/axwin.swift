import ApplicationServices
import Foundation
// axwin <pid> <x> <y> <w> <h>: moves and resizes the process's first window.
let pid = pid_t(CommandLine.arguments[1])!
var pos = CGPoint(x: Double(CommandLine.arguments[2])!, y: Double(CommandLine.arguments[3])!)
var size = CGSize(width: Double(CommandLine.arguments[4])!, height: Double(CommandLine.arguments[5])!)
let app = AXUIElementCreateApplication(pid)
var v: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success, let windows = v as? [AXUIElement], let w = windows.first else { print("no window"); exit(1) }
let p = AXValueCreate(.cgPoint, &pos)!, s = AXValueCreate(.cgSize, &size)!
let r1 = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
let r2 = AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
print("position=\(r1.rawValue) size=\(r2.rawValue)")
