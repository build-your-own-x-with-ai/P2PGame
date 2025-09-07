import Foundation
import MultipeerConnectivity
#if os(iOS)
import UIKit
#endif

// 用于跨执行器传递非 Sendable 对象的轻量包装（开发者需确保使用时机安全）
final class UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@MainActor
class P2PManager: NSObject, ObservableObject {
    private let serviceType = "boardgames-p2p"
    private let myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isConnected = false
    @Published var receivedData: Data?
    @Published var connectionStatus = "Not Connected"
    @Published var discoveredPeers: [MCPeerID] = []
    @Published var isHosting = false
    @Published var isBrowsing = false
    @Published var pendingInvitationPeer: MCPeerID?
    @Published var wasHost = false // 记录是否是创建房间的人
    private var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?
    
    private var connectionTimer: Timer?
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 3
    
    override init() {
        #if os(iOS)
        // 使用设备的实际名称而不是固定的"iPhone"
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        #else
        self.myPeerID = MCPeerID(displayName: ProcessInfo.processInfo.hostName)
        #endif
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        self.session.delegate = self
    }
    
    func startHosting() {
        stopBrowsing() // 停止搜索
        discoveredPeers.removeAll()
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        isHosting = true
        wasHost = true // 记录创建了房间
        isBrowsing = false
        connectionStatus = "正在创建房间..."
        
        print("开始创建房间，设备名: \(myPeerID.displayName)")
    }
    
    func startBrowsing() {
        stopHosting() // 停止创建房间
        discoveredPeers.removeAll()
        
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        isHosting = false
        wasHost = false // 记录加入了房间
        isBrowsing = true
        connectionStatus = "正在搜索房间..."
        
        print("开始搜索房间，设备名: \(myPeerID.displayName)")
    }
    
    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isHosting = false
        if !isConnected {
            connectionStatus = "未连接"
        }
        print("停止创建房间")
    }
    
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        discoveredPeers.removeAll()
        if !isConnected {
            connectionStatus = "未连接"
        }
        print("停止搜索房间")
    }
    
    func disconnect() {
        stopConnectionTimer()
        reconnectAttempts = 0
        session.disconnect()
        stopHosting()
        stopBrowsing()
        discoveredPeers.removeAll()
        pendingInvitationPeer = nil
        pendingInvitationHandler = nil
        // 注意：保持 wasHost 不变，以记住角色
        isHosting = false
        isBrowsing = false
        connectionStatus = "未连接"
        print("断开连接，但保持角色记忆: \(wasHost ? "主机" : "客机")")
    }
    
    func send(_ data: Data) {
        print("==== P2P send 开始 ====")
        print("数据大小: \(data.count) 字节")
        print("连接对等方数: \(connectedPeers.count)")
        print("对等方: \(connectedPeers.map { $0.displayName })")
        
        guard !connectedPeers.isEmpty else {
            print("错误：没有连接的对等方！")
            return
        }
        
        do {
            try session.send(data, toPeers: connectedPeers, with: .reliable)
            print("数据发送成功")
        } catch {
            print("发送数据失败: \(error)")
            print("错误详情: \(error.localizedDescription)")
        }
        print("==== P2P send 结束 ====")
    }
    
    func sendGameMove(_ move: GameMove) {
        guard let data = try? JSONEncoder().encode(move) else { return }
        send(data)
    }
    
    func connectToPeer(_ peerID: MCPeerID) {
        guard let browser = browser else {
            print("Browser未初始化")
            return
        }
        
        guard session.connectedPeers.isEmpty else {
            print("已有连接，无法连接到新设备")
            return
        }
        
        print("手动连接到 \(peerID.displayName)")
        connectionStatus = "正在连接到 \(peerID.displayName)..."
        
        // 设置连接超时
        startConnectionTimer(for: peerID)
        
        let currentBrowser = browser
        let currentSession = session
        let queue = DispatchQueue(label: "p2p.invite.queue", qos: .userInitiated)
        queue.async {
            currentBrowser.invitePeer(peerID, to: currentSession, withContext: nil, timeout: 15)
        }
    }
    
    private func startConnectionTimer(for peerID: MCPeerID) {
        let name = peerID.displayName
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            let timer = Timer(timeInterval: 15.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if !self.isConnected {
                        print("连接超时: \(name)")
                        self.handleConnectionFailure(forPeerNamed: name)
                    }
                }
            }
            self.connectionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            print("已启动连接超时计时器 (15s, common runloop) for \(name)")
        }
    }
    
    private func handleConnectionFailure(forPeerNamed name: String) {
        stopConnectionTimer()
        print("连接超时或失败，等待用户手动重试: \(name)")
        connectionStatus = "连接超时，请手动重试"
        reconnectAttempts = 0
        // 不自动重连，不自动切换角色，保持当前 browsing/hosting 状态
    }
    
    private func resetConnectionAndRetry(for peerID: MCPeerID) {
        // 重新创建session
        session.disconnect()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // 如果是browser端，重新尝试连接
        if isBrowsing, let browser = browser {
            print("重新尝试连接到 \(peerID.displayName)")
            startConnectionTimer(for: peerID)
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        }
        // 如果是advertiser端，重新开始广播
        else if isHosting {
            stopHosting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startHosting()
            }
        }
    }
    
    private func stopConnectionTimer() {
        DispatchQueue.main.async {
            if let t = self.connectionTimer {
                t.invalidate()
                self.connectionTimer = nil
                print("已停止连接超时计时器")
            }
        }
    }
    
    // 手动处理来自对端的邀请
    func acceptInvitation() {
        guard let peer = pendingInvitationPeer, let handler = pendingInvitationHandler else { return }
        startConnectionTimer(for: peer)
        connectionStatus = "正在建立连接..."
        handler(true, session)
        pendingInvitationPeer = nil
        pendingInvitationHandler = nil
    }
    
    func declineInvitation() {
        guard let handler = pendingInvitationHandler else {
            pendingInvitationPeer = nil
            return
        }
        handler(false, nil)
        pendingInvitationPeer = nil
        pendingInvitationHandler = nil
        connectionStatus = "已拒绝连接请求"
    }
    
    func resetConnection() {
        print("重置连接状态")
        session.disconnect()
        
        // 重新创建session
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        connectedPeers.removeAll()
        isConnected = false
        connectionStatus = "连接已重置"
        
        // 如果正在hosting，重新开始
        if isHosting {
            stopHosting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startHosting()
            }
        }
        
        // 如果正在browsing，重新开始
        if isBrowsing {
            stopBrowsing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startBrowsing()
            }
        }
    }
}

extension P2PManager: @preconcurrency MCSessionDelegate {
    nonisolated(unsafe) func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        print("PeerConnection状态变化: \(name) -> \(state)")
        
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.stopConnectionTimer()
                self.reconnectAttempts = 0  // 重置重连计数器
                self.connectedPeers = self.session.connectedPeers
                self.isConnected = true
                self.connectionStatus = "已连接到 \(name)"
                self.stopHosting()
                self.stopBrowsing()
                print("PeerConnection connectedHandler (成功) - 已连接到 \(name)")
            case .connecting:
                self.connectionStatus = "正在连接 \(name)..."
                print("PeerConnection connectingHandler - 正在连接到 \(name)")
            case .notConnected:
                self.stopConnectionTimer()
                self.connectedPeers = self.session.connectedPeers
                self.isConnected = self.connectedPeers.count > 0
                if !self.isConnected {
                    self.connectionStatus = "连接失败或断开"
                    print("PeerConnection connectedHandler (advertiser side) - error [Connection failed or disconnected]")
                }
                print("PeerConnection disconnectedHandler - 与 \(name) 断开连接")
            @unknown default:
                self.stopConnectionTimer()
                print("PeerConnection unknownStateHandler - 未知状态")
                break
            }
        }
    }
    
    nonisolated(unsafe) func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("==== P2P 收到数据 ====")
        print("来自: \(peerID.displayName)")
        print("数据大小: \(data.count) 字节")
        
        DispatchQueue.main.async {
            self.receivedData = data
            print("数据已更新到 receivedData")
        }
        
        print("==== P2P 数据接收完成 ====")
    }
    
    nonisolated(unsafe) func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    nonisolated(unsafe) func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    nonisolated(unsafe) func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    
    // 添加连接错误处理
    nonisolated(unsafe) func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        print("收到来自 \(peerID.displayName) 的证书验证请求")
        certificateHandler(true)
    }
}

extension P2PManager: @preconcurrency MCNearbyServiceAdvertiserDelegate {
    nonisolated(unsafe) func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let name = peerID.displayName
        let handlerBox = UnsafeSendableBox(invitationHandler)
        print("收到来自 \(name) 的连接请求")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionStatus = "收到连接请求来自 \(name)"
            if !self.session.connectedPeers.isEmpty || self.pendingInvitationHandler != nil {
                print("拒绝来自 \(name) 的连接请求 - 已有连接或已有待处理邀请")
                handlerBox.value(false, nil)
                return
            }
            self.pendingInvitationPeer = MCPeerID(displayName: name)
            self.pendingInvitationHandler = { accepted, _ in
                handlerBox.value(accepted, accepted ? self.session : nil)
            }
        }
    }
    
    nonisolated(unsafe) func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("创建房间失败: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.connectionStatus = "创建房间失败: \(error.localizedDescription)"
            self.isHosting = false
        }
    }
}

extension P2PManager: @preconcurrency MCNearbyServiceBrowserDelegate {
    nonisolated(unsafe) func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("发现设备: \(peerID.displayName)")
        let box = UnsafeSendableBox(peerID)
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(box.value) {
                self.discoveredPeers.append(box.value)
            }
            self.connectionStatus = "发现 \(self.discoveredPeers.count) 个房间"
        }
    }
    
    nonisolated(unsafe) func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("设备离开: \(peerID.displayName)")
        let box = UnsafeSendableBox(peerID)
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == box.value }
            if self.discoveredPeers.isEmpty {
                self.connectionStatus = "未发现房间"
            } else {
                self.connectionStatus = "发现 \(self.discoveredPeers.count) 个房间"
            }
        }
    }
    
    nonisolated(unsafe) func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("搜索房间失败: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.connectionStatus = "搜索失败: \(error.localizedDescription)"
            self.isBrowsing = false
        }
    }
}

struct GameMove: Codable {
    let gameType: GameType
    let moveData: Data
    
    enum GameType: String, Codable {
        case fiveInRow = "FiveInRow"
        case chineseChess = "ChineseChess"
    }
}