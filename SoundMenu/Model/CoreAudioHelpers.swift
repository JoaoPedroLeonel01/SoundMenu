//
//  CoreAudioHelpers.swift
//  SoundMenu
//
//  Pequenos utilitários para ler propriedades do Core Audio sem repetir boilerplate.
//

import CoreAudio
import Foundation

nonisolated struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let operation: String

    var description: String { "\(operation) falhou (OSStatus \(status))" }
}

nonisolated func checkStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation) }
}

nonisolated extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, default value: T) throws -> T {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        try checkStatus(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &result), "Leitura da propriedade \(selector)")
        return result
    }

    func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, value: T) throws {
        var address = address(selector)
        var value = value
        try checkStatus(AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value),
                        "Escrita da propriedade \(selector)")
    }

    func readObjectList(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        try checkStatus(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "Tamanho da propriedade \(selector)")

        var list = [AudioObjectID](repeating: .unknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try checkStatus(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &list), "Leitura da propriedade \(selector)")
        return list
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try checkStatus(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value), "Leitura da propriedade \(selector)")
        return value?.takeRetainedValue() as String? ?? ""
    }

    /// Chama `handler` na main queue sempre que a propriedade mudar.
    func addListener(_ selector: AudioObjectPropertySelector, handler: @escaping () -> Void) {
        var address = address(selector)
        AudioObjectAddPropertyListenerBlock(self, &address, .main) { _, _ in handler() }
    }
}
