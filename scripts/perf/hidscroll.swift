import CoreGraphics
import Foundation
// hidscroll <x> <y> <axis: v|h> <seconds> [pxPerTick] [hz]
// Moves the pointer to (x,y) and posts continuous (trackpad-style) wheel
// events there through the system event tap, reversing every second.
let args = CommandLine.arguments
let x = Double(args[1])!, y = Double(args[2])!
let axis = args[3]
let seconds = Double(args[4])!
let px = Int32(args.count > 5 ? args[5] : "6")!
let hz = Double(args.count > 6 ? args[6] : "165")!
let point = CGPoint(x: x, y: y)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(150_000)
let interval = 1.0 / hz
let perSecond = Int(hz)
let ticks = Int(seconds * hz)
var direction: Int32 = 1
var posted = 0
let start = Date()
for i in 0..<ticks {
  if i > 0 && i % perSecond == 0 { direction = -direction }
  let dy: Int32 = axis == "h" ? 0 : px * direction
  let dx: Int32 = axis == "v" ? 0 : px * direction
  if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: i % perSecond == 0 ? 1 : 2)
    e.location = point
    e.post(tap: .cghidEventTap)
    posted += 1
  }
  let wait = start.addingTimeInterval(Double(i + 1) * interval).timeIntervalSinceNow
  if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
}
if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) {
  e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
  e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
  e.location = point
  e.post(tap: .cghidEventTap)
}
print("posted \(posted) wheel events at \(Int(x)),\(Int(y)) over \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
