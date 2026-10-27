#pragma once

// Buffer / Capsule / Mailbox integration points for the Linux IME.
//
// Buffer and Capsule hook the commit and key surfaces below. Mailbox is
// still a later port and must not fork a second librime runtime.
//
// 1. Commit
//    RimesIme::commitText is the only path from librime commit text into a
//    Fcitx5 InputContext. When Buffer capture owns that IC, the text becomes
//    a staged block instead of ic->commitString — the same intercept as macOS
//    drainCommit before Delivery.insert. Capsule insert does not go through
//    this hook: CapsuleService calls ic->commitString after an armed-token
//    recheck so a capturing Buffer cannot swallow a note as a chip.
//
// 2. Keys
//    BufferService::HandleEarlyKey sits in front of CapsuleService::HandleEarlyKey
//    and RimesState::keyEvent. Alt+Shift+B toggles Buffer.
//    Alt+Shift+C toggles Capsule. While Buffer is capturing, Return,
//    Backspace, Escape (this IC only), Ctrl+A and Ctrl+V stay with Buffer.
//    While Capsule is armed and Buffer is not capturing, Tab, arrows, Return,
//    Escape (this IC only), Ctrl+1–9, Ctrl+C and printable search keys are
//    consumed here. Same-IC reactivation disarms Capsule (field may have
//    changed).
//
// 3. Session / field isolation
//    One Rime session per Fcitx5 InputContext (RimesState). Buffer and
//    Capsule are process-wide and bind their session to one IC pointer
//    token. Focus change returns typing to the host.
//
// 4. UI
//    Candidates stay on Fcitx5's InputPanel. GTK companions (rimes-buffer,
//    rimes-capsule) talk length-prefixed JSON over separate Unix sockets.
//    They are renderers, not a second engine. A dead UI is respawned.
//
// 5. Still later
//    - Mailbox
//    - Capsule clipboard history, iCloud, password vault, media kinds
//    - Custom candidate chrome that follows the Buffer caret
//    - Global hotkeys while another IM is active
//    - Cross-batch chord pairing (macOS frontend only)
//    - IBus engine (would reuse RimeEngine + these hooks)

namespace rimes::linuxime {

inline constexpr const char* kCommitHookNote =
    "RimesIme::commitText is the single Fcitx5 commit path";

}  // namespace rimes::linuxime
