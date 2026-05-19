import SwiftUI
import ServiceManagement
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "LaunchAtLogin")

func launchAtLoginBinding() -> Binding<Bool> {
    Binding(
        get: { SMAppService.mainApp.status == .enabled },
        set: { newValue in
            do {
                try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                log.error("SMAppService \(newValue ? "register" : "unregister") failed: \(error)")
            }
        }
    )
}
