// hidclick <x> <y>: moves the pointer to a screen point and clicks there.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
  print("usage: hidclick <x> <y>")
  exit(1)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
guard let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
      let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
  print("could not make the events")
  exit(1)
}
move.post(tap: .cghidEventTap)
usleep(60_000)
down.post(tap: .cghidEventTap)
usleep(40_000)
up.post(tap: .cghidEventTap)
print("clicked at \(Int(x)),\(Int(y))")
