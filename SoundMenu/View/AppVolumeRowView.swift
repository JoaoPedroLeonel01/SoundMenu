//
//  AppVolumeRowView.swift
//  SoundMenu
//
//  Linha do menu para um app: ícone, nome, porcentagem, botão de mudo e slider.
//  A view não conhece o model; ela só repassa as ações para o delegate (controller).
//

import AppKit

protocol AppVolumeRowViewDelegate: AnyObject {
    func rowView(_ rowView: AppVolumeRowView, didChangeVolume volume: Float)
    func rowViewDidToggleMute(_ rowView: AppVolumeRowView)
}

final class AppVolumeRowView: NSView {
    let bundleID: String
    weak var delegate: AppVolumeRowViewDelegate?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let playingIndicator = NSImageView()
    private let percentLabel = NSTextField(labelWithString: "")
    private let muteButton = NSButton()
    private let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)

    init(bundleID: String) {
        self.bundleID = bundleID
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        setUpViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, icon: NSImage?, isPlaying: Bool) {
        nameLabel.stringValue = name
        iconView.image = icon
        playingIndicator.isHidden = !isPlaying
    }

    func update(volume: Float, isMuted: Bool) {
        slider.floatValue = volume
        percentLabel.stringValue = isMuted ? "Mudo" : "\(Int((volume * 100).rounded()))%"

        let symbol: String
        if isMuted || volume == 0 {
            symbol = "speaker.slash.fill"
        } else if volume < 0.34 {
            symbol = "speaker.wave.1.fill"
        } else if volume < 0.67 {
            symbol = "speaker.wave.2.fill"
        } else {
            symbol = "speaker.wave.3.fill"
        }
        muteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: isMuted ? "Ativar som" : "Silenciar")
        muteButton.contentTintColor = isMuted ? .systemRed : .secondaryLabelColor
    }

    // MARK: - Ações

    @objc private func sliderChanged(_ sender: NSSlider) {
        delegate?.rowView(self, didChangeVolume: sender.floatValue)
    }

    @objc private func muteClicked(_ sender: NSButton) {
        delegate?.rowViewDidToggleMute(self)
    }

    // MARK: - Layout

    private func setUpViews() {
        iconView.imageScaling = .scaleProportionallyUpOrDown

        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        playingIndicator.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Tocando")
        playingIndicator.contentTintColor = .controlAccentColor
        playingIndicator.symbolConfiguration = .init(pointSize: 10, weight: .semibold)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right

        muteButton.isBordered = false
        muteButton.imagePosition = .imageOnly
        muteButton.imageScaling = .scaleProportionallyDown
        muteButton.target = self
        muteButton.action = #selector(muteClicked(_:))

        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged(_:))

        let subviews: [NSView] = [iconView, nameLabel, playingIndicator, percentLabel, muteButton, slider]
        for view in subviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            playingIndicator.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            playingIndicator.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            playingIndicator.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),

            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            percentLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 44),

            muteButton.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            muteButton.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            muteButton.widthAnchor.constraint(equalToConstant: 20),
            muteButton.heightAnchor.constraint(equalToConstant: 18),

            slider.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: percentLabel.trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: muteButton.centerYAnchor),
        ])
    }
}
