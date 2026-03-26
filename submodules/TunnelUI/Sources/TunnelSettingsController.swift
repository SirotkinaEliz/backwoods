import Foundation
import UIKit
import SwiftSignalKit
import TunnelKit
import TunnelManager

// Backwoods: TunnelSettingsController
// VPN settings & debug screen.
// Shows connection status, server info, logs, and reconnect controls.
// Follows Telegram's ItemListController UI pattern (table-based settings).

public final class TunnelSettingsController: UITableViewController {
    
    // MARK: - Section / Row Model
    
    private enum Section: Int, CaseIterable {
        case status = 0
        case connection = 1
        case actions = 2
        case debug = 3
    }
    
    private enum StatusRow: Int, CaseIterable {
        case statusIndicator = 0
        case uptime = 1
    }
    
    private enum ConnectionRow: Int, CaseIterable {
        case server = 0
        case protocol_ = 1
        case mtu = 2
    }
    
    private enum ActionRow: Int, CaseIterable {
        case connectToggle = 0
        case reconnect = 1
    }
    
    private enum DebugRow: Int, CaseIterable {
        case viewLogs = 0
        case copyConfig = 1
        case clearLogs = 2
    }
    
    // MARK: - Properties
    
    private var currentStatus: TransportStatus = .disconnected
    private var statusDisposable: Disposable?
    private var connectStartTime: Date?
    private var uptimeTimer: Timer?
    
    // MARK: - Section Headers (Russian)
    
    private let sectionHeaders: [Section: String] = [
        .status: "Статус",
        .connection: "Соединение",
        .actions: "Управление",
        .debug: "Отладка"
    ]
    
    // MARK: - Lifecycle
    
    public init() {
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        statusDisposable?.dispose()
        uptimeTimer?.invalidate()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "VPN Туннель"
        navigationItem.largeTitleDisplayMode = .never
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "actionCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "destructiveCell")
        
        bindToTunnelManager()
        startUptimeTimer()
    }
    
    // MARK: - Binding
    
    private func bindToTunnelManager() {
        statusDisposable = (TunnelManager.shared.status
        |> deliverOnMainQueue).start(next: { [weak self] status in
            let previousStatus = self?.currentStatus
            self?.currentStatus = status
            
            if case .connected = status, previousStatus != .some(.connected) {
                self?.connectStartTime = Date()
            } else if case .disconnected = status {
                self?.connectStartTime = nil
            }
            
            self?.tableView.reloadData()
        })
    }
    
    // MARK: - Uptime Timer
    
    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, case .connected = self.currentStatus else { return }
            // Only reload the uptime row
            let indexPath = IndexPath(row: StatusRow.uptime.rawValue, section: Section.status.rawValue)
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
    
    // MARK: - UITableViewDataSource
    
    public override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .status: return StatusRow.allCases.count
        case .connection: return ConnectionRow.allCases.count
        case .actions: return ActionRow.allCases.count
        case .debug: return DebugRow.allCases.count
        }
    }
    
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        return sectionHeaders[section]
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .status:
            return configureStatusCell(for: indexPath)
        case .connection:
            return configureConnectionCell(for: indexPath)
        case .actions:
            return configureActionCell(for: indexPath)
        case .debug:
            return configureDebugCell(for: indexPath)
        }
    }
    
    // MARK: - Cell Configuration
    
    private func configureStatusCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none
        
        guard let row = StatusRow(rawValue: indexPath.row) else { return cell }
        
        var config = cell.defaultContentConfiguration()
        
        switch row {
        case .statusIndicator:
            config.text = "Статус"
            config.secondaryText = statusText(for: currentStatus)
            config.secondaryTextProperties.color = statusColor(for: currentStatus)
            config.secondaryTextProperties.font = .systemFont(ofSize: 15, weight: .semibold)
            
        case .uptime:
            config.text = "Время работы"
            config.secondaryText = formattedUptime()
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    private func configureConnectionCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none
        
        guard let row = ConnectionRow(rawValue: indexPath.row) else { return cell }
        
        // Load current configuration for display
        let configuration = TransportConfiguration.loadEmbedded()
        
        var config = cell.defaultContentConfiguration()
        
        switch row {
        case .server:
            config.text = "Сервер"
            config.secondaryText = configuration?.wireGuard?.peer.endpoint ?? "Не настроен"
            
        case .protocol_:
            config.text = "Протокол"
            config.secondaryText = "WireGuard"
            
        case .mtu:
            config.text = "MTU"
            config.secondaryText = "\(configuration?.wireGuard?.interface.mtu ?? TunnelConstants.WireGuard.defaultMTU)"
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    private func configureActionCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "actionCell", for: indexPath)
        
        guard let row = ActionRow(rawValue: indexPath.row) else { return cell }
        
        var config = cell.defaultContentConfiguration()
        
        switch row {
        case .connectToggle:
            let isConnected = currentStatus == .connected || currentStatus == .connecting || currentStatus == .reconnecting
            config.text = isConnected ? "Отключить VPN" : "Подключить VPN"
            config.textProperties.color = isConnected ? .systemRed : .systemBlue
            config.textProperties.alignment = .center
            
        case .reconnect:
            config.text = "Переподключить"
            config.textProperties.color = .systemOrange
            config.textProperties.alignment = .center
            let isActive = currentStatus == .connected || currentStatus == .connecting || currentStatus == .reconnecting
            cell.isUserInteractionEnabled = isActive
            cell.contentView.alpha = isActive ? 1.0 : 0.4
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    private func configureDebugCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = DebugRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }
        
        let cell: UITableViewCell
        var config: UIListContentConfiguration
        
        switch row {
        case .viewLogs:
            cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            config = cell.defaultContentConfiguration()
            config.text = "Просмотр логов"
            cell.accessoryType = .disclosureIndicator
            
        case .copyConfig:
            cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            config = cell.defaultContentConfiguration()
            config.text = "Скопировать конфигурацию"
            
        case .clearLogs:
            cell = tableView.dequeueReusableCell(withIdentifier: "destructiveCell", for: indexPath)
            config = cell.defaultContentConfiguration()
            config.text = "Очистить логи"
            config.textProperties.color = .systemRed
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .status:
            break
        case .connection:
            break
        case .actions:
            handleActionSelection(at: indexPath)
        case .debug:
            handleDebugSelection(at: indexPath)
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleActionSelection(at indexPath: IndexPath) {
        guard let row = ActionRow(rawValue: indexPath.row) else { return }
        
        switch row {
        case .connectToggle:
            let isConnected = currentStatus == .connected || currentStatus == .connecting || currentStatus == .reconnecting
            if isConnected {
                TunnelManager.shared.stopTunnel()
            } else {
                let _ = TunnelManager.shared.ensureConnected()
            }
            
        case .reconnect:
            TunnelManager.shared.reconnect()
        }
    }
    
    private func handleDebugSelection(at indexPath: IndexPath) {
        guard let row = DebugRow(rawValue: indexPath.row) else { return }
        
        switch row {
        case .viewLogs:
            showLogs()
            
        case .copyConfig:
            copyConfigToClipboard()
            
        case .clearLogs:
            confirmClearLogs()
        }
    }
    
    // MARK: - Debug Actions
    
    private func showLogs() {
        let logsVC = TunnelLogsViewController()
        navigationController?.pushViewController(logsVC, animated: true)
    }
    
    private func copyConfigToClipboard() {
        guard let config = TransportConfiguration.loadEmbedded() else {
            showToast("Конфигурация не найдена")
            return
        }
        
        // Redact private key for safety
        var description = "Сервер: \(config.wireGuard?.peer.endpoint ?? "?")\n"
        description += "Протокол: WireGuard\n"
        description += "MTU: \(config.wireGuard?.interface.mtu ?? TunnelConstants.WireGuard.defaultMTU)\n"
        description += "DNS: \(config.wireGuard?.interface.dns.joined(separator: ", ") ?? "?")\n"
        description += "Allowed IPs: \(config.wireGuard?.peer.allowedIPs.joined(separator: ", ") ?? "?")"
        
        UIPasteboard.general.string = description
        showToast("Скопировано")
    }
    
    private func confirmClearLogs() {
        let alert = UIAlertController(
            title: "Очистить логи?",
            message: "Все логи туннеля будут удалены.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Очистить", style: .destructive) { [weak self] _ in
            TunnelLogger.clearSharedLog()
            self?.showToast("Логи очищены")
        })
        present(alert, animated: true)
    }
    
    // MARK: - Helpers
    
    private func statusText(for status: TransportStatus) -> String {
        switch status {
        case .connected: return "Подключено"
        case .connecting: return "Подключение..."
        case .reconnecting: return "Переподключение..."
        case .disconnected: return "Отключено"
        case .disconnecting: return "Отключение..."
        case .failed: return "Ошибка"
        }
    }
    
    private func statusColor(for status: TransportStatus) -> UIColor {
        switch status {
        case .connected: return .systemGreen
        case .connecting, .reconnecting: return .systemOrange
        case .disconnected, .disconnecting: return .systemGray
        case .failed: return .systemRed
        }
    }
    
    private func formattedUptime() -> String {
        guard let start = connectStartTime else { return "—" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }
}

// MARK: - TunnelLogsViewController

/// Simple log viewer — displays the shared tunnel log file.
public final class TunnelLogsViewController: UIViewController {
    
    private let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        tv.textColor = UIColor(red: 0.0, green: 0.9, blue: 0.4, alpha: 1.0) // Terminal green
        return tv
    }()
    
    private var logsDisposable: Disposable?
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Логи туннеля"
        view.backgroundColor = textView.backgroundColor
        
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Обновить", style: .plain, target: self, action: #selector(refreshLogs)),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareLogs))
        ]
        
        loadLogs()
        
        // Also request logs from extension via IPC
        requestExtensionLogs()
    }
    
    deinit {
        logsDisposable?.dispose()
    }
    
    private func loadLogs() {
        let logs = TunnelLogger.readSharedLog()
        textView.text = logs.isEmpty ? "Логов пока нет." : logs
        
        // Scroll to bottom
        if !logs.isEmpty {
            let range = NSMakeRange(textView.text.count - 1, 1)
            textView.scrollRangeToVisible(range)
        }
    }
    
    private func requestExtensionLogs() {
        logsDisposable = (TunnelManager.shared.requestLogs()
        |> deliverOnMainQueue).start(next: { [weak self] logs in
            guard let self = self, !logs.isEmpty else { return }
            let separator = "\n\n=== Логи расширения ===\n\n"
            self.textView.text = (self.textView.text ?? "") + separator + logs
        })
    }
    
    @objc private func refreshLogs() {
        loadLogs()
        requestExtensionLogs()
    }
    
    @objc private func shareLogs() {
        let logs = textView.text ?? ""
        let activityVC = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
        present(activityVC, animated: true)
    }
}
