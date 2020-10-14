//
//  Game.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/30/20.
//

import Foundation
import Combine

enum GameID: Hashable {
    case OGS(Int)
}

class Game: ObservableObject, Identifiable, CustomDebugStringConvertible, Equatable {
    static func == (lhs: Game, rhs: Game) -> Bool {
        return lhs.ID == rhs.ID
    }
    
    @Published var gameData: OGSGame? {
        didSet {
            if let data = gameData {
                self.gameName = data.gameName
                self.blackRank = data.players.black.rank
                self.whiteRank = data.players.white.rank
                self.blackId = data.players.black.id
                self.whiteId = data.players.white.id
                if let blackAcceptedRemovedStones = data.players.black.acceptedStones {
                    self.removedStonesAccepted[.black] = BoardPosition.points(fromPositionString: blackAcceptedRemovedStones)
                }
                if let whiteAcceptedRemovedStones = data.players.white.acceptedStones {
                    self.removedStonesAccepted[.white] = BoardPosition.points(fromPositionString:  whiteAcceptedRemovedStones)
                }
                
                var position = initialPosition
                do {
                    var firstNonHandicapMoveIndex = 0
                    var initialPositionStones = 0
                    if data.initialState.white.count > 0 || data.initialState.black.count > 0 {
                        for point in BoardPosition.points(fromPositionString: data.initialState.black) {
                            position.putStone(row: point[0], column: point[1], color: .black)
                            initialPositionStones += 1
                        }
                        for point in BoardPosition.points(fromPositionString: data.initialState.white) {
                            position.putStone(row: point[0], column: point[1], color: .white)
                            initialPositionStones += 1
                        }
                        position.nextToMove = data.initialPlayer
                    }
                    if data.handicap > 0 && data.freeHandicapPlacement {
                        firstNonHandicapMoveIndex = min(data.handicap, data.moves.count)
                        for handicapMove in data.moves[..<firstNonHandicapMoveIndex] {
                            position = try position.makeHandicapPlacement(move: .placeStone(handicapMove[1], handicapMove[0]))
                        }
                        position.nextToMove = firstNonHandicapMoveIndex == data.handicap ? data.initialPlayer.opponentColor() : data.initialPlayer
                    }
                    for move in data.moves[firstNonHandicapMoveIndex...] {
                        position = try position.makeMove(move: move[0] == -1 ? .pass : .placeStone(move[1], move[0]), allowsSelfCapture: data.allowSelfCapture)
                    }
                } catch {
                    print(error)
                }
                currentPosition = position
                if let removedStones = gameData?.removed {
                    currentPosition.removedStones = BoardPosition.points(fromPositionString: removedStones)
                }
                currentPosition.gameScores = gameData?.score

                pauseControl = data.pauseControl
                clock = data.clock
                
                undoRequested = data.undoRequested

                autoScoringDone = data.autoScoringDone
                // Put this at the end since it will trigger score computing
                gamePhase = data.phase
            }
        }
    }
    var width: Int
    var height: Int
    var blackName: String
    var whiteName: String
    @Published var blackRank: Double?
    @Published var whiteRank: Double?
    @Published var blackId: Int?
    @Published var whiteId: Int?
    @Published var gameName: String?
    @Published var currentPosition: BoardPosition
    @Published var undoRequested: Int?
    var blackFormattedRank: String {
        return formattedRankString(rank: blackRank, professional: gameData?.players.black.professional ?? false)
    }
    var whiteFormattedRank: String {
        return formattedRankString(rank: whiteRank, professional: gameData?.players.white.professional ?? false)
    }
    var initialPosition: BoardPosition
    var ID: GameID
    var ogsURL: URL? {
        if case .OGS(let id) = self.ID {
            return URL(string: "\(OGSService.ogsRoot)/game/\(id)")
        }
        return nil
    }
    @Published var ogsRawData: [String: Any]?
    @Published var clock: OGSClock?
    @Published var pauseControl: OGSPauseControl?
    var canBeCancelled: Bool {
        if gamePhase != .play {
            return false
        }
        
        if gameData?.tournamentId != nil {
            return false
        }
        
        if gameData?.ladderId != nil {
            return false
        }
        
        var maxMovePlayed = 2
        if let handicap = gameData?.handicap {
            if gameData?.freeHandicapPlacement ?? false {
                maxMovePlayed += handicap - 1
            }
        }
        return currentPosition.lastMoveNumber < maxMovePlayed
    }
    
    var autoScoringDone: Bool?
    var autoScoringCancellable: AnyCancellable?
    var toggleRemovedStoneCancellable: AnyCancellable?
    weak var ogs: OGSService?
    @Published var gamePhase: OGSGamePhase? {
        didSet {
            if gamePhase == .stoneRemoval {
                if !(autoScoringDone ?? false) {
                    // Doing score estimating
                    self.autoScoringCancellable = currentPosition.estimateTerritory(on: computeQueue)
                        .receive(on: DispatchQueue.main)
                        .sink(receiveValue: { territory in
                            var estimatedRemovedStones = Set<[Int]>()
                            for row in 0..<self.currentPosition.height {
                                for column in 0..<self.currentPosition.width {
                                    let isCaptured = self.currentPosition[row, column] != .empty && self.currentPosition[row, column] != territory[row][column]
                                    let isDame = territory[row][column] == .empty && self.currentPosition[row, column] == .empty
                                    if isCaptured || isDame {
                                        estimatedRemovedStones.insert([row, column])
                                    }
                                }
                            }
                            self.toggleRemovedStoneCancellable = self.ogs?.toggleRemovedStones(stones: estimatedRemovedStones, forGame: self)
                                .sink(receiveCompletion: { _ in}, receiveValue: { _ in})
                    })
                } else {
                    computeScoresAndUpdate()
                }
            } else if gamePhase == .play {
                DispatchQueue.main.async {
                    self.autoScoringDone = nil
                    self.currentPosition.gameScores = nil
                    self.currentPosition.removedStones = nil
                }
            }
        }
    }
    @Published var removedStonesAccepted = [StoneColor: Set<[Int]>]()
    lazy var computeQueue = DispatchQueue(label: "com.honganhkhoa.Surround.computeQueue", qos: .default)
    
    var debugDescription: String {
        if case .OGS(let id) = self.ID {
            return "Game #\(id)"
        }
        return ""
    }
    var ogsID: Int? {
        if case .OGS(let id) = self.ID {
            return id
        }
        return nil
    }
    
    func playerIcon(for player: StoneColor, size: Int) -> String? {
        guard let icon = ((self.ogsRawData ?? [:]) as NSDictionary).value(forKeyPath: player == .black ? "players.black.icon" : "players.white.icon") as? String else {
            return nil
        }
        
        let regex1 = try! NSRegularExpression(pattern: "-[0-9]+.png")
        let regex2 = try! NSRegularExpression(pattern: "s=[0-9]+")
        var result = icon
        result = regex1.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "-\(size).png")
        result = regex2.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "s=\(size)")
        return result
    }
    
    init(width: Int, height: Int, blackName: String, whiteName: String, gameId: GameID) {
        self.width = width
        self.height = height
        self.blackName = blackName
        self.whiteName = whiteName
        self.ID = gameId
        self.initialPosition = BoardPosition(width: width, height: height)
        self.currentPosition = self.initialPosition
    }
    
    init(ogsGame: OGSGame) {
        self.width = ogsGame.width
        self.height = ogsGame.height
        self.blackName = ogsGame.players.black.username
        self.whiteName = ogsGame.players.white.username
        self.blackId = ogsGame.players.black.id
        self.whiteId = ogsGame.players.white.id
        self.ID = .OGS(ogsGame.gameId)
        self.initialPosition = BoardPosition(width: width, height: height)
        self.currentPosition = self.initialPosition
        self.gameData = ogsGame
    }
    
    func makeMove(move: Move) throws {
        if let handicap = gameData?.handicap {
            if gameData?.freeHandicapPlacement ?? false {
                if currentPosition.lastMoveNumber < handicap - 1 {
                    self.currentPosition = try currentPosition.makeHandicapPlacement(move: move)
                    return
                }
            }
        }
        self.currentPosition = try currentPosition.makeMove(move: move, allowsSelfCapture: gameData?.allowSelfCapture ?? false)
        self.undoRequested = nil
    }
    
    func undoMove(numbered moveNumber: Int) {
        var position = currentPosition
        while position.previousPosition != nil && position.lastMoveNumber >= moveNumber {
            position = position.previousPosition!
        }
        currentPosition = position
        self.undoRequested = nil
    }
    
    func computeScore() -> GameScores? {
        guard let gameData = gameData else {
            return nil
        }
        var score = GameScores(
            black: PlayerScore(
                handicap: 0,
                komi: 0,
                scoringPositions: Set<[Int]>(),
                stones: 0,
                territory: 0,
                prisoners: 0,
                total: 0
            ),
            white: PlayerScore(
                handicap: gameData.handicap,
                komi: gameData.komi,
                scoringPositions: Set<[Int]>(),
                stones: 0,
                territory: 0,
                prisoners: 0,
                total: 0
            )
        )
        let territoryGroups = self.currentPosition.constructTerritoryGroups()
        
        if gameData.agaHandicapScoring && score.white.handicap > 0 {
            score.white.handicap -= 1
        }
        
        if gameData.scoreTerritory {
            for group in territoryGroups {
                group.computeTerritory()
                if group.isTerritory {
                    if group.territoryColor == .black {
                        score.black.scoringPositions.formUnion(group.points)
                        if !group.isDame {
                            score.black.territory += group.points.count
                        }
                    } else {
                        score.white.scoringPositions.formUnion(group.points)
                        if !group.isDame {
                            score.white.territory += group.points.count
                        }
                    }
                }
            }
        }
        
        for row in 0..<width {
            for column in 0..<height {
                if case .hasStone(let color) = currentPosition[row, column] {
                    let isRemoved = currentPosition.removedStones?.contains([row, column]) ?? false
                    if !isRemoved && gameData.scoreStones {
                        if color == .black {
                            score.black.stones += 1
                            score.black.scoringPositions.insert([row, column])
                        } else {
                            score.white.stones += 1
                            score.white.scoringPositions.insert([row, column])
                        }
                    }
                    if isRemoved && gameData.scorePrisoners {
                        if color == .black {
                            score.white.prisoners += 1
                        } else {
                            score.black.prisoners += 1
                        }
                    }
                }
            }
        }
        
        if gameData.scorePrisoners {
            score.white.prisoners += currentPosition.captures[.white] ?? 0
            score.black.prisoners += currentPosition.captures[.black] ?? 0
        }
        
        score.black.total = Double(score.black.stones + score.black.territory + score.black.prisoners) + score.black.komi
        score.white.total = Double(score.white.stones + score.white.territory + score.white.prisoners) + score.white.komi
        if gameData.scoreHandicap {
            score.black.total += Double(score.black.handicap)
            score.white.total += Double(score.white.handicap)
        }
        
        return score
    }
    
    func computeScoresAndUpdate() {
        computeQueue.async {
            if let score = self.computeScore() {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.currentPosition.gameScores = score
                }
            }
        }
    }
    
    func setRemovedStones(removedString: String) {
        self.currentPosition.removedStones = BoardPosition.points(fromPositionString: removedString)
        if self.gamePhase == .stoneRemoval {
            self.computeScoresAndUpdate()
        }
    }
    
    func setAutoResign(playerId: Int, time: Double) {
        guard playerId == blackId || playerId == whiteId else {
            return
        }
        
        let playerColor = playerId == blackId ? StoneColor.black : StoneColor.white
        self.clock?.autoResignTime[playerColor] = time
    }
    
    func clearAutoResign(playerId: Int) {
        guard playerId == blackId || playerId == whiteId else {
            return
        }
        
        let playerColor = playerId == blackId ? StoneColor.black : StoneColor.white
        self.clock?.autoResignTime.removeValue(forKey: playerColor)
    }
    
    var isUserPlaying: Bool {
        guard let user = ogs?.user else {
            return false
        }
        return user.id == self.blackId || user.id == self.whiteId
    }
    
    var isUserTurn: Bool {
        guard isUserPlaying else {
            return false
        }
        
        guard let user = ogs?.user else {
            return false
        }
        
        guard self.gamePhase == .play else {
            return false
        }
        
        return (self.clock?.currentPlayer == .black && user.id == self.blackId) ||
            (self.clock?.currentPlayer == .white && user.id == self.whiteId)
    }
    
    var status: String {
        if let outcome = gameData?.outcome {
            if gameData?.winner == blackId {
                return "Black wins by \(outcome)"
            } else {
                return "White wins by \(outcome)"
            }
        } else if let estimatedScores = currentPosition.estimatedScores {
            var whiteScore: Double = 0
            var blackScore: Double = 0
            for row in 0..<currentPosition.height {
                for column in 0..<currentPosition.width {
                    if case .hasStone(let color) = estimatedScores[row][column] {
                        if color == .black {
                            blackScore += 1
                        } else {
                            whiteScore += 1
                        }
                    }
                }
            }
            let difference = whiteScore + (gameData?.komi ?? 0) - blackScore
            if difference > 0 {
                return String(format: "White by %.1f", difference)
            } else {
                return String(format: "Black by %.1f", -difference)
            }
        } else {
            if gamePhase == .stoneRemoval {
                return "Stone Removal Phase"
            }
            if undoRequested != nil {
                return "Undo requested"
            }
            if isUserPlaying {
                if isUserTurn {
                    if case .pass = currentPosition.lastMove {
                        return "Opponent passed"
                    } else {
                        return "Your move"
                    }
                } else {
                    return "Waiting for opponent"
                }
            } else {
                if let currentPlayer = clock?.currentPlayer {
                    return "\(currentPlayer == .black ? "Black" : "White") to move"
                } else {
                    return ""
                }
            }
        }
    }
    
    var undoable: Bool {
        guard isUserPlaying else {
            return false
        }
        
        guard gamePhase == .play && gameData?.outcome == nil else {
            return false
        }
        
        var minimumLastMove = 0
        if let handicap = gameData?.handicap {
            if gameData?.freeHandicapPlacement ?? false {
                minimumLastMove = handicap
            }
        }
        
        return !isUserTurn && undoRequested == nil && currentPosition.lastMoveNumber > minimumLastMove
    }

    var undoacceptable: Bool {
        guard let undoRequested = undoRequested else {
            return false
        }
        return isUserTurn && undoRequested == currentPosition.lastMoveNumber
    }
}
