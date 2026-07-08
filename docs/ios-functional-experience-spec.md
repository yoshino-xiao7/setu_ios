# iOS Functional Experience Spec

Date: 2026-07-08
Scope: `setu_ios` interaction & functional UX. **Companion to `ios-soft-pink-ui-design.md`** — that doc is comprehensive on the visual system and page structure and stands as-is. This one covers what it deliberately does not: runtime behavior, states, long-running tasks, network resilience, and platform integration. No visual redesign here; both docs share the same `Setu*` components.

---

## 1. Assessment of the existing UI doc

`ios-soft-pink-ui-design.md` fully covers: color/type/spacing tokens, component library, per-tab page structure, rollout phases, and accessibility. **No additions needed there.** The gaps below are functional, not visual — they're about how flows behave, not how they look.

---

## 2. Canonical state ladder

The app already models `LoadState<T>` (idle/loading/loaded/failed). Make it uniform and complete across every data-driven view via a shared `SetuStateView` wrapper (pairs with `SetuEmptyState` from the UI doc).

| State | Behavior |
| --- | --- |
| idle/loading | Skeleton for lists/grids; inline `ProgressView` for actions. No layout jump on load. |
| loaded-empty | Branded empty state + a primary next action (e.g. "还没有作品 · 去创作"). |
| failed | Inline retry for page loads; transient toast for action failures. Show a human message, not a raw error. |
| unauthorized (401) | Route to auth without a content flash; preserve intended destination to resume after login. |
| submitting | Disable duplicate taps; progress on destructive/long ops. |

Acceptance: no screen shows a bare spinner or a dead-end empty list; every list/grid handles all five.

---

## 3. Long-running tasks (AI drawing)

The highest-stakes flow. Backend supports polling + Live Activity push tokens (`/mobile/live-activities`).

- **Submit → immediate feedback:** optimistic "已提交" job card, never a frozen button.
- **Progress:** in-app job card reflects queue/generating/done; mirror to a **Live Activity** when the app backgrounds so users don't have to keep the app open.
- **Failure/timeout:** clear failed state with a retry/reuse-params path; don't strand the job as perpetually "generating".
- **Reconciliation:** on app foreground, reconcile local job state with server truth (poll once) before trusting cached status.
- **Cancel:** expose cancel where the backend allows; reflect terminal state in both the card and the Live Activity (`/end`).

---

## 4. Network resilience & data freshness

- **Offline:** detect connectivity; show a non-blocking "离线" banner and serve last-good cached data where safe (history, playlists) rather than an error screen.
- **Retry policy:** idempotent GETs auto-retry with backoff once; mutations never auto-retry (user-initiated only) to respect nonce/replay semantics.
- **Pull-to-refresh + pagination:** every paged list (points logs, history, square, notifications) supports refresh and clear "load more / end reached" affordances; no silent dead ends.
- **Session expiry:** on 401 mid-session, refresh signature if possible, else route to login preserving context — no data loss on drafts (AI draw draft store already exists; extend the pattern to other in-progress forms).
- **Image loading:** consistent placeholder → loaded → failed for `SetuImageTile`; cache thumbnails; cap concurrent decodes in grids for scroll performance.

---

## 5. Music & background audio

- **Background playback:** already targeted; verify lock-screen Now Playing, remote controls, and artwork stay in sync with the mini player.
- **Interruptions:** handle calls/other-audio (AVAudioSession interruption) — pause and resume correctly; handle route changes (unplug headphones → pause).
- **Upstream URL reality:** playback uses upstream media URLs (`REMOTE_URL`); handle expired/failed URLs with a graceful "重新获取播放地址" rather than a silent stall. Seeking depends on upstream Range — degrade seek UI when unsupported.
- **Queue clarity:** current track, next-up, and play mode always visible from the mini player and full player.

---

## 6. Navigation, notifications & deep links

- **Tab state:** each tab keeps an independent `NavigationStack` (already true) — preserve scroll/stack when switching tabs.
- **Notification routing:** tapping a push/notification-center item deep-links to the concrete target (job detail, delete-request detail) via typed `AppRoute`, not just the list.
- **Back-stack depth:** admin flows are deep — provide a way back to section root; avoid 5-level pushes with no shortcut.
- **Unread integrity:** unread badge/count reconciles after reading (already partially handled); ensure it updates optimistically and confirms with server.

---

## 7. Permissions & first-run

- Request notification/photo permissions **in context** (at the moment of use), not on launch, with a pre-prompt explaining why.
- Passkey/Associated Domains require the real RP ID on device (see `passkey-associated-domains.md`) — surface a clear fallback to password login when passkey is unavailable.
- Admin entry points render only for `role == admin` (already the rule) — never flash admin UI to non-admins.

---

## 8. Performance & feel

- 60fps scrolling in image grids (AI/square) — lazy load, thumbnail-first, cancel offscreen loads.
- Respect Reduce Motion for the gradient/hero animations from the UI doc.
- Keep main-thread work off decode/network; debounce search (music) and asset filters.

---

## 9. Acceptance

- `swift test` for any Core/client change; build the app target for view/navigation changes.
- Every data view exercises the §2 ladder; AI-draw and music verified against §3/§5 on device (background, interruption, expiry).
- Deep links from notifications land on the correct detail screen.
- Offline and 401-mid-session paths verified to not lose in-progress user input.

## 10. References

- `ios-soft-pink-ui-design.md` — visual system & page structure (primary UI doc)
- `backend-mobile-contract.md` — `/mobile/**`, APNs, Live Activity lifecycle
- `passkey-associated-domains.md` — passkey/RP ID setup
- `RootAppView.swift` / `AppRoute.swift` — navigation & routing model
