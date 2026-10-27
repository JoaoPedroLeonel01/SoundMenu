//
//  AudioPermission.swift
//  SoundMenu
//
//  Permissão de "Gravação de Áudio do Sistema", necessária para os process taps.
//
//  O macOS não tem API pública para consultar ou pedir essa permissão, então usamos
//  o framework privado TCC (o mesmo caminho do projeto de exemplo AudioCap).
//  Se ele não estiver disponível, o status fica `.unknown` e o sistema pede a
//  permissão sozinho na primeira vez que um tap for criado.
//

import Foundation

nonisolated enum AudioPermission {
    enum Status {
        case authorized, denied, unknown
    }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tccHandle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static var status: Status {
        guard let symbol = dlsym(tccHandle, "TCCAccessPreflight") else { return .unknown }
        let preflight = unsafeBitCast(symbol, to: PreflightFunction.self)

        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Mostra o pedido do sistema (se ainda não foi respondido) e devolve o resultado na main queue.
    static func request(completion: @escaping @MainActor (Bool) -> Void) {
        guard let symbol = dlsym(tccHandle, "TCCAccessRequest") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let request = unsafeBitCast(symbol, to: RequestFunction.self)
        request(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
