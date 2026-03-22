# Make Playwright Automation Naturally Perfect


## Overview
Fix critical bugs, add missing auto-wait intelligence, stealth injection, and robust error recovery to make the Playwright layer work reliably on first try — like real Playwright.

---

## Bug Fixes (Critical)

- [x] **Fix broken `first()` / `last()` / `nth()` on Locator** — Replaced with JavaScript-based nth-match resolution that correctly picks the Nth element matching the full selector.
- [x] **Fix `fill()` not clearing existing value** — Clears the field first (select-all + delete), then sets value and fires proper input/change events.
- [x] **Fix navigation errors silently ignored** — `waitForNavigation` now checks `navigationDelegate.navigationError` and throws when navigation fails.
- [x] **Fix `click()` failing on offscreen elements** — Automatic `scrollIntoView` before clicking, matching real Playwright behavior.
- [x] **Fix `evaluate<T>` type mismatch** — Clear error messages for nil/undefined and type mismatches including the actual type received.

## Stealth Injection (Missing Feature)

- [x] **Inject stealth scripts into every new page** — Reads `AutomationSettings.stealth` config and injects JS to spoof WebGL, Canvas, AudioContext, WebRTC, navigator properties, and CDP detection based on enabled toggles.

## Auto-Wait & Retry Intelligence

- [x] **Add configurable retry with exponential backoff** — Actions wrapped in retry loop (3 attempts, 100ms → 200ms → 400ms backoff) for transient DOM instability.
- [x] **Improve `networkIdle` detection** — Injected JS tracks pending XHR/fetch requests and waits for zero outstanding requests for 500ms.
- [x] **Add `waitFor()` directly on Locator** — `locator.waitFor(state: .visible)` convenience method.

## Locator Improvements

- [x] **Add scoped sub-locators** — `locator.locator("child-selector")` finds elements within a parent, matching Playwright's chaining API.
- [x] **Add `filter(hasText:)` method** — Filters matched elements by their text content.
- [x] **Add `pressSequentially()` as alias for `type()`** — Matches modern Playwright naming.
- [x] **Improve `type()` to handle special keys** — Supports Enter, Tab, Escape, Backspace, Delete, Arrow keys.
- [x] **Add `clear()` method** — Select-all and delete field content.

## Page Improvements

- [x] **Add cookie management** — `page.setCookie()`, `page.cookies()`, `page.clearCookies()` for session handling.
- [x] **Add `waitForURL()` method** — Waits for the URL to match a string or contain a substring.
- [x] **Add `waitForFunction()` method** — Waits for a JS expression to return truthy.
- [x] **Add `page.close()` method** — Self-removal from orchestrator with proper cleanup.

## Codegen Recorder Improvements

- [x] **Record navigation events on URL changes** — Detects page navigations via `didCommit` and auto-records `goto()` actions.
- [x] **Record keyboard submissions** — Captures Enter key presses on forms and records them as `pressEnter` actions.
- [x] **Improve selector generation** — Prioritizes `data-testid` → `id` → `aria-label` → `placeholder` → role → text content → name → CSS path.
- [x] **Add `waitForTimeout` recording** — Pause duration inserted as `waitForTimeout` step when user resumes recording.

## Expectation Additions

- [x] **Add `not` modifier** — `expect(locator).not.toBeVisible()` for negated assertions.
- [x] **Add `toHaveClass()` assertion** — Checks element's CSS classes.
- [x] **Add `toHaveCSS()` assertion** — Checks computed CSS property values.

## Code Generation Quality

- [x] **Proper string escaping** — Quotes, backslashes, newlines, and tabs escaped in generated Swift code strings.
- [x] **Add `waitForLoadState` after navigation** — Generated code includes `waitForLoadState(.networkIdle)` after `goto()` calls.
- [x] **Group related actions** — Fill followed by click/pressEnter gets a `// Submit form` comment.

---

## Additional Fixes Applied

- [x] **Fix CodegenWebView not exposing WKWebView to parent** — URL bar back/forward/reload and manual navigation now work in PlaywrightStudioView.
- [x] **Fix Settings not saving all changes** — Replaced individual property onChange handlers with per-section Equatable onChange, so all setting changes persist.
- [x] **Fix `.symbolEffect(.pulse)` on non-symbol Circle** — Removed ineffective modifier from recording indicator.
- [x] **Add `.presentationContentInteraction(.scrolls)` to network sheet** — Scroll gesture no longer fights sheet resize on multi-detent sheets.
