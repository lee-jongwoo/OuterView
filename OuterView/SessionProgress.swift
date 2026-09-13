import Foundation

nonisolated struct SessionProgress {
    enum Stage: Equatable { case deck, reading, question, recording, saving }
    private(set) var stage: Stage = .deck
    private(set) var groupIndex = 0
    private(set) var questionIndex: Int?
    private(set) var timerStartedAt: Date?
    private(set) var frozenElapsed: TimeInterval = 0
    var isTraining: Bool { stage != .deck }
    mutating func endTraining() { guard !isLocked else { return }; reset() }
    var isLocked: Bool { stage == .recording || stage == .saving }

    mutating func selectGroup(_ index: Int, count: Int) {
        guard !isLocked, (0..<count).contains(index) else { return }
        groupIndex = index
        reset()
    }
    mutating func start(hasPassage: Bool, now: Date = Date()) {
        guard stage == .deck else { return }
        stage = hasPassage ? .reading : .question
        questionIndex = hasPassage ? nil : 0
        timerStartedAt = hasPassage ? now : nil
        frozenElapsed = 0
    }
    mutating func next(questionCount: Int) {
        guard !isLocked else { return }
        if stage == .reading { stage = .question; questionIndex = 0; timerStartedAt = nil; frozenElapsed = 0 }
        else if let index = questionIndex {
            if index + 1 < questionCount { questionIndex = index + 1; timerStartedAt = nil; frozenElapsed = 0 }
            else { reset() }
        }
    }
    mutating func previous(hasPassage: Bool, now: Date = Date()) {
        guard stage == .question, let index = questionIndex else { return }
        if index > 0 { questionIndex = index - 1; frozenElapsed = 0 }
        else if hasPassage { stage = .reading; questionIndex = nil; timerStartedAt = now; frozenElapsed = 0 }
    }
    mutating func beginRecording(now: Date = Date()) {
        guard stage == .question else { return }
        stage = .recording; timerStartedAt = now; frozenElapsed = 0
    }
    mutating func beginSaving(now: Date = Date()) {
        guard stage == .recording else { return }
        frozenElapsed = elapsed(at: now); timerStartedAt = nil; stage = .saving
    }
    mutating func finishSaving() {
        guard isLocked else { return }
        stage = .question; timerStartedAt = nil
    }
    func elapsed(at now: Date) -> TimeInterval {
        timerStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? frozenElapsed
    }
    private mutating func reset() {
        stage = .deck; questionIndex = nil; timerStartedAt = nil; frozenElapsed = 0
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
}
