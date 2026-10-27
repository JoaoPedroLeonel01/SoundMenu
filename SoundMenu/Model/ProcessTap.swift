//
//  ProcessTap.swift
//  SoundMenu
//
//  Captura o áudio de um app, silencia a saída original e o reproduz de novo
//  no dispositivo de saída atual com o ganho escolhido.
//
//  Fluxo: CATapDescription (muteBehavior = .muted) -> aggregate device privado
//  (tap como entrada + dispositivo de saída) -> IOProc que copia entrada * ganho.
//

import CoreAudio
import Foundation
import Synchronization

/// Ganho compartilhado com a thread de áudio em tempo real, sem locks.
nonisolated final class AtomicGain: Sendable {
    private let bits: Atomic<UInt32>

    init(_ value: Float) { bits = Atomic(value.bitPattern) }

    var value: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

nonisolated final class ProcessTap {
    let processObjectIDs: [AudioObjectID]
    let outputDeviceUID: String

    private let gainStorage: AtomicGain
    private let ioQueue = DispatchQueue(label: "SoundMenu.ProcessTap", qos: .userInteractive)
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    var gain: Float {
        get { gainStorage.value }
        set { gainStorage.value = newValue }
    }

    init(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        self.gainStorage = AtomicGain(gain)

        do {
            try start()
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if aggregateID != .unknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = .unknown
        tapID = .unknown
    }

    private func start() throws {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .muted
        tapDescription.isPrivate = true
        try checkStatus(AudioHardwareCreateProcessTap(tapDescription, &tapID), "Criar process tap")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundMenu Tap",
            kAudioAggregateDeviceUIDKey: OutputDevice.internalUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        try checkStatus(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
                        "Criar aggregate device")

        let gainStorage = gainStorage
        try checkStatus(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { _, input, _, output, _ in
            ProcessTap.render(from: input, to: output, gain: gainStorage.value)
        }, "Criar IOProc")
        try checkStatus(AudioDeviceStart(aggregateID, ioProcID), "Iniciar aggregate device")
    }

    // Roda na thread de áudio em tempo real: nada de alocação nem locks aqui.
    private static func render(from input: UnsafePointer<AudioBufferList>,
                               to output: UnsafeMutablePointer<AudioBufferList>,
                               gain: Float) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
        var outputChannel = 0

        for buffer in outputBuffers {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))

            let stride = Int(buffer.mNumberChannels)
            guard stride > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let frameCount = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride)

            for offset in 0..<stride {
                defer { outputChannel += 1 }
                guard let source = channel(outputChannel, in: inputBuffers) else { continue }

                for frame in 0..<min(frameCount, source.frameCount) {
                    samples[frame * stride + offset] = source.samples[frame * source.stride] * gain
                }
            }
        }
    }

    /// Localiza o canal `index` da entrada, seja ela intercalada ou não.
    private static func channel(_ index: Int, in buffers: UnsafeMutableAudioBufferListPointer)
        -> (samples: UnsafePointer<Float>, stride: Int, frameCount: Int)? {
        var firstChannel = 0
        for buffer in buffers {
            let channelCount = Int(buffer.mNumberChannels)
            if channelCount > 0, index < firstChannel + channelCount, let data = buffer.mData {
                let samples = data.assumingMemoryBound(to: Float.self) + (index - firstChannel)
                let frameCount = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channelCount)
                return (UnsafePointer(samples), channelCount, frameCount)
            }
            firstChannel += channelCount
        }
        return nil
    }
}
