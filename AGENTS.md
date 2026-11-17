# aiui-odekake

Combined going-out agent for Rokid Glasses: zaisen (Keihan train
positions) + rain radar in one page, built 2026-11-17 at the
user's request. Voice launch name: "odekake".
Agent ID: 39389b0b6c2647648ca84645f2aa0cae (Studio Version 1.0.6;
package 39389b0b6c2647648ca84645f2aa0cae-1794929907725.aix,
37.90 KB, odk-b6).

## Modes

- **combo** (default): zaisen 'single' lines on top, radar wide
  view below (home/here auto-switch as in radar); overflow
  scrolls with swipes. Tap cycles the radar forecast
  0 -> +5 -> +10 -> +30 (no +60 in combo). BACK reloads both.
- **zaisen**: the zaisen agent as-is.
- **radar**: the radar agent as-is.

Mode switch: tap, then a swipe within 3 s. NOTE (wearer-
confirmed 2026-11-17): the R08 bridge consumes a swipe that
lands within ~700 ms of the tap as a tap+swipe combo gesture,
so the swipe must come after a short breath (~1 s works);
this is structural, not a page bug. The tap's effect is
reverted, then the mode switches (down swipe = next, up =
previous, wrapping combo -> zaisen -> radar -> combo). The mode
switched to keeps its previous display state. BACK follows the
zai-b40 / rdr-b12 rule in every mode (within 3 s of the last
reload / tap / swipe it passes through to exit; otherwise it
reloads the current mode).

## Build / maintenance

- Current build: **odk-b7** (assembled from zai-b41 + rdr-b12).
  Tap-arm race fix (odk-b7, measured 2026-11-18): the tap
  timer fired 300 ms after GlobalHook unless an ArrowUp/
  Down keyUP cancelled it — but a long swipe's ArrowDown
  keyUP lands past 300 ms (its horizontal ArrowRight
  repeats stretch the sequence to ~450 ms), so the tap
  fired mid-swipe and the late ArrowDown became a
  tap->swipe mode switch (user-reported: long swipes
  switched modes). Fix: any arrow keyDOWN cancels the tap
  arm (onKeyDown), ArrowLeft/Right keyUPs also cancel it,
  and the arm window is 500 ms. The same timer pattern
  exists in standalone radar/zaisen (milder symptoms);
  not yet ported there.
  DEBUG drive (user suggestion 2026-11-17): the daemon's
  send_key cadence (~5 s per token) cannot fit the 3 s
  tap->swipe window, so development verification switches
  modes with a dedicated key. Measured facts (kensho
  vrf-b34 keylog, 2026-11-18): ink key events carry ONLY
  `code` (key / keyCode are always undefined — every
  kc-based condition in every page was always dead); a
  physical temple swipe delivers GlobalHook, then
  ArrowRight/Left x1-2 (count varies!) and ArrowDown/Up
  x1, so count/NOTIFICATION fingerprints are unreliable
  (odk-b4's plain DPAD triggers and odk-b5's macro guard
  both failed on physical swipes); daemon scan 149
  (SETTINGS) delivers a 'Shortcut' keyDOWN only, which a
  temple swipe can never produce; scan 148 and letter
  scans deliver nothing. odk-b6: onKeyDown 'Shortcut' =
  next mode; BT keyboard a/s = next/previous. Development
  exit needs no page support (launcher via adb am start).
- The page is ASSEMBLED by `tools/merge.py` from
  `../aiui-zaisen/pages/index/index.ink` and
  `../aiui-radar/pages/index/index.ink`. Engine identifiers are
  prefixed (z*/r*); engine setData calls write display buffers
  that the shell's syncDisplay() composes per mode.
- **Standing rule (user, 2026-11-17): when zaisen or radar gets
  a functional fix, odekake gets the same fix.** Port by editing
  the source agent, re-running `python3 tools/merge.py`,
  node --check on the extracted script, bumping the build
  string in merge.py (SHELL_FIELDS data.build), and rebuilding
  in Studio (edit the EXISTING odekake project -> Repackage and
  Save; Import from GitHub would create a new agent).
- Layout (odk-b2): the whole column (head / zaisen lines /
  foot / radar status / hint / image) lives in one
  <scroll-view> whose scroll-top the shell drives (kensho
  vrf-b32/b33: no page-scroll APIs exist, arrow keys never
  scroll the inner view, and a text slot cleared to '' keeps
  its line height). A mode switch resets the scroll position:
  combo/zaisen to 0, radar to RADAR_TOP (the offset of the
  radar block inside the column, so the '' zaisen slots above
  it are scrolled past). Combo swipes step scroll-top by
  63 px. The zaisen footer rides in the line flow (zai-b41),
  both in zaisen mode and in combo's single lines.

Personal use only (contains zaisen); do not submit for store
review.
