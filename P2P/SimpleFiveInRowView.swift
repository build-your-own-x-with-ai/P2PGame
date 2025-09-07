import SwiftUI

struct SimpleFiveInRowView: View {
    @StateObject private var game: SimpleFiveInRowGame
    @ObservedObject var p2pManager: P2PManager
    
    init(p2pManager: P2PManager) {
        self.p2pManager = p2pManager
        let isHost = p2pManager.wasHost
        self._game = StateObject(wrappedValue: SimpleFiveInRowGame(isHost: isHost))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("五子棋")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("你是: \(game.isHost ? "黑棋(先手)" : "白棋")")
                    .font(.headline)
                Spacer()
                Text(game.isMyTurn ? "你的回合" : "对手回合")
                    .font(.headline)
            }
            .padding(.horizontal)
            
            // Board with intersection points
            ZStack {
                // Background
                Rectangle()
                    .fill(Color.yellow.opacity(0.3))
                    .frame(width: 360, height: 360)
                
                // Grid lines
                Canvas { context, size in
                    let spacing = size.width / 14 // 14 spaces for 15 points
                    
                    // Vertical lines
                    for i in 0..<15 {
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: CGFloat(i) * spacing, y: 0))
                                path.addLine(to: CGPoint(x: CGFloat(i) * spacing, y: size.height))
                            },
                            with: .color(.black),
                            lineWidth: 1
                        )
                    }
                    
                    // Horizontal lines
                    for i in 0..<15 {
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: CGFloat(i) * spacing))
                                path.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * spacing))
                            },
                            with: .color(.black),
                            lineWidth: 1
                        )
                    }
                    
                    // Draw pieces on intersections
                    for row in 0..<15 {
                        for col in 0..<15 {
                            if game.board[row][col] != 0 {
                                let x = CGFloat(col) * spacing
                                let y = CGFloat(row) * spacing
                                
                                let circle = Path(ellipseIn: CGRect(
                                    x: x - spacing * 0.4,
                                    y: y - spacing * 0.4,
                                    width: spacing * 0.8,
                                    height: spacing * 0.8
                                ))
                                
                                if game.board[row][col] == 1 {
                                    context.fill(circle, with: .color(.black))
                                } else {
                                    context.fill(circle, with: .color(.white))
                                    context.stroke(circle, with: .color(.black), lineWidth: 1)
                                }
                            }
                        }
                    }
                }
                .frame(width: 360, height: 360)
                .onTapGesture { location in
                    let spacing = 360.0 / 14.0
                    let col = Int(round(location.x / spacing))
                    let row = Int(round(location.y / spacing))
                    
                    if row >= 0 && row < 15 && col >= 0 && col < 15 {
                        game.makeMove(row: row, col: col, p2pManager: p2pManager)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            if let winner = game.winner {
                Text("\(winner == 1 ? "黑棋" : "白棋") 获胜!")
                    .font(.title)
                    .foregroundColor(.green)
            }
            
            Button("重新开始") {
                game.reset()
            }
            .buttonStyle(.borderedProminent)
        }
        .onReceive(p2pManager.$receivedData) { data in
            guard let data = data else { return }
            
            if let gameMove = try? JSONDecoder().decode(GameMove.self, from: data),
               gameMove.gameType == .fiveInRow,
               let move = try? JSONDecoder().decode(SimpleFiveMove.self, from: gameMove.moveData) {
                game.receiveMove(move)
            }
        }
    }
}

struct SimpleFiveMove: Codable {
    let row: Int
    let col: Int
    let player: Int
}

@MainActor
class SimpleFiveInRowGame: ObservableObject {
    @Published var board: [[Int]] = Array(repeating: Array(repeating: 0, count: 15), count: 15)
    @Published var currentPlayer = 1 // 1 = black, 2 = white
    @Published var winner: Int?
    @Published var isMyTurn: Bool
    @Published var isHost: Bool
    
    init(isHost: Bool) {
        self.isHost = isHost
        self.isMyTurn = isHost // 主机先手
    }
    
    func makeMove(row: Int, col: Int, p2pManager: P2PManager?) {
        guard board[row][col] == 0, winner == nil, isMyTurn else { return }
        
        let playerColor = isHost ? 1 : 2
        board[row][col] = playerColor
        
        if checkWin(row, col) {
            winner = playerColor
        }
        
        // Send move to other player
        let move = SimpleFiveMove(row: row, col: col, player: playerColor)
        if let moveData = try? JSONEncoder().encode(move),
           let gameMove = try? JSONEncoder().encode(GameMove(gameType: .fiveInRow, moveData: moveData)) {
            p2pManager?.send(gameMove)
        }
        
        isMyTurn = false
        currentPlayer = currentPlayer == 1 ? 2 : 1
    }
    
    func receiveMove(_ move: SimpleFiveMove) {
        DispatchQueue.main.async {
            self.board[move.row][move.col] = move.player
            
            if self.checkWin(move.row, move.col) {
                self.winner = move.player
            }
            
            self.isMyTurn = true
            self.currentPlayer = self.currentPlayer == 1 ? 2 : 1
        }
    }
    
    private func checkWin(_ row: Int, _ col: Int) -> Bool {
        let player = board[row][col]
        let directions = [
            [(0, 1), (0, -1)],
            [(1, 0), (-1, 0)],
            [(1, 1), (-1, -1)],
            [(1, -1), (-1, 1)]
        ]
        
        for direction in directions {
            var count = 1
            for (dr, dc) in direction {
                var r = row + dr
                var c = col + dc
                while r >= 0 && r < 15 && c >= 0 && c < 15 && board[r][c] == player {
                    count += 1
                    r += dr
                    c += dc
                }
            }
            if count >= 5 {
                return true
            }
        }
        return false
    }
    
    func reset() {
        board = Array(repeating: Array(repeating: 0, count: 15), count: 15)
        currentPlayer = 1
        winner = nil
        isMyTurn = isHost
    }
}