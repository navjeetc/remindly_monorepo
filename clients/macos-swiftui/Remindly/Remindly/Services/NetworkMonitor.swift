import Foundation
import Network
import Combine

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = true
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var forceOffline = false // Debug: manually force offline mode
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    var effectivelyConnected: Bool {
        return isConnected && !forceOffline
    }
    
    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            let isConnected = path.status == .satisfied
            let connectionType = path.availableInterfaces.first?.type
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnected = isConnected
                self.connectionType = connectionType
                
                if isConnected {
                    let typeString: String
                    switch connectionType {
                    case .wifi: typeString = "WiFi"
                    case .cellular: typeString = "Cellular"
                    case .wiredEthernet: typeString = "Ethernet"
                    case .loopback: typeString = "Loopback"
                    default: typeString = "Unknown"
                    }
                    print("📡 Network connected: \(typeString)")
                    // Trigger sync when connection is restored
                    NotificationCenter.default.post(name: .networkConnected, object: nil)
                } else {
                    print("📡 Network disconnected")
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
}

extension Notification.Name {
    static let networkConnected = Notification.Name("networkConnected")
}
