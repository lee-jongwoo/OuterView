# OuterView — Interview Prep Suite (macOS)

## Overview

OuterView is a native macOS app (Swift, SwiftUI, SwiftData) that helps a student
practice for in-person admissions interviews. The user imports "training sets"
built from real interview-prep handouts, works through passages and questions
one at a time in a flashcard-like session, records video answers, and reviews
or exports takes — primarily to send to a tutor for feedback.

Distribution target: standalone Xcode project, sandboxed macOS app. Channel
(GitHub release / DMG vs. App Store) is undecided and should not constrain
architecture.

---

## Data Model (SwiftData)

Hierarchy: `TrainingSet` → `PassageGroup` (ordered) → `Question` (ordered) → `Take`

```swift
@Model
final class TrainingSet {
    var title: String              // e.g. "Yonsei 2024 - Humanities"
    var createdAt: Date
    var items: [PassageGroup]      // single ordered list — the full session sequence
}

@Model
final class PassageGroup {
    var label: String              // user-assigned identifier, e.g. "Ethics", "Case study 3"
    var imagePath: String?         // nil = no passage for this group, just question(s)
    var order: Int
    var questions: [Question]      // ordered, always >= 1
    var trainingSet: TrainingSet?  // inverse relationship
}

@Model
final class Question {
    var text: String
    var order: Int
    var passageGroup: PassageGroup?
    var takes: [Take]
}

@Model
final class Take {
    var videoPath: String          // file on disk (Application Support), not embedded in DB
    var recordedAt: Date
    var durationSeconds: Double
    var question: Question?
}
```

Notes for implementation:
- `PassageGroup` with `imagePath == nil` still behaves identically in the session
  flow — it's just skipped at the passage-reveal stage. No separate "standalone
  question" type.
- Relationship arrays are not guaranteed to preserve insertion order in SwiftData;
  always sort by `order` on fetch.
- Deleting a `TrainingSet` should cascade-delete its `PassageGroup`/`Question`/`Take`
  records, but video files on disk are a separate concern — implement explicit
  cleanup (e.g. delete associated files before/during model deletion) so videos
  don't orphan in storage.
- Video files live in the app's Application Support directory (or similar sandbox-safe
  location), organized in a sensible per-set folder structure. DB stores paths/UUIDs,
  never raw video data.

---

## Import Pipeline

**Primary path (v1, must work reliably):**
1. User imports a PDF (scanned handout).
2. Manual UI: user crops out the passage region as an image (per `PassageGroup`,
   optional) and types in the associated question(s) as plain text.
3. This becomes the source of truth — no unattended/automatic step required for v1.

**Optional future assist (not required for v1, do not block v1 on this):**
- A vision-model pass that attempts to auto-crop passage regions and extract
  question text from the PDF, producing a draft the user then reviews/corrects
  in the same manual UI above. Never auto-imports without a human review step —
  OCR/vision extraction errors should be caught before they reach a live session.

**Spoiler control on import:**
- Default behavior: after import, the user can preview/review the full set
  (needed to catch cropping/transcription errors, and reasonable since most
  importers built the set themselves or are reviewing someone else's work).
- Optional "blind import" toggle: user picks a file and imports without previewing
  contents — only a summary count is shown (e.g. "14 questions imported across
  5 groups"). Off by default. Exists because this app may be shared with friends
  who import sets someone else prepared for them.

---

## Session Flow

1. **Deck view**: list of `PassageGroup` items in a `TrainingSet`, shown by
   `label` only (e.g. "Ethics," "Case study 3") — no passage or question content
   visible. This is navigation, not preview.
2. User selects a group and presses **Start**.
   - If the group has a passage image: it's revealed, with a reading-elapsed
     timer (counts up, no cutoff).
   - If the group has no passage image: skip straight to the first question
     (no empty reading stage).
3. Press **Next**: reveals the first question's text.
4. Press **Record**: starts recording + a recording-elapsed timer (counts up,
   no cutoff — no auto-stop-on-timeout for v1; a time-warning/bell feature is
   explicitly deferred, not part of this build).
5. Press **Next** while recording: stops and saves the current take (associated
   with the current `Question`), then advances to the next question in the group
   (or ends the group if it was the last question). "Next" and "Stop" are the
   same action while a recording is active — this should be reflected visually
   (e.g. different color/label) rather than looking like neutral navigation.
6. Repeat through all questions in the group, then return to deck view (or
   advance to the next group — either is fine, use judgment).

Each take is independent and retryable — recording a new take for the same
question does not overwrite or delete previous takes. Multiple takes accumulate
per question; nothing is auto-deleted.

---

## Visibility Controls

- Per-session (not global preference, not baked into set data) toggle buttons —
  small "eye" icons — for:
  - Passage visibility
  - Question text visibility
  - Camera mirror visibility
- These exist because different schools/interview formats show or withhold
  passages/questions differently, and the user wants to flip this per-session
  without editing set data or digging into preferences.

---

## Layout (SwiftUI, three-panel)

- **Top bar**: context-sensitive controls — Start / Next / Record-Stop. Buttons
  change based on current stage (deck / passage-reveal / question-reveal /
  recording).
- **Left panel**: passage-group index for the current training set, showing
  `label` only. Used for navigation between groups, not content preview.
- **Right panel**: passive display only — camera mirror + whichever timer is
  currently active (reading-elapsed or recording-elapsed depending on stage).
  No buttons live here.
- **Bottom panel**: list of takes for the *currently active question only*
  (not a global/running log — swaps as the active question changes). Each take
  supports playback and retry (re-record a new take) from this panel.

---

## Export

- Export happens **per take, on demand** — not automatically after every
  recording, and not a single "export everything" action for v1.
- Export output:
  - Sequential, human-readable filename (question order within its group/set),
    not device-default names like `IMG_4021.mov`.
  - Short title-card caption at the start of the exported video (first few
    seconds only, then it clears) showing the question text — since the
    recipient (tutor) already knows the questions and just needs quick context
    while browsing/playing, not a persistent overlay.
  - Configurable video quality/compression: default to a modest encode (e.g.
    H.264, ~720p, conservative bitrate) since exports go to a tutor for content
    review, not archival or high-fidelity viewing. Quality should be a user-facing
    setting, not hardcoded.

---

## Explicitly Deferred (do not build in v1)

- Time-warning / bell alert when a recording approaches some duration limit.
- Automatic vision-model passage cropping / question extraction as a trusted,
  unattended pipeline (may exist as a reviewed draft-assist only, per Import
  Pipeline above).
- Any self-analysis feedback (speaking pace, filler-word detection, eye-contact
  scoring, etc.) — this app is a recording/organization workflow tool for
  tutor-driven feedback, not an automated coaching product.
- Global per-set persisted visibility settings — visibility is a per-session
  toggle, not stored data.

---

## Open / Left to Implementer Judgment

- Exact on-disk folder structure and file naming scheme for video assets.
- Whether finishing a group auto-advances to the next group or returns to deck view.
- Distribution channel (GitHub/DMG vs. App Store) — build should not assume either;
  sandboxed camera/mic entitlements should be handled correctly regardless.
