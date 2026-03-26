import Foundation
import UIKit
import SwiftSignalKit
import TunnelKit
import TunnelManager

// Backwoods: TunnelStatusView
// Compact status indicator for the navigation bar.
// Shows a colored dot + text indicating tunnel status.
// Designed to be non-intrusive — follows Telegram's UI patterns.

public final class TunnelStatusView: UIView {
    
    // MARK: - UI Elements
    
    private let statusDot: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Properties
    
    private var statusDisposable: Disposable?
    
    // MARK: - Colors
    
    public struct Theme {
        public let connectedColor: UIColor
        public let connectingColor: UIColor
        public let disconnectedColor: UIColor
        public let errorColor: UIColor
        public let textColor: UIColor
        
        public static let `default` = Theme(
            connectedColor: UIColor(red: 0.29, green: 0.85, blue: 0.39, alpha: 1.0), // Green
            connectingColor: UIColor(red: 1.0, green: 0.79, blue: 0.16, alpha: 1.0),   // Yellow
            disconnectedColor: UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0),    // Gray
            errorColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0),          // Red
            textColor: UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)              // Gray
        )
    }
    
    public var theme: Theme = .default {
        didSet {
            updateAppearance(for: lastStatus)
        }
    }
    
    private var lastStatus: TransportStatus = .disconnected
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        bindToTunnelManager()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        bindToTunnelManager()
    }
    
    deinit {
        statusDisposable?.dispose()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        addSubview(stackView)
        stackView.addArrangedSubview(statusDot)
        stackView.addArrangedSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        updateAppearance(for: .disconnected)
    }
    
    // MARK: - Binding
    
    private func bindToTunnelManager() {
        statusDisposable = (TunnelManager.shared.status
        |> deliverOnMainQueue).start(next: { [weak self] status in
            self?.lastStatus = status
            self?.updateAppearance(for: status)
        })
    }
    
    // MARK: - Appearance
    
    private func updateAppearance(for status: TransportStatus) {
        let color: UIColor
        let text: String
        
        switch status {
        case .connected:
            color = theme.connectedColor
            text = "VPN"
        case .connecting:
            color = theme.connectingColor
            text = "VPN..."
        case .reconnecting:
            color = theme.connectingColor
            text = "VPN..."
        case .disconnected:
            color = theme.disconnectedColor
            text = "VPN ✕"
        case .disconnecting:
            color = theme.disconnectedColor
            text = "VPN..."
        case .failed:
            color = theme.errorColor
            text = "VPN !"
        }
        
        UIView.animate(withDuration: 0.2) {
            self.statusDot.backgroundColor = color
            self.statusLabel.text = text
            self.statusLabel.textColor = self.theme.textColor
        }
        
        // Pulse animation for connecting states
        if case .connecting = status {
            startPulseAnimation()
        } else if case .reconnecting = status {
            startPulseAnimation()
        } else {
            stopPulseAnimation()
        }
    }
    
    // MARK: - Animations
    
    private func startPulseAnimation() {
        guard statusDot.layer.animation(forKey: "pulse") == nil else { return }
        
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        statusDot.layer.add(pulse, forKey: "pulse")
    }
    
    private func stopPulseAnimation() {
        statusDot.layer.removeAnimation(forKey: "pulse")
        statusDot.layer.opacity = 1.0
    }
    
    // MARK: - Public API
    
    /// Update the status manually (for testing / mock mode)
    public func setStatus(_ status: TransportStatus) {
        lastStatus = status
        updateAppearance(for: status)
    }
    
    public override var intrinsicContentSize: CGSize {
        return stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }
}
