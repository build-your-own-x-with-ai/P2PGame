import SwiftUI

struct ChessMove: Codable {
    let fromRow: Int
    let fromCol: Int
    let toRow: Int
    let toCol: Int
}

enum ChessPiece: String, CaseIterable {
    case redGeneral = "帥"
    case redAdvisor = "仕"
    case redElephant = "相"
    case redHorse = "馬"
    case redChariot = "車"
    case redCannon = "炮"
    case redSoldier = "兵"
    
    case blackGeneral = "將"
    case blackAdvisor = "士"
    case blackElephant = "象"
    case blackHorse = "马"
    case blackChariot = "车"
    case blackCannon = "砲"
    case blackSoldier = "卒"
    
    var isRed: Bool {
        switch self {
        case .redGeneral, .redAdvisor, .redElephant, .redHorse, .redChariot, .redCannon, .redSoldier:
            return true
        default:
            return false
        }
    }
}

@MainActor
class ChineseChessGame: ObservableObject {
    @Published var board: [[ChessPiece?]] = []
    @Published var selectedPosition: (row: Int, col: Int)?
    @Published var isRedTurn = true
    @Published var winner: String?
    @Published var isMyTurn = true
    @Published var isHost = false
    @Published var myColor: Bool = true // true for red, false for black
    
    private var p2pManager: P2PManager?
    
    init(p2pManager: P2PManager? = nil, isHost: Bool = false) {
        self.p2pManager = p2pManager
        self.isHost = isHost
        self.myColor = isHost
        self.isMyTurn = isHost
        setupBoard()
    }
    
    func setupBoard() {
        board = Array(repeating: Array(repeating: nil, count: 9), count: 10)
        
        // Red pieces (bottom)
        board[9][0] = .redChariot
        board[9][1] = .redHorse
        board[9][2] = .redElephant
        board[9][3] = .redAdvisor
        board[9][4] = .redGeneral
        board[9][5] = .redAdvisor
        board[9][6] = .redElephant
        board[9][7] = .redHorse
        board[9][8] = .redChariot
        
        board[7][1] = .redCannon
        board[7][7] = .redCannon
        
        for i in stride(from: 0, through: 8, by: 2) {
            board[6][i] = .redSoldier
        }
        
        // Black pieces (top)
        board[0][0] = .blackChariot
        board[0][1] = .blackHorse
        board[0][2] = .blackElephant
        board[0][3] = .blackAdvisor
        board[0][4] = .blackGeneral
        board[0][5] = .blackAdvisor
        board[0][6] = .blackElephant
        board[0][7] = .blackHorse
        board[0][8] = .blackChariot
        
        board[2][1] = .blackCannon
        board[2][7] = .blackCannon
        
        for i in stride(from: 0, through: 8, by: 2) {
            board[3][i] = .blackSoldier
        }
    }
    
    func selectPiece(row: Int, col: Int) {
        print("==== selectPiece 函数开始 ====")
        print("winner: \(winner ?? "无")")
        
        guard winner == nil else { 
            print("游戏已结束，不能移动")
            return 
        }
        
        // 主机控制红方，客机控制黑方
        let shouldBeRed = myColor
        
        print("点击位置: (\(row), \(col)), 我的颜色: \(shouldBeRed ? "红" : "黑"), 是我的回合: \(isMyTurn)")
        print("棋盘该位置: \(board[row][col]?.rawValue ?? "空")")
        
        if let selected = selectedPosition {
            print("已选中棋子在: (\(selected.row), \(selected.col))")
            print("已选中的棋子是: \(board[selected.row][selected.col]?.rawValue ?? "空")")
            
            // 尝试移动棋子
            let canMoveResult = canMove(from: selected, to: (row, col))
            print("canMove结果: \(canMoveResult)")
            
            if canMoveResult {
                if isMyTurn {
                    print("执行移动: (\(selected.row), \(selected.col)) -> (\(row), \(col))")
                    makeMove(from: selected, to: (row, col))
                } else {
                    print("不是你的回合，不能移动")
                }
                selectedPosition = nil
            } else if let piece = board[row][col], piece.isRed == shouldBeRed {
                // 选择新的己方棋子
                print("不能移动到该位置，选择新棋子: \(piece.rawValue)")
                selectedPosition = (row, col)
            } else {
                print("不能移动到该位置，取消选择")
                selectedPosition = nil
            }
        } else if let piece = board[row][col], piece.isRed == shouldBeRed {
            // 第一次选择己方棋子
            print("选择棋子: \(piece.rawValue)")
            selectedPosition = (row, col)
        } else if let piece = board[row][col] {
            print("这是对方的棋子: \(piece.rawValue)，不能选中")
        } else {
            print("点击了空位置，但没有选中的棋子")
        }
        
        print("选中状态更新为: \(selectedPosition != nil ? "(\(selectedPosition!.row), \(selectedPosition!.col))" : "无")")
        print("==== selectPiece 函数结束 ====")
    }
    
    private func makeMove(from: (row: Int, col: Int), to: (row: Int, col: Int)) {
        print("==== makeMove 开始 ====")
        print("从 (\(from.row), \(from.col)) 到 (\(to.row), \(to.col))")
        
        let capturedPiece = board[to.row][to.col]
        board[to.row][to.col] = board[from.row][from.col]
        board[from.row][from.col] = nil
        
        if capturedPiece == .redGeneral {
            winner = "黑方获胜"
        } else if capturedPiece == .blackGeneral {
            winner = "红方获胜"
        }
        
        // 检查P2P连接状态
        if let p2p = p2pManager {
            print("P2P管理器存在")
            print("是否连接: \(p2p.isConnected)")
            print("连接对等方数: \(p2p.connectedPeers.count)")
            print("连接状态: \(p2p.connectionStatus)")
            
            if !p2p.isConnected || p2p.connectedPeers.isEmpty {
                print("警告：P2P未连接或没有对等方！")
            }
        } else {
            print("警告：P2P管理器为nil！")
        }
        
        let move = ChessMove(fromRow: from.row, fromCol: from.col, toRow: to.row, toCol: to.col)
        if let moveData = try? JSONEncoder().encode(move) {
            let gameMove = GameMove(gameType: .chineseChess, moveData: moveData)
            
            // 直接发送，不使用Task
            if let gameData = try? JSONEncoder().encode(gameMove) {
                p2pManager?.send(gameData)
                print("已发送移动数据，大小: \(gameData.count) 字节")
            } else {
                print("错误：无法编码GameMove")
            }
        } else {
            print("错误：无法编码ChessMove")
        }
        
        isRedTurn.toggle()
        isMyTurn = false
        
        print("回合切换: 现在是\(isRedTurn ? "红方" : "黑方")回合")
        print("我的回合: \(isMyTurn)")
        print("==== makeMove 结束 ====")
    }
    
    func receiveMove(_ move: ChessMove) {
        print("==== receiveMove 开始 ====")
        print("收到移动: (\(move.fromRow), \(move.fromCol)) -> (\(move.toRow), \(move.toCol))")
        
        let capturedPiece = board[move.toRow][move.toCol]
        board[move.toRow][move.toCol] = board[move.fromRow][move.fromCol]
        board[move.fromRow][move.fromCol] = nil
        
        if capturedPiece == .redGeneral {
            winner = "黑方获胜"
        } else if capturedPiece == .blackGeneral {
            winner = "红方获胜"
        }
        
        isRedTurn.toggle()
        isMyTurn = true
        
        print("棋盘更新完成")
        print("回合切换: 现在是\(isRedTurn ? "红方" : "黑方")回合")
        print("我的回合: \(isMyTurn)")
        print("==== receiveMove 结束 ====")
    }
    
    private func canMove(from: (row: Int, col: Int), to: (row: Int, col: Int)) -> Bool {
        guard let piece = board[from.row][from.col] else {
            print("canMove: 起始位置没有棋子")
            return false
        }
        
        print("canMove: 检查 \(piece.rawValue) 从 (\(from.row), \(from.col)) 到 (\(to.row), \(to.col))")
        
        // 不能移动到己方棋子的位置
        if let targetPiece = board[to.row][to.col], targetPiece.isRed == piece.isRed {
            print("canMove: 目标位置是己方棋子 \(targetPiece.rawValue)")
            return false
        }
        
        let rowDiff = abs(to.row - from.row)
        let colDiff = abs(to.col - from.col)
        print("canMove: 行差=\(rowDiff), 列差=\(colDiff)")
        
        switch piece {
        case .redGeneral, .blackGeneral:
            let inPalace = (piece.isRed && to.row >= 7 && to.col >= 3 && to.col <= 5) ||
                           (!piece.isRed && to.row <= 2 && to.col >= 3 && to.col <= 5)
            return inPalace && (rowDiff + colDiff == 1)
            
        case .redAdvisor, .blackAdvisor:
            let inPalace = (piece.isRed && to.row >= 7 && to.col >= 3 && to.col <= 5) ||
                           (!piece.isRed && to.row <= 2 && to.col >= 3 && to.col <= 5)
            return inPalace && rowDiff == 1 && colDiff == 1
            
        case .redElephant, .blackElephant:
            let sameSide = (piece.isRed && to.row >= 5) || (!piece.isRed && to.row <= 4)
            let noObstacle = board[(from.row + to.row)/2][(from.col + to.col)/2] == nil
            return sameSide && rowDiff == 2 && colDiff == 2 && noObstacle
            
        case .redHorse, .blackHorse:
            if rowDiff == 2 && colDiff == 1 {
                return board[from.row + (to.row - from.row)/2][from.col] == nil
            } else if rowDiff == 1 && colDiff == 2 {
                return board[from.row][from.col + (to.col - from.col)/2] == nil
            }
            return false
            
        case .redChariot, .blackChariot:
            if from.row == to.row {
                let minCol = min(from.col, to.col)
                let maxCol = max(from.col, to.col)
                for col in (minCol + 1)..<maxCol {
                    if board[from.row][col] != nil { return false }
                }
                return true
            } else if from.col == to.col {
                let minRow = min(from.row, to.row)
                let maxRow = max(from.row, to.row)
                for row in (minRow + 1)..<maxRow {
                    if board[row][from.col] != nil { return false }
                }
                return true
            }
            return false
            
        case .redCannon, .blackCannon:
            var pieceCount = 0
            if from.row == to.row {
                let minCol = min(from.col, to.col)
                let maxCol = max(from.col, to.col)
                for col in (minCol + 1)..<maxCol {
                    if board[from.row][col] != nil { pieceCount += 1 }
                }
            } else if from.col == to.col {
                let minRow = min(from.row, to.row)
                let maxRow = max(from.row, to.row)
                for row in (minRow + 1)..<maxRow {
                    if board[row][from.col] != nil { pieceCount += 1 }
                }
            } else {
                return false
            }
            
            if board[to.row][to.col] != nil {
                return pieceCount == 1
            } else {
                return pieceCount == 0
            }
            
        case .redSoldier:
            // 红兵向上走（row减小）
            print("canMove: 红兵，当前行=\(from.row)")
            if from.row <= 4 {
                // 过河后可以左右移动
                let result = (rowDiff + colDiff == 1) && to.row <= from.row
                print("canMove: 红兵已过河，可以左右，结果=\(result)")
                return result
            } else {
                // 未过河只能向前
                let result = rowDiff == 1 && colDiff == 0 && to.row == from.row - 1
                print("canMove: 红兵未过河，只能向前，目标行应该是\(from.row - 1)，实际是\(to.row)，结果=\(result)")
                return result
            }
            
        case .blackSoldier:
            // 黑卒向下走（row增加）
            print("canMove: 黑卒，当前行=\(from.row)")
            if from.row >= 5 {
                // 过河后可以左右移动
                let result = (rowDiff + colDiff == 1) && to.row >= from.row
                print("canMove: 黑卒已过河，可以左右，结果=\(result)")
                return result
            } else {
                // 未过河只能向前
                let result = rowDiff == 1 && colDiff == 0 && to.row == from.row + 1
                print("canMove: 黑卒未过河，只能向前，目标行应该是\(from.row + 1)，实际是\(to.row)，结果=\(result)")
                return result
            }
        }
    }
    
    func restart() {
        setupBoard()
        selectedPosition = nil
        isRedTurn = true
        winner = nil
        isMyTurn = isHost
    }
}

struct SimpleChineseChessView: View {
    @StateObject private var game: ChineseChessGame
    @ObservedObject var p2pManager: P2PManager
    private let isHost: Bool
    @State private var showInfo = false
    
    init(p2pManager: P2PManager) {
        self.p2pManager = p2pManager
        self.isHost = p2pManager.wasHost
        self._game = StateObject(wrappedValue: ChineseChessGame(p2pManager: p2pManager, isHost: p2pManager.wasHost))
    }
    
    var body: some View {
        ScrollView {
            VStack {
                // 标题栏
                HStack {
                    Text("中国象棋")
                        .font(.largeTitle)
                    
                    Spacer()
                    
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                    }
                }
                .padding(.horizontal)
                
                // 获胜信息（显示在顶部）
                if let winner = game.winner {
                    Text(winner)
                        .font(.title)
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
                
                // 状态信息（可折叠）
                if showInfo {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("你是: \(game.myColor ? "红方（下方）" : "黑方（上方）")")
                            .foregroundColor(game.myColor ? .red : .black)
                            .font(.headline)
                        
                        if game.isMyTurn {
                            Text("状态: 你的回合")
                                .foregroundColor(.green)
                                .font(.headline)
                        } else {
                            Text("状态: 对手回合")
                                .foregroundColor(.gray)
                        }
                        
                        if let selected = game.selectedPosition {
                            let piece = game.board[selected.row][selected.col]
                            Text("已选中: \(piece?.rawValue ?? "") 在 (\(selected.row), \(selected.col))")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text("👆 现在点击空位或对方棋子来移动")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .bold()
                        } else if game.isMyTurn {
                            Text("👆 点击你的棋子来选中")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        
                        Text("当前回合: \(game.isRedTurn ? "红方" : "黑方")")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Divider()
                        
                        // 棋盘坐标说明
                        Text("棋盘坐标说明：")
                            .font(.caption)
                            .bold()
                        Text("• 第0行：黑方后排（将、车、马等）")
                        Text("• 第3行：黑方兵")
                        Text("• 第6行：红方兵")
                        Text("• 第9行：红方后排（帅、车、马等）")
                        Text("• 列：0-8 从左到右")
                    }
                    .font(.caption2)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .transition(.opacity)
                    .animation(.easeInOut, value: showInfo)
                }
                
                // 简洁状态栏（始终显示）
                HStack {
                    Circle()
                        .fill(game.myColor ? Color.red : Color.black)
                        .frame(width: 12, height: 12)
                    Text(game.myColor ? "红方" : "黑方")
                        .font(.caption)
                    
                    Spacer()
                    
                    if game.isMyTurn {
                        Label("你的回合", systemImage: "play.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("对手回合", systemImage: "pause.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                // 中国象棋棋盘 - 棋子在交叉点上
                ZStack {
                    // 棋盘背景
                    Rectangle()
                        .fill(Color.yellow.opacity(0.3))
                        .frame(width: 360, height: 400)
                    
                    // 画棋盘线
                    Canvas { context, size in
                        let cellWidth = size.width / 8
                        let cellHeight = size.height / 9
                        
                        // 横线
                        for i in 0..<10 {
                            context.stroke(
                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: CGFloat(i) * cellHeight))
                                    path.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * cellHeight))
                                },
                                with: .color(.black),
                                lineWidth: 1
                            )
                        }
                        
                        // 竖线
                        for i in 0..<9 {
                            // 上半部分
                            if i == 0 || i == 8 {
                                context.stroke(
                                    Path { path in
                                        path.move(to: CGPoint(x: CGFloat(i) * cellWidth, y: 0))
                                        path.addLine(to: CGPoint(x: CGFloat(i) * cellWidth, y: size.height))
                                    },
                                    with: .color(.black),
                                    lineWidth: 1
                                )
                            } else {
                                // 上半部分
                                context.stroke(
                                    Path { path in
                                        path.move(to: CGPoint(x: CGFloat(i) * cellWidth, y: 0))
                                        path.addLine(to: CGPoint(x: CGFloat(i) * cellWidth, y: cellHeight * 4))
                                    },
                                    with: .color(.black),
                                    lineWidth: 1
                                )
                                // 下半部分
                                context.stroke(
                                    Path { path in
                                        path.move(to: CGPoint(x: CGFloat(i) * cellWidth, y: cellHeight * 5))
                                        path.addLine(to: CGPoint(x: CGFloat(i) * cellWidth, y: size.height))
                                    },
                                    with: .color(.black),
                                    lineWidth: 1
                                )
                            }
                        }
                        
                        // 九宫格斜线
                        // 上方九宫格
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: cellWidth * 3, y: 0))
                                path.addLine(to: CGPoint(x: cellWidth * 5, y: cellHeight * 2))
                            },
                            with: .color(.black),
                            lineWidth: 1
                        )
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: cellWidth * 5, y: 0))
                                path.addLine(to: CGPoint(x: cellWidth * 3, y: cellHeight * 2))
                            },
                            with: .color(.black),
                            lineWidth: 1
                        )
                        
                        // 下方九宫格
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: cellWidth * 3, y: cellHeight * 7))
                                path.addLine(to: CGPoint(x: cellWidth * 5, y: cellHeight * 9))
                            },
                            with: .color(.black),
                            lineWidth: 1
                        )
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: cellWidth * 5, y: cellHeight * 7))
                                path.addLine(to: CGPoint(x: cellWidth * 3, y: cellHeight * 9))
                            },
                            with: .color(.black),
                            lineWidth: 1
                        )
                        
                        // 楚河汉界
                        let text = "楚河     汉界"
                        context.draw(Text(text).font(.system(size: 16)), at: CGPoint(x: size.width / 2, y: cellHeight * 4.5))
                    }
                    .frame(width: 360, height: 400)
                    
                    // 棋子 - 放在交叉点上
                    ForEach(0..<10, id: \.self) { row in
                        ForEach(0..<9, id: \.self) { col in
                            let x = CGFloat(col) * 45  // 360/8 = 45
                            let y = CGFloat(row) * 44.44  // 400/9 = 44.44
                            
                            if let piece = game.board[row][col] {
                                ChessPieceView(
                                    piece: piece,
                                    isSelected: game.selectedPosition?.row == row && game.selectedPosition?.col == col
                                )
                                .position(x: x, y: y)
                                .onTapGesture {
                                    print("点击棋子: (\(row), \(col)) - \(piece.rawValue)")
                                    game.selectPiece(row: row, col: col)
                                }
                            }
                            
                            // 为每个位置添加透明的点击区域（包括空位）
                            Circle()
                                .fill(Color.blue.opacity(0.01)) // 几乎透明，仅用于调试
                                .frame(width: 40, height: 40)
                                .position(x: x, y: y)
                                .allowsHitTesting(game.board[row][col] == nil) // 只有空位才响应点击
                                .onTapGesture {
                                    if game.board[row][col] == nil {
                                        print("==== 点击空位 ====")
                                        print("空位位置: (\(row), \(col))")
                                        print("当前选中: \(game.selectedPosition != nil ? "(\(game.selectedPosition!.row), \(game.selectedPosition!.col))" : "无")")
                                        game.selectPiece(row: row, col: col)
                                    }
                                }
                        }
                    }
                }
                .frame(width: 360, height: 400)
                .padding()
                
                // 控制按钮
                HStack {
                    Button("重新开始") {
                        game.restart()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if !p2pManager.isConnected {
                        Button("测试模式") {
                            game.myColor = true
                            game.isMyTurn = true
                            game.isRedTurn = true
                            print("进入测试模式：红方先手")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
        .onReceive(p2pManager.$receivedData) { data in
            guard let data = data,
                  let gameMove = try? JSONDecoder().decode(GameMove.self, from: data),
                  gameMove.gameType == .chineseChess else { return }
            
            if let move = try? JSONDecoder().decode(ChessMove.self, from: gameMove.moveData) {
                game.receiveMove(move)
            }
        }
    }
}

struct ChessPieceView: View {
    let piece: ChessPiece
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // 选中效果
            if isSelected {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 42, height: 42)
            }
            
            Circle()
                .fill(Color.white)
                .frame(width: 36, height: 36)
            
            if isSelected {
                Circle()
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 38, height: 38)
            } else {
                Circle()
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 36, height: 36)
            }
            
            Text(piece.rawValue)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(piece.isRed ? .red : .black)
        }
    }
}

// 保留原来的ChessCellView以兼容
struct ChessCellView: View {
    let piece: ChessPiece?
    let isSelected: Bool
    let row: Int
    let col: Int
    let game: ChineseChessGame
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .border(Color.black, width: 1)
            
            if let piece = piece {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 35, height: 35)
                    
                    if isSelected {
                        Circle()
                            .stroke(Color.blue, lineWidth: 3)
                            .frame(width: 38, height: 38)
                    }
                    
                    Text(piece.rawValue)
                        .font(.system(size: 20))
                        .foregroundColor(piece.isRed ? .red : .black)
                }
            }
        }
        .frame(width: 40, height: 40)
        .onTapGesture {
            print("点击格子: (\(row), \(col)) - 棋子: \(piece?.rawValue ?? "空")")
            game.selectPiece(row: row, col: col)
        }
    }
}