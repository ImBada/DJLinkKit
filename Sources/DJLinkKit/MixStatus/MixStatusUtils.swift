// 원본 src/mixstatus/utils.ts

private let playingStates: [CDJStatus.PlayState] = [.playing, .looping]

private let stoppingStates: [CDJStatus.PlayState] = [.cued, .ended, .loading]

/// Returns true if the the status reports a playing state.
public func isPlaying(_ s: CDJStatus.State) -> Bool {
    playingStates.contains(s.playState)
}

/// Returns true if the status reports a stopping state.
public func isStopping(_ s: CDJStatus.State) -> Bool {
    stoppingStates.contains(s.playState)
}
