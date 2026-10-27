//
//  AudioProcess.swift
//  SoundMenu
//
//  Um processo que o Core Audio conhece (qualquer processo que já abriu um cliente de áudio).
//

import CoreAudio
import Foundation

// API do libsystem que devolve o processo "responsável" por outro. Helpers como o
// GPU process do Safari ou os helpers do Chrome tocam áudio em nome do app principal.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
nonisolated private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

nonisolated struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isPlaying: Bool

    var responsiblePID: pid_t {
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        return responsible > 0 ? responsible : pid
    }

    static func all() -> [AudioProcess] {
        guard let objectIDs = try? AudioObjectID.system.readObjectList(kAudioHardwarePropertyProcessObjectList) else {
            return []
        }

        return objectIDs.compactMap { objectID in
            guard let pid = try? objectID.read(kAudioProcessPropertyPID, default: pid_t(-1)), pid > 0 else {
                return nil
            }
            let bundleID = try? objectID.readString(kAudioProcessPropertyBundleID)
            let isRunningOutput = (try? objectID.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0

            return AudioProcess(objectID: objectID,
                                pid: pid,
                                bundleID: bundleID?.isEmpty == false ? bundleID : nil,
                                isPlaying: isRunningOutput != 0)
        }
    }
}
