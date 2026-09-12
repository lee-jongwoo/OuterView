# OuterView

The ultimate interview-preparation suite.

## Overview

The main purpose of this app is to help students prepare for in-person interviews. Consult SPEC.md for implementation details.

## Status Quo

The first SwiftUI shell is ready for layout review: an Xcode-style training-set
launch screen, a set editor, and a practice workspace with question navigation,
visibility controls, and a collapsible takes area. Choose **Explore a Sample**
to walk through the workspace without creating a set.

Training sets now persist locally with SwiftData, including last-opened dates and
explicit group/question ordering. The editor supports reordering and removal;
Cancel leaves saved content unchanged. Right-click a set on the launch screen to
edit or delete it. Deletion cascades to its records and cleans up unused assets.

The library lives under the sandbox's Application Support/OuterView directory:
`Library.store` holds metadata; `Assets/<set UUID>/images` and `videos` hold media.
Cleanup runs after successful changes and at startup to recover interrupted cleanup.
PDF selection, page navigation, rectangular cropping, and saved passage previews
are implemented. Camera/microphone selection, live preview, recording, per-question playback, and
retry are implemented. Use Enable Camera to grant access. Failed saves can be
retried, and pending recordings are recovered on the next launch. Shared-set
export is available from a set’s context menu. Import supports review before saving
or blind import with summary counts. Video export is next.

## Development checkpoints

Commit each completed implementation pass after its relevant checks pass.
Passes 1–3 (persistence, PDF preparation, and session flow) are complete.
Passage groups now reveal the passage first with a reading timer; question-only
groups skip directly to questions. Pass 4 adds camera capture, take review, and interrupted-save recovery.

Run the `OuterViewTests` target for persistence/reopen, ordering, recording
preservation, cascading deletion, asset cleanup, and path validation coverage.

Open `OuterView.xcodeproj` and run the `OuterView` scheme on macOS 26.0 or later.

## Shared-set format

`.outerview` is a ZIP archive with UTF-8 names and uncompressed (STORE) entries,
containing `manifest.json` (version 1) and PNG passage images. Groups/questions
have explicit zero-based order values. Local IDs, recency, and recordings are
excluded. Import validates size limits, entry names, checksums, images, and order
before saving anything. Share the exported file directly without re-zipping it.
