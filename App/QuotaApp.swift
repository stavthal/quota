import QuotaCore
import SwiftUI

@main
struct QuotaApp: App {
    var body: some Scene {
        MenuBarExtra("Quota", systemImage: "gauge.with.dots.needle.67percent") {
            Text("Quota \(QuotaCoreModule.version)")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
