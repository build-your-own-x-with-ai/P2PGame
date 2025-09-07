//
//  ContentView.swift
//  P2P
//
//  Created by i on 2025/9/7.
//

import SwiftUI
import MultipeerConnectivity

enum GameType: String, CaseIterable {
    case fiveInRow = "五子棋"
    case chineseChess = "中国象棋"
}

struct ContentView: View {
    @StateObject private var p2pManager = P2PManager()
    @State private var selectedGame: GameType?
    @State private var showGameView = false
    @State private var connectingPeer: MCPeerID? = nil
    @State private var showInviteAlert: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("P2P 棋类游戏")
                    .font(.largeTitle)
                    .padding()
                
                VStack(spacing: 10) {
                    Text("连接状态")
                        .font(.headline)
                    
                    Text(p2pManager.connectionStatus)
                        .foregroundColor(p2pManager.isConnected ? .green : (p2pManager.isHosting || p2pManager.isBrowsing) ? .blue : .gray)
                        .padding()
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 20) {
                        Button("创建房间") {
                            p2pManager.startHosting()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(p2pManager.isConnected || p2pManager.isHosting)
                        
                        Button("加入房间") {
                            p2pManager.startBrowsing()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(p2pManager.isConnected || p2pManager.isBrowsing)
                        
                        if p2pManager.isConnected {
                            Button("断开连接") {
                                p2pManager.disconnect()
                                showGameView = false
                                selectedGame = nil
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                    }
                    
                    // 显示正在进行的操作的停止按钮
                    if p2pManager.isHosting && !p2pManager.isConnected {
                        Button("停止创建房间") {
                            p2pManager.stopHosting()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.orange)
                    }
                    
                    if p2pManager.isBrowsing && !p2pManager.isConnected {
                        Button("停止搜索") {
                            p2pManager.stopBrowsing()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // 显示发现的设备列表
                if p2pManager.isBrowsing && !p2pManager.discoveredPeers.isEmpty {
                    VStack(spacing: 10) {
                        Text("发现的房间")
                            .font(.headline)
                        
                        ForEach(p2pManager.discoveredPeers, id: \.self) { peer in
                            HStack {
                                Image(systemName: "person.circle")
                                Text(peer.displayName)
                                Spacer()
                                if connectingPeer == peer && !p2pManager.isConnected {
                                    Text("连接中...")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                } else {
                                    Button("连接") {
                                        connectingPeer = peer
                                        p2pManager.connectToPeer(peer)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(p2pManager.isConnected || connectingPeer != nil)
                                }
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
                }
                
                if p2pManager.isConnected {
                    VStack(spacing: 15) {
                        Text("选择游戏")
                            .font(.headline)
                        
                        NavigationLink(destination: SimpleFiveInRowView(p2pManager: p2pManager)) {
                            HStack {
                                Image(systemName: "circle.grid.3x3")
                                    .font(.title2)
                                Text("五子棋")
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                        
                        NavigationLink(destination: SimpleChineseChessView(p2pManager: p2pManager)) {
                            HStack {
                                Image(systemName: "square.grid.3x3")
                                    .font(.title2)
                                Text("中国象棋")
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .padding()
            .alert("收到连接请求", isPresented: $showInviteAlert, presenting: p2pManager.pendingInvitationPeer) { peer in
                Button("接受") { p2pManager.acceptInvitation() }
                Button("拒绝", role: .cancel) { p2pManager.declineInvitation() }
            } message: { peer in
                Text("\(peer.displayName) 请求连接")
            }
            .onReceive(p2pManager.$pendingInvitationPeer) { peer in
                showInviteAlert = (peer != nil)
            }
            .onReceive(p2pManager.$connectionStatus) { status in
                if p2pManager.isConnected
                    || status.contains("失败")
                    || status.contains("断开")
                    || status.contains("超时")
                    || status == "未连接" {
                    connectingPeer = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
