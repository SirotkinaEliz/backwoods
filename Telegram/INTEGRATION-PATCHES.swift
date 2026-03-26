// Backwoods: AppDelegate Integration Patch
// ==============================================================================
// This file documents the EXACT changes needed in Telegram's AppDelegate.swift.
// Apply as a patch after forking.
//
// File: Telegram/Telegram-iOS/AppDelegate.swift
// ==============================================================================
//
// --- PATCH 1: Import tunnel modules ---
// Location: Top of file, after existing imports
//
//   import TunnelManager  // Backwoods
//
// --- PATCH 2: Tunnel gate in application(_:didFinishLaunchingWithOptions:) ---
// Location: At the VERY BEGINNING of didFinishLaunchingWithOptions, 
//           BEFORE any Telegram networking initialization
//
//   // Backwoods: Initialize VPN tunnel before anything else
//   BackwoodsTunnelBridge.shared.initialize()
//
// --- PATCH 3: Wait for tunnel before presenting UI (optional, strict mode) ---
// Location: Where the root controller is set
//
//   // Backwoods: Wait for tunnel to be ready
//   let _ = (BackwoodsTunnelBridge.shared.tunnelReady.get()
//   |> filter { $0 }
//   |> take(1)
//   |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single(false))
//   |> deliverOnMainQueue).start(next: { ready in
//       if ready {
//           TunnelLogger.shared.log("AppDelegate: туннель готов, запуск UI", level: .info)
//       } else {
//           TunnelLogger.shared.log("AppDelegate: туннель не готов, запуск UI без VPN", level: .warning)
//       }
//       // ... existing UI setup code ...
//   })
//
// ==============================================================================
// IMPORTANT: The tunnel MUST start before Telegram's MTProto connections.
// If the tunnel is not ready, the kill-switch (includeAllNetworks = true)
// will block all network traffic, preventing data leaks.
// ==============================================================================
//
// --- PATCH 4: Status indicator in chat list ---
// Location: In the chat list controller setup (ChatListController or similar)
//
//   // Backwoods: Add VPN status indicator
//   BackwoodsTunnelBridge.shared.installStatusIndicator(in: self.navigationItem)
//
// --- PATCH 5: Settings entry point ---
// Location: In the settings controller (SettingsController or similar),
//           add a new row that opens the tunnel settings
//
//   // Backwoods: VPN tunnel settings entry
//   let tunnelSettingsItem = ItemListDisclosureItem(
//       title: "VPN Туннель",
//       label: "",  // Will be dynamically set from tunnel status
//       sectionId: self.section,
//       style: .blocks,
//       action: {
//           let controller = BackwoodsTunnelBridge.shared.createSettingsController()
//           pushController(controller)
//       }
//   )
