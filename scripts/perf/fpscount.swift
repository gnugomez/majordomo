import Foundation
import ScreenCaptureKit
import CoreMedia
// fpscount <windowID> <seconds>: per second, how many display refreshes
// carried new content for the window (its achieved update rate).
_ = CGMainDisplayID()
let windowID = CGWindowID(CommandLine.arguments[1])!
let seconds = Int(CommandLine.arguments[2])!

final class Counter: NSObject, SCStreamOutput {
  var complete = 0
  var idle = 0
  let lock = NSLock()
  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen,
          let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
          let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
    lock.lock(); defer { lock.unlock() }
    if status == .complete { complete += 1 } else if status == .idle { idle += 1 }
  }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
  do {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
      print("window \(windowID) not found"); exit(1)
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    config.minimumFrameInterval = CMTime(value: 1, timescale: 240)
    config.width = Int(window.frame.width / 4)
    config.height = Int(window.frame.height / 4)
    config.queueDepth = 8
    config.showsCursor = false
    let counter = Counter()
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    try stream.addStreamOutput(counter, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
    try await stream.startCapture()
    print("capturing window \(windowID) '\(window.title ?? "")' \(Int(window.frame.width))x\(Int(window.frame.height))")
    for t in 0..<seconds {
      try await Task.sleep(for: .seconds(1))
      counter.lock.lock()
      print("t=\(String(format: "%02d", t))  updates/s=\(counter.complete)  idle=\(counter.idle)")
      counter.complete = 0; counter.idle = 0
      counter.lock.unlock()
    }
    try await stream.stopCapture()
  } catch {
    print("error: \(error)")
  }
  semaphore.signal()
}
semaphore.wait()
