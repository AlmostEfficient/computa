import SwiftUI
import AppKit
import Foundation
struct KeyEventRecord: Identifiable { let id = UUID(); let time = Date(); let kind = "down"; let keyCode: Int64 = 1; let key = "A"; let modifiers = ""; let matched = false }
enum TapMode { case none, active }
@MainActor @Observable final class AppModel { var keyFeedEnabled = true; var keyLog: [KeyEventRecord] = []; var tapMode = TapMode.active }
struct KeyFeed: View {
    let model: AppModel
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LIVE KEY EVENTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Debug feed", isOn: Binding(get: { model.keyFeedEnabled }, set: { model.keyFeedEnabled = $0 })).controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if model.keyLog.isEmpty {
                VStack(spacing: 6) {
                    Text(!model.keyFeedEnabled ? "Key-event logging is off" : model.tapMode == .none ? "Not listening to keys" : "Press any key")
                        .font(.system(size: 13, weight: .medium))
                    Text("Enable the debug feed only when diagnosing a shortcut. Dictation works with it off.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.keyLog.indices, id: \.self) { index in
                            let event = model.keyLog[index]
                            HStack(spacing: 8) {
                                Text(Self.time.string(from: event.time)).foregroundStyle(.secondary)
                                Text(event.kind).frame(width: 44, alignment: .leading).foregroundStyle(.secondary)
                                Text(event.modifiers + event.key).fontWeight(.medium)
                                Spacer()
                                Text("code \(event.keyCode)").foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(event.matched ? Color.pink.opacity(0.18) : .clear)
                        }
                    }
                }
            }
        }
    }
}

@main struct Check {
 @MainActor static func main() async {
  let model = AppModel()
  let host = NSHostingView(rootView: KeyFeed(model: model))
  host.frame = NSRect(x:0,y:0,width:380,height:720)
  for i in 0..<10000 {
   autoreleasepool {
    model.keyLog.insert(KeyEventRecord(),at:0)
    if model.keyLog.count > 40 { model.keyLog.removeLast() }
    host.layoutSubtreeIfNeeded()
   }
   if i % 1000 == 999 {
    var info = task_vm_info_data_t(); var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/4)
    let status = withUnsafeMutablePointer(to:&info) { p in p.withMemoryRebound(to:integer_t.self,capacity:Int(n)) { task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&n) } }
    print("rows=\(i+1) footprint=\(info.phys_footprint) status=\(status)")
   }
   try? await Task.sleep(for:.milliseconds(1))
  }
  withExtendedLifetime(host) {}
 }
}
