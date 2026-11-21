---
version: 1
slug: "tests-manualtestcases-html"
primary_target: "Tests/ManualTestCases.html"
related_targets: []
---

## Scope
`Tests/ManualTestCases.html`: offline manual QA checklist. Visitor mode: Operate.

## Audience and task
The developer alone at a laptop next to the iOS Simulator or an iPhone, working through 48 success/failure cases, recording Pass/Fail/Blocked/Skip with notes, exporting Markdown. Needs: bigger type, why each case matters plus the code under test, expected values at a glance, run summary by area with failing cases and the eval 9/10 gate.

## Constraints
Single offline HTML file, no CDN, no build step. Light and dark mode follow the system. Keep case IDs and localStorage key so results survive.

## Direction contract
THESIS: The run is an evacuation route; each app area is a station you clear in order. Refuses the grey test-navigator tree with status diamonds.
OWN-WORLD: ISO 7010 safe-condition signage: safety-green rail field (#14633f), white sign plates, amber You-are-here (#ffb300), signal red for fail, near-black ink; dark mode on deep green-black. System sans, heavy weights, signage scale (18px body).
STORY: The tester sees where they are on the route, what is failing, and whether the eval gate is met before reading any case.
FIRST VIEWPORT: Left green rail with route stations (area, counts, segmented progress, You-are-here), top summary (run, pass, fail, blocked, failing list, eval gate), first case card with ID sign plate, expected chips, Protects line with code ref, steps/expected columns, result column.
SIGNATURE: The route rail: stations fill with result segments as you test and the amber marker follows the area in view.
RAISES: Result in a fixed cell, filled or hollow. Action colour only on pressable controls. ID is the handle everywhere. One shared grid. Status carries icon + word, never hue alone.

seed: cec54cbb

## Decision record
21 Nov 2026: user chose the assigned card "Evacuation Route" on the decision page (sketch `.impeccable/mocks/decision/assigned.html`). Alternates shown: Triage Tag Board (pick), Ticket Wallet (competitive), category-standard test navigator.
