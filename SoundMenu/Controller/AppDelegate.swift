//
//  AppDelegate.swift
//  SoundMenu
//
//  Ponto de entrada: app só de barra de menus (sem janela e sem ícone no Dock).
//

import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppVolumeModel()
        statusMenuController = StatusMenuController(model: model)

        // Pede a permissão logo ao abrir, em vez de esperar o primeiro ajuste de volume.
        if AudioPermission.status == .unknown {
            AudioPermission.request { granted in
                if granted { model.restartTaps() }
            }
        }
    }
}
