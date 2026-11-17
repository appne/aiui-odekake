# aiui-odekake

Combined going-out agent for Rokid Glasses: zaisen (Keihan train
positions) + rain radar in one page, built 2026-11-17 at the
user's request. Voice launch name: "odekake".

## Modes

- **combo** (default): zaisen 'single' lines on top, radar wide
  view below (home/here auto-switch as in radar); overflow
  scrolls with swipes. Tap cycles the radar forecast
  0 -> +5 -> +10 -> +30 (no +60 in combo). BACK reloads both.
- **zaisen**: the zaisen agent as-is.
- **radar**: the radar agent as-is.

Mode switch: tap, then a swipe within 3 s. The tap's effect is
reverted, then the mode switches (down swipe = next, up =
previous, wrapping combo -> zaisen -> radar -> combo). The mode
switched to keeps its previous display state. BACK follows the
zai-b40 / rdr-b12 rule in every mode (within 3 s of the last
reload / tap / swipe it passes through to exit; otherwise it
reloads the current mode).

## Build / maintenance

- Current build: **odk-b1** (assembled from zai-b40 + rdr-b12).
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
- Layout assumption to verify on device (odk-b1): one stacked
  column (head / zaisen lines / foot / radar status / hint /
  image); inactive modes' slots are set to '' — this relies on
  empty <text> elements collapsing (or sitting below the fold)
  and an empty-src <image> sitting below the fold in zaisen
  mode. If the wearer check shows the radar image pushed down
  in radar mode, the layout needs rework.

Personal use only (contains zaisen); do not submit for store
review.
