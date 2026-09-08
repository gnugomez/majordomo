// A small SVG path-data parser, enough to draw the two provider marks
// (M/L/H/V/C/S/A/Z, absolute and relative, elliptical arcs converted to
// cubic Béziers). Not a general SVG engine: adjacent arc flags without
// separators aren't handled — the two paths in ProviderMark.swift don't
// use them.

import CoreGraphics
import Foundation

enum SVGPath {
  static func parse(_ d: String) -> CGPath {
    let path = CGMutablePath()
    let scalars = Array(d.unicodeScalars)
    var i = 0
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var lastCubicControl: CGPoint?
    var command: UnicodeScalar = " "

    func isSeparator(_ c: UnicodeScalar) -> Bool {
      c == " " || c == "," || c == "\n" || c == "\r" || c == "\t"
    }

    func skipSeparators() {
      while i < scalars.count, isSeparator(scalars[i]) {
        i += 1
      }
    }

    func number() -> CGFloat? {
      skipSeparators()
      var j = i
      var seenDot = false
      var seenDigit = false
      if j < scalars.count, scalars[j] == "+" || scalars[j] == "-" {
        j += 1
      }
      loop: while j < scalars.count {
        switch scalars[j] {
        case "0" ... "9":
          seenDigit = true
          j += 1
        case ".":
          if seenDot {
            break loop
          }
          seenDot = true
          j += 1
        case "e", "E":
          // Exponent: consume sign + digits.
          var k = j + 1
          if k < scalars.count, scalars[k] == "+" || scalars[k] == "-" {
            k += 1
          }
          var expDigits = false
          while k < scalars.count, ("0" ... "9").contains(scalars[k]) {
            expDigits = true
            k += 1
          }
          if expDigits {
            j = k
          }
          break loop
        default:
          break loop
        }
      }
      guard seenDigit else {
        return nil
      }
      let text = String(String.UnicodeScalarView(scalars[i ..< j]))
      i = j
      guard let value = Double(text) else {
        return nil
      }
      return CGFloat(value)
    }

    func numbers(_ n: Int) -> [CGFloat]? {
      var result: [CGFloat] = []
      result.reserveCapacity(n)
      for _ in 0 ..< n {
        guard let value = number() else {
          return nil
        }
        result.append(value)
      }
      return result
    }

    /// SVG endpoint arc → cubic Béziers (W3C implementation notes B.2.4).
    func arc(rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool, to end: CGPoint) {
      var rx = abs(rxIn)
      var ry = abs(ryIn)
      let from = current
      if rx == 0 || ry == 0 || from == end {
        path.addLine(to: end)
        return
      }
      let phi = rotation * .pi / 180
      let dx2 = (from.x - end.x) / 2
      let dy2 = (from.y - end.y) / 2
      let x1p = cos(phi) * dx2 + sin(phi) * dy2
      let y1p = -sin(phi) * dx2 + cos(phi) * dy2
      let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
      if lambda > 1 {
        let s = sqrt(lambda)
        rx *= s
        ry *= s
      }
      let rxs = rx * rx
      let rys = ry * ry
      let num = rxs * rys - rxs * y1p * y1p - rys * x1p * x1p
      let den = rxs * y1p * y1p + rys * x1p * x1p
      var coef = den == 0 ? 0 : sqrt(max(0, num / den))
      if largeArc == sweep {
        coef = -coef
      }
      let cxp = coef * rx * y1p / ry
      let cyp = -coef * ry * x1p / rx
      let cx = cos(phi) * cxp - sin(phi) * cyp + (from.x + end.x) / 2
      let cy = sin(phi) * cxp + cos(phi) * cyp + (from.y + end.y) / 2

      func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        guard len != 0 else {
          return 0
        }
        var a = acos(min(1, max(-1, dot / len)))
        if ux * vy - uy * vx < 0 {
          a = -a
        }
        return a
      }

      let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
      var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
      if !sweep, delta > 0 {
        delta -= 2 * .pi
      }
      if sweep, delta < 0 {
        delta += 2 * .pi
      }

      let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
      let segDelta = delta / CGFloat(segments)
      let alpha = 4 / 3 * tan(segDelta / 4)

      func point(_ a: CGFloat) -> CGPoint {
        CGPoint(
          x: cx + rx * cos(a) * cos(phi) - ry * sin(a) * sin(phi),
          y: cy + rx * cos(a) * sin(phi) + ry * sin(a) * cos(phi)
        )
      }

      func derivative(_ a: CGFloat) -> CGPoint {
        CGPoint(
          x: -rx * sin(a) * cos(phi) - ry * cos(a) * sin(phi),
          y: -rx * sin(a) * sin(phi) + ry * cos(a) * cos(phi)
        )
      }

      var t = theta1
      var p1 = from
      for _ in 0 ..< segments {
        let t2 = t + segDelta
        let p2 = point(t2)
        let d1 = derivative(t)
        let d2 = derivative(t2)
        path.addCurve(
          to: p2,
          control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
          control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)
        )
        t = t2
        p1 = p2
      }
    }

    while i < scalars.count {
      skipSeparators()
      guard i < scalars.count else {
        break
      }
      let c = scalars[i]
      if ("A" ... "Z").contains(c) || ("a" ... "z").contains(c) {
        command = c
        i += 1
      } else if command == "M" {
        command = "L" // Implicit lineto after a moveto.
      } else if command == "m" {
        command = "l"
      }

      let relative = ("a" ... "z").contains(command)
      func resolve(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
      }

      switch command {
      case "M", "m":
        guard let n = numbers(2) else { return path }
        current = resolve(n[0], n[1])
        subpathStart = current
        path.move(to: current)
        lastCubicControl = nil
      case "L", "l":
        guard let n = numbers(2) else { return path }
        current = resolve(n[0], n[1])
        path.addLine(to: current)
        lastCubicControl = nil
      case "H", "h":
        guard let n = numbers(1) else { return path }
        current = CGPoint(x: relative ? current.x + n[0] : n[0], y: current.y)
        path.addLine(to: current)
        lastCubicControl = nil
      case "V", "v":
        guard let n = numbers(1) else { return path }
        current = CGPoint(x: current.x, y: relative ? current.y + n[0] : n[0])
        path.addLine(to: current)
        lastCubicControl = nil
      case "C", "c":
        guard let n = numbers(6) else { return path }
        let c1 = resolve(n[0], n[1])
        let c2 = resolve(n[2], n[3])
        current = resolve(n[4], n[5])
        path.addCurve(to: current, control1: c1, control2: c2)
        lastCubicControl = c2
      case "S", "s":
        guard let n = numbers(4) else { return path }
        let reflected = lastCubicControl.map {
          CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
        } ?? current
        let c2 = resolve(n[0], n[1])
        current = resolve(n[2], n[3])
        path.addCurve(to: current, control1: reflected, control2: c2)
        lastCubicControl = c2
      case "A", "a":
        guard let n = numbers(7) else { return path }
        let end = resolve(n[5], n[6])
        arc(rx: n[0], ry: n[1], rotation: n[2], largeArc: n[3] != 0, sweep: n[4] != 0, to: end)
        current = end
        lastCubicControl = nil
      case "Z", "z":
        path.closeSubpath()
        current = subpathStart
        lastCubicControl = nil
      default:
        return path
      }
    }
    return path
  }
}
