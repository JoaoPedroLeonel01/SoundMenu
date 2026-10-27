//
//  OutputDevice.swift
//  SoundMenu
//
//  Dispositivo de saída de áudio (alto-falantes, fones com fio, AirPods...).
//

import CoreAudio
import Foundation

nonisolated struct OutputDevice {
    /// Prefixo do UID dos aggregate devices criados pelo próprio SoundMenu, que não devem aparecer na lista.
    static let internalUIDPrefix = "SoundMenu-"

    let id: AudioObjectID
    let uid: String
    let name: String

    static var current: OutputDevice? {
        guard let id = try? AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown),
              id != .unknown else { return nil }
        return OutputDevice(id: id)
    }

    /// Todos os dispositivos que têm ao menos um stream de saída.
    static func all() -> [OutputDevice] {
        let ids = (try? AudioObjectID.system.readObjectList(kAudioHardwarePropertyDevices)) ?? []

        return ids
            .filter { id in
                let streams = (try? id.readObjectList(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)) ?? []
                return !streams.isEmpty
            }
            .compactMap(OutputDevice.init(id:))
            .filter { !$0.uid.hasPrefix(internalUIDPrefix) }
    }

    /// Torna este dispositivo a saída padrão do sistema (a mesma do menu de som nativo).
    func makeDefault() throws {
        try AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, value: id)
    }

    private init?(id: AudioObjectID) {
        guard let uid = try? id.readString(kAudioDevicePropertyDeviceUID), !uid.isEmpty else { return nil }
        self.id = id
        self.uid = uid
        self.name = (try? id.readString(kAudioObjectPropertyName)) ?? uid
    }
}
