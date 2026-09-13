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

Minimum OS: macOS 26.0, using the native Liquid Glass appearance. The v1
interface is English only; user-authored content supports Unicode, including Korean.

---

## Data Model (SwiftData)

Hierarchy: `TrainingSet` → `PassageGroup` (ordered) → `Question` (ordered) → `Take`

```swift
@Model
final class TrainingSet {
    var title: String              // e.g. "Yonsei 2024 - Humanities"
    var createdAt: Date
    var lastOpenedAt: Date?       // local recency; nil until first opened
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
   optional) and types in the associated question(s) as plain text. Each group
   supports one rectangular crop from one PDF page; multi-crop/multi-page
   passages are out of scope for v1.
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
- Optional "blind import" toggle for prepared training-set files: user picks a file and imports without previewing
  contents — only a summary count is shown (e.g. "14 questions imported across
  5 groups"). Off by default. Exists because this app may be shared with friends
  who import sets someone else prepared for them.
- Raw PDF preparation requires manual cropping/transcription and does not offer
  blind import.

**Training-set sharing (v1):**
- Users can export prepared training sets and import sets shared by friends.
  Shared sets include passage images and questions, without recordings.
- Format: a `.outerview` ZIP archive
  containing a versioned `manifest.json` and passage images. The manifest stores
  the set title, group labels, question text, and explicit ordering.

---

## Session Flow

1. **Deck view**: list of `PassageGroup` items in a `TrainingSet`, shown by
   `label` only (e.g. "Ethics," "Case study 3") — no passage or question content
   visible. This is navigation, not preview.
2. User selects a group and presses **Start**.
   - Start activates the camera/microphone for this training session, requesting
     permission if needed. The launch screen and group deck keep capture off;
     choosing devices does not activate them.
   - If the group has a passage image: it's revealed, with a reading-elapsed
     timer (counts up, no cutoff).
   - If the group has no passage image: skip straight to the first question
     (no empty reading stage).
3. Press **Next**: reveals the first question's text.
4. Press **Record**: starts recording + a recording-elapsed timer (counts up,
   no cutoff — no auto-stop-on-timeout for v1; a time-warning/bell feature is
   explicitly deferred, not part of this build).
5. Press **Stop**: stops and saves the current take associated with the current
   `Question`, remaining on that question. **Record / Stop** is a separate
   control from **Previous / Next**.
6. When not recording, **Previous / Next** lets the user navigate freely without
   requiring a take. While recording, disable both navigation controls and other
   in-app navigation that would change the active question/group/set. Keep
   navigation disabled while the take finishes saving.
7. Repeat through all questions in the group, then return to deck view (or
   advance to the next group — either is fine, use judgment).

**End Training** returns to the group deck and turns capture off. Finishing a
group, changing groups, opening the editor, or returning to Training Sets also
turns capture off. End Training is disabled during recording/saving. Closing or
quitting when not recording/saving asynchronously releases capture devices before
completing; late permission/setup results cannot reactivate ended sessions.

Each take is independent and retryable — recording a new take for the same
question does not overwrite or delete previous takes. Multiple takes accumulate
per question; nothing is auto-deleted.

---

## Visibility Controls

- Passage and question text visibility are persistent global preferences in the
  Settings pane. These preferences never bypass the session's reveal stages.
- Camera mirror and timer visibility each have a small eye button at the corner
  of that item. These are independent per-session controls, with the eye button
  remaining available when content is hidden so it can be restored.
- Hiding a timer or camera preview affects display only; elapsed timing and
  recording continue normally.

---

## Launch Screen and Workspace

The app opens to an Xcode-style launch screen listing the user's training sets.
This is the entry point to the app, separate from the practice workspace and
its passage-group deck view.

- Use a compact 820 × 520 welcome window with branding/actions on the left
  and recent training sets on the right. Expand for practice and restore the
  compact size when returning home.
- Sort sets by last-opened date, newest first; never-opened sets follow, newest
  created first. Update lastOpenedAt whenever a set opens. This is local metadata,
  not part of the shared training-set archive.
- List training sets by title, with summary metadata such as group/question
  counts, without exposing passage images or question text.
- Provide actions to create a training set from a PDF and import a prepared
  training-set file shared by someone else.
- Opening a training set enters its workspace in deck view; it does not
  automatically reveal a passage/question or start recording.
- Provide a way to return to the training-set launch screen from the workspace.
  Disable this navigation during recording and saving, like other navigation
  that changes the active set.
- When there are no training sets, show an empty state with the same creation
  and import actions.

For v1, use one main window: opening a set replaces the launch screen with its
workspace, and a Training Sets button returns home. The workspace has a central
passage/question area, narrow group sidebar, camera/timer on the right, and a
collapsible takes strip below. Visual details will be reviewed in the UI shell.

## Practice Workspace Layout (SwiftUI)

- **Top bar**: context-sensitive controls — Start, Previous / Next, and a separate
  Record / Stop control. Previous / Next is disabled during recording and saving. Buttons
  change based on current stage (deck / passage-reveal / question-reveal /
  recording).
- **Left panel**: passage-group index for the current training set, showing
  `label` only. Used for navigation between groups, not content preview.
- **Center panel**: passage and question content, subject to reveal stage and
  global visibility preferences.
- **Right panel**: camera mirror + whichever timer is
  currently active (reading-elapsed or recording-elapsed depending on stage).
  Each item has its own corner eye button; recording/navigation controls stay
  in the top bar.
- **Bottom panel**: list of takes for the *currently active question only*
  (not a global/running log — swaps as the active question changes). Each take
  supports playback and retry (re-record a new take) from this panel.

---

## Video Export

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
- Per-set persisted visibility settings — passage/question visibility lives in
  global preferences; camera/timer visibility is per-session.

---

## Open / Left to Implementer Judgment

- Exact on-disk folder structure and file naming scheme for video assets.
- Whether finishing a group auto-advances to the next group or returns to deck view.
- Distribution channel (GitHub/DMG vs. App Store) — build should not assume either;
  sandboxed camera/mic entitlements should be handled correctly regardless.
