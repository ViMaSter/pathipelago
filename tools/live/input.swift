// Minimal macOS input/window helper for the live Pathogenic test harness.
//   input windows <owner>          JSON list of on-screen windows of that app
//   input activate <pid>           bring the app to the front
//   input key <keycode> [hold_ms]  press and release a key
//   input click <x> <y>            left click at screen point
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}
guard args.count >= 2 else { fail("usage: input windows|activate|key|click ...") }
let source = CGEventSource(stateID: .hidSystemState)

switch args[1] {
case "windows":
    guard args.count == 3 else { fail("usage: input windows <owner>") }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    var result: [[String: Any]] = []
    for window in list where (window[kCGWindowOwnerName as String] as? String) == args[2] {
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        result.append(["id": window[kCGWindowNumber as String] ?? 0,
                       "pid": window[kCGWindowOwnerPID as String] ?? 0,
                       "layer": window[kCGWindowLayer as String] ?? 0,
                       "bounds": bounds])
    }
    let data = try! JSONSerialization.data(withJSONObject: result)
    print(String(data: data, encoding: .utf8)!)
case "activate":
    guard args.count == 3, let pid = Int32(args[2]),
          let app = NSRunningApplication(processIdentifier: pid) else { fail("unknown pid") }
    app.activate()
    Thread.sleep(forTimeInterval: 0.3)
case "key":
    guard args.count >= 3, let code = UInt16(args[2]) else { fail("usage: input key <keycode> [hold_ms]") }
    let hold = args.count >= 4 ? (Double(args[3]) ?? 60) / 1000.0 : 0.06
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: hold)
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
case "click":
    guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else { fail("usage: input click <x> <y>") }
    let point = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.15)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
default:
    fail("unknown command \(args[1])")
}
