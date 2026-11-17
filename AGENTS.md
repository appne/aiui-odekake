# aiui-odekake

Combined going-out agent for Rokid Glasses: zaisen (Keihan train
positions) + rain radar in one page, built 2026-11-17 at the
user's request. Voice launch name: "odekake".
Agent ID: 39389b0b6c2647648ca84645f2aa0cae (Studio Version 1.0.1;
first package 39389b0b6c2647648ca84645f2aa0cae-1794916110573.aix,
36.48 KB).

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

- Current build: **odk-b3** (assembled from zai-b41 + rdr-b12).
  odk-b3 adds DEBUG keys (user suggestion 2026-11-17): in
  onKeyUp, 'a' (KeyA / keyCode 65) switches to the next mode
  and 's' (83) to the previous, directly, without the
  tap->swipe sequence — the bridge daemon's send_key cadence
  (~5 s per token, measured 2026-11-17) cannot fit the 3 s
  tap->swipe window, so development verification drives mode
  switches with these keys (daemon scan 30 / 31).
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
