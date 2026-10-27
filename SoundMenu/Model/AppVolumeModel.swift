//
//  AppVolumeModel.swift
//  SoundMenu
//
//  Model principal: sabe quais apps estão abertos, guarda o volume de cada um,
//  controla a saída de áudio e mantém um ProcessTap ativo para todo app que não está em 100%.
//

import AppKit
import CoreAudio

struct AudioApp {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let pid: pid_t
    let isPlaying: Bool
}

struct VolumeSetting: Codable, Equatable {
    var volume: Float = 1
    var isMuted = false

    /// Em 100% e sem mudo o app toca direto, sem passar por um tap.
    var isDefault: Bool { volume >= 1 && !isMuted }

    /// Curva quadrática: o ouvido percebe volume de forma logarítmica, então um
    /// slider linear deixaria quase todo o curso "alto demais".
    var gain: Float { isMuted ? 0 : volume * volume }
}

final class AppVolumeModel {
    private static let settingsKey = "volumeSettings"

    /// Avisa o controller quando algo mudou fora da interação do usuário (ex.: trocou o fone).
    var onChange: (() -> Void)?

    private var outputDeviceUID = ""
    private var settings: [String: VolumeSetting] = [:]
    private var taps: [String: ProcessTap] = [:]

    init() {
        loadSettings()
        outputDeviceUID = OutputDevice.current?.uid ?? ""

        AudioObjectID.system.addListener(kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.reconcileTaps()
        }
        AudioObjectID.system.addListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            guard let self else { return }
            outputDeviceUID = OutputDevice.current?.uid ?? ""
            reconcileTaps()
            onChange?()
        }
        reconcileTaps()
    }

    // MARK: - Apps

    /// Apps abertos (com ícone no Dock), os que estão tocando áudio primeiro.
    func runningApps() -> [AudioApp] {
        let processes = audioProcessesByApp()

        return regularApps()
            .compactMap { app -> AudioApp? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AudioApp(bundleID: bundleID,
                                name: app.localizedName ?? bundleID,
                                icon: app.icon,
                                pid: app.processIdentifier,
                                isPlaying: processes[app.processIdentifier]?.contains { $0.isPlaying } ?? false)
            }
            .sorted { ($0.isPlaying ? 0 : 1, $0.name.localizedLowercase) < ($1.isPlaying ? 0 : 1, $1.name.localizedLowercase) }
    }

    func setting(for bundleID: String) -> VolumeSetting {
        settings[bundleID] ?? VolumeSetting()
    }

    func setVolume(_ volume: Float, for bundleID: String) {
        update(bundleID) { $0.volume = min(max(volume, 0), 1) }
    }

    func toggleMute(for bundleID: String) {
        update(bundleID) { $0.isMuted.toggle() }
    }

    func resetAll() {
        settings.removeAll()
        saveSettings()
        reconcileTaps()
    }

    /// Recria todos os taps; usado quando a permissão de áudio acabou de ser concedida.
    func restartTaps() {
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
        reconcileTaps()
    }

    private func update(_ bundleID: String, _ change: (inout VolumeSetting) -> Void) {
        var setting = setting(for: bundleID)
        change(&setting)
        settings[bundleID] = setting.isDefault ? nil : setting
        saveSettings()

        // Caminho rápido enquanto o slider é arrastado: só troca o ganho do tap existente.
        if let tap = taps[bundleID], !setting.isDefault {
            tap.gain = setting.gain
        } else {
            reconcileTaps()
        }
    }

    // MARK: - Saída

    func outputDevices() -> [OutputDevice] {
        OutputDevice.all()
    }

    func isCurrentOutput(_ device: OutputDevice) -> Bool {
        device.uid == outputDeviceUID
    }

    /// Troca a saída do sistema; o listener de saída padrão recria os taps no novo dispositivo.
    func selectOutput(_ device: OutputDevice) {
        do {
            try device.makeDefault()
        } catch {
            NSLog("SoundMenu: não foi possível trocar a saída para \(device.name): \(error)")
        }
    }

    // MARK: - Taps

    /// Cria, recria ou destrói taps para que reflitam os apps abertos, os volumes e a saída atual.
    private func reconcileTaps() {
        let processes = audioProcessesByApp()
        var runningBundleIDs = Set<String>()

        for app in regularApps() {
            guard let bundleID = app.bundleIdentifier, runningBundleIDs.insert(bundleID).inserted else { continue }

            let setting = setting(for: bundleID)
            let objectIDs = (processes[app.processIdentifier] ?? []).map(\.objectID).sorted()

            guard !setting.isDefault, !objectIDs.isEmpty, !outputDeviceUID.isEmpty else {
                taps.removeValue(forKey: bundleID)?.invalidate()
                continue
            }

            if let tap = taps[bundleID], tap.processObjectIDs == objectIDs, tap.outputDeviceUID == outputDeviceUID {
                tap.gain = setting.gain
                continue
            }

            taps.removeValue(forKey: bundleID)?.invalidate()
            do {
                taps[bundleID] = try ProcessTap(processObjectIDs: objectIDs, outputDeviceUID: outputDeviceUID, gain: setting.gain)
            } catch {
                NSLog("SoundMenu: não foi possível controlar \(bundleID): \(error)")
            }
        }

        for bundleID in taps.keys where !runningBundleIDs.contains(bundleID) {
            taps.removeValue(forKey: bundleID)?.invalidate()
        }
    }

    /// Agrupa os processos de áudio pelo app dono (pid do app principal).
    private func audioProcessesByApp() -> [pid_t: [AudioProcess]] {
        let apps = regularApps()
        let appPIDs = Set(apps.map(\.processIdentifier))
        var result: [pid_t: [AudioProcess]] = [:]

        for process in AudioProcess.all() where process.pid != getpid() {
            if let owner = owner(of: process, apps: apps, appPIDs: appPIDs) {
                result[owner, default: []].append(process)
            }
        }
        return result
    }

    private func owner(of process: AudioProcess, apps: [NSRunningApplication], appPIDs: Set<pid_t>) -> pid_t? {
        if appPIDs.contains(process.pid) { return process.pid }
        if appPIDs.contains(process.responsiblePID) { return process.responsiblePID }

        // Fallback: helpers com bundle ID derivado do app (ex.: com.google.Chrome.helper).
        guard let bundleID = process.bundleID else { return nil }
        return apps.first { app in
            guard let appBundleID = app.bundleIdentifier else { return false }
            return bundleID.hasPrefix(appBundleID + ".")
        }?.processIdentifier
    }

    private func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
    }

    // MARK: - Persistência

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
              let saved = try? JSONDecoder().decode([String: VolumeSetting].self, from: data) else { return }
        settings = saved
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
