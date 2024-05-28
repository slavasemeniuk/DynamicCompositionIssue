//
//  ContentView.swift
//  MutableCompositionIssue
//
//  Created by Semeniuk Slava on 23.04.2024.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @State private var compositionStore = CompositionStore()
    @State private var generateTask: Task<Void, Never>?
    @State private var player = AVPlayer()

    var body: some View {
        ZStack {
            if player.currentItem != nil {
                VideoPlayer(player: player)
                    .frame(height: 400)
            } else if generateTask != nil {
                ProgressView()
                    .tint(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.yellow)
        .overlay(alignment: .bottom) {
            HStack {
                Button("4K sources") { generate(name: "IMG_4K") }
                Button("1080 sources") { generate(name: "IMG_1080") }
            }
            .buttonStyle(BorderedButtonStyle())
        }
        .onAppear { generate(name: "IMG_4K") }
    }

    @MainActor
    private func generate(name: String) {
        generateTask?.cancel()
        generateTask = Task {
            compositionStore.asset = nil
            try! await compositionStore.build(name: name)
            if Task.isCancelled { return }
            let item = compositionStore.asset.map(AVPlayerItem.init)
            item?.appliesPerFrameHDRDisplayMetadata = false
            player.replaceCurrentItem(with: item)
            generateTask = nil
        }
    }
}

@Observable
final class CompositionStore {

    var asset: AVMutableComposition?

    @MainActor
    func build(name: String) async throws {
        let date = Date()
        print("Start")
        defer { print("Complete: \(-date.timeIntervalSinceNow)") }
        let bundleFileURL = Bundle.main.url(forResource: name, withExtension: "MOV")!
        let sourceComposition = AVURLAsset(url: bundleFileURL)

        asset = nil
        let targetComposition = AVMutableComposition()
        let frameDurationValue: CMTimeValue = 5
        let frameDuration = CMTime(value: frameDurationValue, timescale: 30)
        let timeRanges: [CMTimeRange] = (0 ... 25).map {
            CMTimeRange(start: CMTime(value: frameDurationValue * $0, timescale: 30), duration: frameDuration)
        }
        let startPointOffset: CMTime = CMTime(value: 1, timescale: 30)
        var currentTime = CMTime.zero

        for targetTimeRange in timeRanges {
            let sourceTimeRage = CMTimeRange(start: currentTime, duration: targetTimeRange.duration)
            print("source \(sourceTimeRage.debugString) | target \(targetTimeRange.debugString)")
            try await targetComposition.insertTimeRange(
                sourceTimeRage,
                of: sourceComposition,
                at: targetTimeRange.start
            )
            currentTime = CMTimeAdd(CMTimeAdd(currentTime, targetTimeRange.duration), startPointOffset)
        }

        targetComposition.tracks
            .filter { $0.mediaType != .video }
            .forEach(targetComposition.removeTrack)
        asset = targetComposition
        print("Tracks count: \(targetComposition.tracks.count)")
    }
}

#Preview {
    ContentView()
}

extension CMTime {
    var debugString: String {
        "\(String(format: "%03d", value))/\(timescale)"
    }
}

extension CMTimeRange {
    var debugString: String {
        "\(start.debugString) - \(end.debugString)"
    }
}
