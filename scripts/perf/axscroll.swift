import ApplicationServices
import Foundation
// axscroll <pid> <axis: v|h> <seconds> [hz] [span 0..1]
// Finds the board's scroll area (the one with both scroll bars) in the
// process's windows and sweeps its scroll bar back and forth through
// `span` of its range at `hz` steps per second.
let args = CommandLine.arguments
let pid = pid_t(args[1])!
let axis = args[2]
let seconds = Double(args[3])!
let hz = Double(args.count > 4 ? args[4] : "165")!
let span = Double(args.count > 5 ? args[5] : "0.3")!

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
  (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
func role(_ e: AXUIElement) -> String { (attr(e, kAXRoleAttribute) as? String) ?? "" }

func findBoardScrollArea(_ e: AXUIElement, depth: Int = 0) -> AXUIElement? {
  if role(e) == kAXScrollAreaRole, attr(e, kAXHorizontalScrollBarAttribute) != nil, attr(e, kAXVerticalScrollBarAttribute) != nil {
    return e
  }
  guard depth < 40 else { return nil }
  for c in children(e) {
    if let found = findBoardScrollArea(c, depth: depth + 1) { return found }
  }
  return nil
}

let app = AXUIElementCreateApplication(pid)
guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
  print("no windows"); exit(1)
}
var area: AXUIElement?
for w in windows {
  if let found = findBoardScrollArea(w) { area = found; break }
}
guard let area else { print("no board scroll area"); exit(1) }
let barName = axis == "h" ? kAXHorizontalScrollBarAttribute : kAXVerticalScrollBarAttribute
guard let bar = attr(area, barName) else { print("no scroll bar"); exit(1) }
let scroller = bar as! AXUIElement
let startValue = (attr(scroller, kAXValueAttribute) as? Double) ?? 0
print("scroll area found; \(axis) bar at \(startValue)")

let interval = 1.0 / hz
let ticks = Int(seconds * hz)
let begin = Date()
var sets = 0
var failures = 0
for i in 0..<ticks {
  // A triangle wave from startValue up through span and back, one cycle per 2 s.
  let phase = (Double(i) * interval).truncatingRemainder(dividingBy: 2.0) / 2.0
  let tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2
  let value = min(1, max(0, startValue + tri * span))
  let number = value as CFNumber
  if AXUIElementSetAttributeValue(scroller, kAXValueAttribute as CFString, number) == .success { sets += 1 } else { failures += 1 }
  let wait = begin.addingTimeInterval(Double(i + 1) * interval).timeIntervalSinceNow
  if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
}
AXUIElementSetAttributeValue(scroller, kAXValueAttribute as CFString, startValue as CFNumber)
let took = Date().timeIntervalSince(begin)
print("sets=\(sets) failures=\(failures) over \(String(format: "%.1f", took))s = \(String(format: "%.0f", Double(sets) / took))/s")
