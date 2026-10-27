//
//  StatusMenuController.swift
//  SoundMenu
//
//  Controller: dono do ícone na barra de menus. Monta o menu a partir do model
//  e traduz as ações das views em alterações no model.
//

import AppKit

final class StatusMenuController: NSObject {
    private static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    private let model: AppVolumeModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(model: AppVolumeModel) {
        self.model = model
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "SoundMenu")
        menu.delegate = self
        statusItem.menu = menu

        model.onChange = { [weak self] in self?.rebuildMenu() }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if AudioPermission.status == .denied {
            let permission = NSMenuItem(title: "Permitir acesso ao áudio do sistema…", action: #selector(openPrivacySettings), keyEquivalent: "")
            permission.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            permission.target = self
            menu.addItem(permission)
            menu.addItem(.separator())
        }

        addOutputDeviceItems()
        menu.addItem(.separator())
        addAppItems()
        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Restaurar todos para 100%", action: #selector(resetAll), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(NSMenuItem(title: "Sair do SoundMenu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Um único item "Saída: <atual>" com submenu de escolha única, para não ocupar espaço no menu.
    private func addOutputDeviceItems() {
        let devices = model.outputDevices()
        let current = devices.first(where: model.isCurrentOutput)
        let submenu = NSMenu()

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectOutputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = model.isCurrentOutput(device) ? .on : .off
            submenu.addItem(item)
        }

        let outputItem = NSMenuItem(title: "Saída: \(current?.name ?? "Nenhuma")", action: nil, keyEquivalent: "")
        outputItem.image = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil)
        outputItem.submenu = submenu
        menu.addItem(outputItem)
    }

    private func addAppItems() {
        menu.addItem(.sectionHeader(title: "Apps"))

        let apps = model.runningApps()
        if apps.isEmpty {
            let empty = NSMenuItem(title: "Nenhum app aberto", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for app in apps {
            let setting = model.setting(for: app.bundleID)
            let row = AppVolumeRowView(bundleID: app.bundleID)
            row.configure(name: app.name, icon: app.icon, isPlaying: app.isPlaying)
            row.update(volume: setting.volume, isMuted: setting.isMuted)
            row.delegate = self

            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
    }

    // MARK: - Ações

    @objc private func selectOutputDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String,
              let device = model.outputDevices().first(where: { $0.uid == uid }) else { return }
        model.selectOutput(device)
    }

    @objc private func resetAll() {
        model.resetAll()
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(Self.privacySettingsURL)
    }
}

// MARK: - NSMenuDelegate

extension StatusMenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}

// MARK: - AppVolumeRowViewDelegate

extension StatusMenuController: AppVolumeRowViewDelegate {
    func rowView(_ rowView: AppVolumeRowView, didChangeVolume volume: Float) {
        model.setVolume(volume, for: rowView.bundleID)
        refresh(rowView)
    }

    func rowViewDidToggleMute(_ rowView: AppVolumeRowView) {
        model.toggleMute(for: rowView.bundleID)
        refresh(rowView)
    }

    private func refresh(_ rowView: AppVolumeRowView) {
        let setting = model.setting(for: rowView.bundleID)
        rowView.update(volume: setting.volume, isMuted: setting.isMuted)
    }
}
