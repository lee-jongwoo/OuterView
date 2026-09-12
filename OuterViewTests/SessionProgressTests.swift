import Foundation
import Testing
@testable import OuterView

struct SessionProgressTests {
    @Test func passageFlowAndRecordingLocks() {
        var session = SessionProgress()
        let start = Date(timeIntervalSince1970: 100)
        session.start(hasPassage: true, now: start)
        #expect(session.stage == .reading)
        #expect(session.questionIndex == nil)
        #expect(session.elapsed(at: start.addingTimeInterval(90)) == 90)
        session.next(questionCount: 2)
        #expect(session.questionIndex == 0)
        session.beginRecording(now: start)
        session.next(questionCount: 2)
        session.previous(hasPassage: true)
        session.selectGroup(1, count: 2)
        #expect(session.groupIndex == 0 && session.questionIndex == 0)
        session.beginSaving(now: start.addingTimeInterval(10))
        session.next(questionCount: 2)
        #expect(session.isLocked)
        #expect(session.elapsed(at: start.addingTimeInterval(30)) == 10)
        session.finishSaving()
        #expect(session.questionIndex == 0 && session.stage == .question)
        session.next(questionCount: 2)
        #expect(session.questionIndex == 1)
        session.previous(hasPassage: true)
        #expect(session.questionIndex == 0)
        session.previous(hasPassage: true)
        #expect(session.stage == .reading)
    }

    @Test func questionOnlyAndGroupCompletion() {
        var session = SessionProgress()
        session.start(hasPassage: false)
        #expect(session.stage == .question && session.questionIndex == 0)
        session.previous(hasPassage: false)
        #expect(session.questionIndex == 0)
        session.next(questionCount: 1)
        #expect(session.stage == .deck && session.questionIndex == nil)
        session.selectGroup(5, count: 2)
        #expect(session.groupIndex == 0)
        #expect(SessionProgress.clock(3661) == "1:01:01")
    }
}
