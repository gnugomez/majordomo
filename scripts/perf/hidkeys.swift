// hidkeys <pid> <keycode> <count> [interval ms]: brings one process to the
// front through Accessibility, checks that it is in front, posts key
// presses, then puts the app that was in front back. Nothing is posted
// unless the target is in front. Arrow key codes: left 123, right 124,
// down 125, up 126.
import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 4, let pid = pid_t(args[1]), let key = UInt16(args[2]), let count = Int(args[3]) else {
  print("usage: hidkeys <pid> <keycode> <count> [interval ms]")
  exit(1)
}
let ms = args.count > 4 ? Int(args[4]) ?? 60 : 60

func bringToFront(_ pid: pid_t) -> Bool {
  let app = AXUIElementCreateApplication(pid)
  AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
  for _ in 0..<20 {
    usleep(50_000)
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
      return true
    }
  }
  return false
}

let previous = NSWorkspace.shared.frontmostApplication?.processIdentifier
guard bringToFront(pid) else {
  print("could not bring pid \(pid) to the front; nothing posted")
  exit(1)
}
let source = CGEventSource(stateID: .hidSystemState)
var posted = 0
for _ in 0..<count {
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
    print("pid \(pid) lost the front after \(posted) presses; stopping")
    break
  }
  guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false) else {
    print("could not make the event")
    exit(1)
  }
  down.post(tap: .cghidEventTap)
  usleep(12_000)
  up.post(tap: .cghidEventTap)
  posted += 1
  usleep(UInt32(ms) * 1000)
}
if let previous, previous != pid {
  _ = bringToFront(previous)
}
print("posted \(posted) presses of key \(key) to pid \(pid)")
