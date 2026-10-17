# Lifecycle and compatibility investigation — October 17, 2026

The audit began at `8f89539` and covered native input identity, mouse/modifier handling, asynchronous AX capture and confirmation, window membership, application lifecycle, hidden state, both termination paths, settings, permissions, monitoring recovery, login-item status, and build configuration. The earlier Discord, Chrome, and CotEditor reports informed the questions without restricting the scope. Current source and history were checked independently by parallel reviewers.

## Findings and changes

| Finding | Evidence and consequence | Resolution |
| --- | --- | --- |
| Unrelated application hides canceled valid attempts | The monitor canceled on every workspace hide notification, including another process and malformed notifications. A two-process disposable AppKit fixture received a real hide notification identifying only the other process. The original handler also canceled simulated press, pending-release, and verified phases. This could miss a quit and incorrectly attribute the interruption to the target. | Retain original attempt ownership from press through confirmation. Ignore unrelated visibility notifications; preserve target hide/unhide cancellation and the existing qualified Discord transition. |
| Secondary/auxiliary presses did not interrupt pending decisions | Both event masks omitted right/other mouse-button presses, although new interactions invalidate intent. These events could leave an earlier quit pending during a context-menu or auxiliary-button action. The omission is confirmed in source; a physical unintended quit was not reproduced. | Subscribe to right/other down events and route them only to cancellation, before metadata reads or AX work. Cover both global and local masks with regression checks. |
| Original process identity was not pinned through final termination | The monitor rechecked eligibility using a retained `NSRunningApplication` but did not compare its current identity with the original press. Apple's SDK explicitly documents that its PID can change following automatic termination. An old AX snapshot must not authorize termination of a new process. This is a confirmed missing invariant; automatic relaunch during an actual close was not reproduced. | Retain the original application object and native PID/bundle identity. Check AppKit object equality plus the pinned identity when accepting the AX hit, beginning confirmation, and immediately before either quit path. Simulated regressions reject changed PID or bundle. |

The changes preserve native close-button proof, exclusions, protected-app checks, save/dialog protection, generation invalidation, observer cleanup, and force-quit opt-in. No confirmation interval, read deadline, worker scheduling, or app-specific exception changed.

Apple's [workspace notification contract](https://developer.apple.com/documentation/appkit/nsworkspace/didhideapplicationnotification) identifies the affected application. Its [application-instance documentation](https://developer.apple.com/documentation/appkit/nsrunningapplication) describes mutable, run-loop-cached state; the installed SDK's `NSRunningApplication.h` additionally documents PID changes after automatic termination and recommends object equality when comparing applications. [Secondary and auxiliary mouse events](https://developer.apple.com/documentation/appkit/nsevent/eventtype/rightmousedown) are separate from left-button input.

## Disposable fixture evidence

Host: macOS 27.0.1 (26A434), arm64. Fixtures used only their own in-memory windows and exited through separate cleanup. No personal application was a termination target. Native/self-AX inspection and programmatic AppKit actions are distinct from a physical click through CallQuits.

Seven window scenarios ran the production `AccessibilityClient` and `CloseSession` unchanged, with snapshot qualification injected into the probe:

| Scenario | Observation |
| --- | --- |
| Two native window tabs, closed through `performClose` | AX exposed one selected tab. The surviving tab appeared under a different identity; production canceled with `replacementWindow`. |
| Same tab group, standard close button's `performClick` | Same result. This is a conservative missed quit in any-window mode, left unresolved because distinguishing a pre-existing hidden tab from a genuine replacement needs additional trustworthy identity evidence. |
| Minimized sibling | It remained in `AXWindows` after the visible window closed. |
| Attached sheet | Direct `AXSheet` child; production canceled with `blockingUI`. |
| Application-modal dialog | `AXDialog` with `AXModal=true`; production canceled with `blockingUI`. |
| Utility panel | Enumerated as `AXFloatingWindow`; the existing standard-window requirement deliberately excludes its close control. |
| Retained, ordered-out window | Absent from `AXWindows` despite still existing as an `NSWindow`. No generic inference about all retained objects or documents is safe. |

These limits agree with the distinctions between [native tab groups](https://developer.apple.com/documentation/appkit/nswindowtabgroup), [ordering a window out](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)), and [closing a window](https://developer.apple.com/documentation/appkit/nswindow/close()). The audit did not weaken replacement or window-role checks to hide these limitations.

Additional AppKit fixtures confirmed that the existing settings reopen sequence restores a minimized settings window. A graceful termination request returned true while a disposable app immediately vetoed it, and while another deferred then declined it; both remained alive until cleanup. Current one-shot request handling and Activity wording correctly distinguish a request from actual exit.

A disposable permission probe reported Accessibility trust false, listen access false, a nonnil annotated-session event tap, and tap enabled false. It destroyed the tap immediately without reading input or requesting permission. This supports the existing enabled-state check, not a claim about the installed CallQuits app's permission state.

Local source, runners, and raw output remain under the ignored `build/fixture-ax-audit/`, `build/lifecycle-audit-probe/`, and `build/policy-audit-probe/` directories. These are development evidence, not shipped app resources.

The handler comparison used synthetic notifications against source copies of the original and updated production handler. All six unrelated/malformed cases across press, pending-release, and verified phases changed from cancellation to preservation, with no spurious Activity entry. All three target-hide cases still canceled. This complements the real workspace-notification fixture; it is not a full physical-input reproduction.

## Validation and remaining gaps

Follow the canonical [routine validation](TESTING.md#routine-validation) and [live matrix](TESTING.md#manual-matrix). Regression coverage distinguishes visibility routing, original process identity, and event subscriptions; existing suites retain close-button, exclusion, sheet, replacement, expiry, and force boundaries.

All 95 debug XCTest cases passed (35 app-integration tests and 60 core tests). The release-configuration development bundle at `build/development/broad-audit/CallQuits.app` built with ad hoc signing and passed strict signature verification. The initial sandboxed release build was blocked by `dsymutil`; the same build succeeded with desktop execution access. Working and staged whitespace checks passed. Source/resource structure and Xcode configuration were unchanged, so project regeneration was unnecessary. The installed app and finalized release bundles were preserved; nothing was pushed, published, or notarized.

The full physical event-to-AX-observer-to-quit pipeline was not validated in this run. Other Spaces/fullscreen, hardware/trackpad input, actual automatic termination/relaunch, sleep/session switching, real permission revocation/recovery, login approval, installation/upgrade on another account or Mac, macOS 14, and Intel remain untested here. No click-to-request, process-exit latency, or visible Dock-disappearance measurements were collected.

Residual risks include windows appearing before observer registration or after the final snapshot, same-process window rearrangement before asynchronous AX hit testing, missing provider notifications, incomplete provider metadata, secure-input effects on cancellation delivery, and AX work queued behind a slow provider. These are plausible or previously documented boundaries, not newly reproduced failures. The audit supplies no evidence for shortening safety delays, changing concurrency, or adding compatibility exceptions.
