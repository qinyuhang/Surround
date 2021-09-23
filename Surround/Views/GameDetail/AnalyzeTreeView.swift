//
//  AnalyzeTree.swift
//  Surround
//
//  Created by Anh Khoa Hong on 31/05/2021.
//

import SwiftUI

struct AnalyzeTreeSlice: View {
    var moveTree: MoveTree
    var lastMoveNumber: Int
    @Binding var selectedPosition: BoardPosition?
    
    var body: some View {
        VStack {
            ZStack {
                ForEach(Array((moveTree.positionsByLastMoveNumber[lastMoveNumber] ?? []).enumerated()), id: \.0) { _, position in
                    if let position = position {
                        if let lastMoveColor = position.lastMoveColor, let level = moveTree.levelByBoardPosition[ObjectIdentifier(position)] {
                            if let previousPosition = position.previousPosition, let previousLevel = moveTree.levelByBoardPosition[ObjectIdentifier(previousPosition)] {
                                Path { path in
                                    path.move(to: CGPoint(x: 15, y: CGFloat(level) * 40 + 15))
                                    path.addCurve(
                                        to: CGPoint(x: -25, y: CGFloat(previousLevel) * 40 + 15),
                                        control1:CGPoint(x: -10, y: CGFloat(level) * 40 + 15),
                                        control2:CGPoint(x: -25, y: CGFloat(previousLevel) * 40 + 15)
                                    )
                                }.stroke(Color(.label))
                            }
                            if self.selectedPosition?.hasTheSamePosition(with: position) ?? false {
                                Color(UIColor.systemTeal).frame(width: 38, height: 38)
                                    .cornerRadius(19)
                                    .position(x: 15, y: CGFloat(level) * 40 + 15)
                            }
                            
                            Stone(color: lastMoveColor, shadowRadius: 2).frame(width: 30, height: 30).position(x: 15, y: CGFloat(level) * 40 + 15)
                                .onTapGesture {
                                    self.selectedPosition = position
                                }
                        } else if lastMoveNumber == 0 {
                            Image(systemName: "squareshape.split.3x3")
//                                .font(.system(size: 30))
                                .background(Color(red: 0.86, green: 0.69, blue: 0.42).cornerRadius(2))
                                .onTapGesture {
                                    self.selectedPosition = position
                                }
                        }
                    }
//                    else {
//                        Color.gray.frame(width: 30, height: 30)
//                            .position(x: 15, y: 15)
//                    }
                }
            }
            .frame(width: 30, height: CGFloat(moveTree.maxLevel) * 40 + 32)
            .padding(.vertical, 5)
            Spacer()
        }.frame(maxHeight: .infinity)
    }
}

struct BackgroundSlice: View {
    @Environment(\.colorScheme) private var colorScheme
    var lastMoveNumber: Int
    
    var body: some View {
        if lastMoveNumber > 0 && lastMoveNumber % 5 == 0 {
            Path { path in
                path.move(to: CGPoint(x: 15, y: 30))
                path.addLine(to: CGPoint(x: 15, y: 800))
            }.stroke(Color(colorScheme == .dark ? .systemGray6 : .systemGray4))
        }
    }
}

struct AnalyzeTreeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var game: Game
    @Binding var selectedPosition: BoardPosition?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ScrollViewReader { horizontalScrollView in
                            LazyHStack(alignment: .top) {
                                ForEach(Array(self.game.moveTree.moveNumberRange), id: \.self) { lastMoveNumber in
                                    ZStack {
                                        BackgroundSlice(lastMoveNumber: lastMoveNumber)
                                        VStack(spacing: 0) {
                                            Spacer().frame(height: 5)
                                            if lastMoveNumber % 5 == 0 {
                                                Text("\(lastMoveNumber)").font(.body.monospacedDigit()).bold()
                                            } else {
                                                Text("\(lastMoveNumber)").font(.body.monospacedDigit())
                                                    .fontWeight(.light)
                                            }
                                            AnalyzeTreeSlice(
                                                moveTree: self.game.moveTree,
                                                lastMoveNumber: lastMoveNumber,
                                                selectedPosition: self.$selectedPosition
                                            )
                                        }
                                    }
                                    .zIndex(-Double(lastMoveNumber))
                                    .id(lastMoveNumber)
                                }
                            }
                            .padding(.horizontal, 10)
                            .onChange(of: self.selectedPosition?.lastMoveNumber) { newLastMoveNumber in
                                DispatchQueue.main.async {
                                    withAnimation {
                                        horizontalScrollView.scrollTo(newLastMoveNumber, anchor: .center)
                                    }
                                }
                            }
                            .onAppear {
                                if let lastMoveNumber = self.selectedPosition?.lastMoveNumber {
                                    horizontalScrollView.scrollTo(lastMoveNumber, anchor: .center)
                                }
                            }
                        }
                    }
                }.frame(minHeight: geometry.size.height)
            }.frame(height: geometry.size.height)
        }
        .background(Color(colorScheme == .dark ? .systemGray4 : .systemGray6).shadow(radius: 2))
    }
}

struct AnalyzeTree_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Ongoing19x19wBot3
        try! game.makeMove(move: .placeStone(1, 1), fromAnalyticsPosition: game.positionByLastMoveNumber[7]!)
        let currentPosition = try! game.makeMove(move: .placeStone(0, 0), fromAnalyticsPosition: game.positionByLastMoveNumber[7]!)
        try! game.makeMove(move: .placeStone(1, 1), fromAnalyticsPosition: game.positionByLastMoveNumber[6]!)
        try! game.makeMove(move: .placeStone(1, 1), fromAnalyticsPosition: game.positionByLastMoveNumber[6]!)
        let position = try! game.makeMove(move: .placeStone(0, 0), fromAnalyticsPosition: game.positionByLastMoveNumber[6]!)
        try! game.makeMove(move: .placeStone(2, 2), fromAnalyticsPosition: position)
        return Group {
            AnalyzeTreeView(
                game: game,
                selectedPosition: .constant(currentPosition)
            )
            .previewLayout(.fixed(width: 390, height: 300))
            AnalyzeTreeView(
                game: game,
                selectedPosition: .constant(currentPosition)
            )
            .previewLayout(.fixed(width: 390, height: 300))
            .colorScheme(.dark)
        }
    }
}