#!/usr/bin/env python3
"""Assemble the odekake AIUI page from the zaisen (zai-b40) and
radar (rdr-b12) pages.

Odekake is a combined agent: it embeds both engines in one page
and switches between combo / zaisen / radar display modes. The
engines are merged mechanically so that a fix in aiui-zaisen or
aiui-radar can be ported by re-running this script:

  1. zaisen identifiers are prefixed z*, radar identifiers r*
     (word-boundary renames; the timetable storage key and URLs
     are untouched).
  2. Each engine's setData() calls are rerouted to engine-local
     display buffers; the shell's syncDisplay() composes the
     visible fields for the current odekake mode.
  3. The engines' own onKeyUp / data blocks are dropped; the
     shell owns data, key handling and the mode-switch gesture.

After a re-merge, eyeball the diff, node --check the script,
bump the build string in SHELL_FIELDS (data.build), and rebuild
in Studio as usual.
"""
import re
import sys

BASE = '/home/hatch/workspace/rokid-ios-bridge/'
Z_IN = BASE + 'aiui-zaisen/pages/index/index.ink'
R_IN = BASE + 'aiui-radar/pages/index/index.ink'
OUT = BASE + 'aiui-odekake/pages/index/index.ink'


def script_body(path):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'<script setup>\n(.*)\n</script>', text, re.S)
    if not m:
        sys.exit('no script setup in ' + path)
    return m.group(1)


def rename(text, pairs):
    for old, new in pairs:
        text = re.sub(r'\b' + re.escape(old) + r'\b', new, text)
    return text


def must_replace(text, old, new, count=1):
    if old not in text:
        sys.exit('MISSING replacement target:\n' + old[:200])
    return text.replace(old, new, count)


# ---------------------------------------------------------------- zaisen
Z_METHODS = [
    ('fetchTimetableRemote', 'zFetchTimetableRemote'),
    ('fetchTimetable', 'zFetchTimetable'),
    ('isCountdownOvertake', 'zIsCountdownOvertake'),
    ('isOvertakeWait', 'zIsOvertakeWait'),
    ('isNakanoshima', 'zIsNakanoshima'),
    ('noteFetchFailure', 'zNoteFetchFailure'),
    ('startAutoReload', 'zStartAutoReload'),
    ('stopAutoReload', 'zStopAutoReload'),
    ('nearestStation', 'zNearestStation'),
    ('parsedTrains', 'zParsedTrains'),
    ('probeLocation', 'zProbeLocation'),
    ('saveTimetable', 'zSaveTimetable'),
    ('serviceDateStr', 'zServiceDateStr'),
    ('nextTrainsText', 'zNextTrainsText'),
    ('notPassedFocus', 'zNotPassedFocus'),
    ('updateTypeWarn', 'zUpdateTypeWarn'),
    ('resolveType', 'zResolveType'),
    ('scheduleRetry', 'zScheduleRetry'),
    ('onReloadTick', 'zOnReloadTick'),
    ('fetchData', 'zFetchData'),
    ('parseTrain', 'zParseTrain'),
    ('trainLabel', 'zTrainLabel'),
    ('stationLine', 'zStationLine'),
    ('applyLines', 'zApplyLines'),
    ('renderSingle', 'zRenderSingle'),
    ('typeKeyFor', 'zTypeKeyFor'),
    ('ttDayType', 'zTtDayType'),
    ('nowMinutes', 'zNowMinutes'),
    ('lastDestOf', 'zLastDestOf'),
    ('autoActive', 'zAutoActive'),
    ('applyHead', 'zApplyHead'),
    ('clockText', 'zClockStr'),
    ('clearRetry', 'zClearRetry'),
    ('stopsAt', 'zStopsAt'),
    ('failHead', 'zFailHead'),
    ('onLoad', 'zOnLoad'),
    ('onUnload', 'zOnUnload'),
    ('render', 'zRender'),
    ('move', 'zMove'),
]
Z_FIELDS = [
    ('_ttLastTry', 'zTtLastTry'),
    ('_reloadUntil', 'zReloadUntil'),
    ('_reloadTimer', 'zReloadTimer'),
    ('_lastFetch', 'zLastFetch'),
    ('_headBase', 'zHeadBase'),
    ('_retryTimer', 'zRetryTimer'),
    ('_clockTimer', 'zClockTimer'),
    ('_posByWdf', 'zPosByWdf'),
    ('_lastOkHm', 'zLastOkHm'),
    ('_elapsedSec', 'zElapsedSec'),
    ('_userMoved', 'zUserMoved'),
    ('_trains', 'zTrains'),
    ('_posDate', 'zPosDate'),
    ('_posAt', 'zPosAt'),
    ('_delay', 'zDelay'),
    ('_nowMin', 'zNowMin'),
    ('_typeWarn', 'zTypeWarn'),
    ('_typeCov', 'zTypeCov'),
    ('_mode', 'zMode'),
    ('_tt', 'zTt'),
]

z = script_body(Z_IN)
z_consts, z_obj = z.split('export default {', 1)
# Drop the data block (the shell owns data) and the engine's own
# onKeyUp (the shell owns keys); keep everything else verbatim.
z_obj = re.sub(r'  data: \{.*?\n  \},\n(?=  _trains:)', '', z_obj, flags=re.S)
z_obj = z_obj[:z_obj.index('\n  onKeyUp(event) {')]
z_consts = rename(z_consts, Z_METHODS + Z_FIELDS)
z_obj = rename(z_obj, Z_METHODS + Z_FIELDS)
z_obj = z_obj.replace('this.data.center', 'this.zCenter')
# setData reroutes -> display buffers + syncDisplay.
z_obj = must_replace(z_obj,
    "    this.setData({ head: mark + this.zHeadBase + modeMark + (this.zTypeWarn ? ' ⚠種別表' : ''), clock: this.zClockStr() });",
    "    this.zHeadText = mark + this.zHeadBase + modeMark + (this.zTypeWarn ? ' ⚠種別表' : '');\n"
    "    this.zClockText = this.zClockStr();\n"
    "    this.syncDisplay();")
z_obj = re.sub(r"this\.setData\(\{ foot: (.+?) \}\);",
               r"this.zFootText = \1; this.syncDisplay();", z_obj)
z_obj = must_replace(z_obj, "        this.setData({ center: idx });",
                     "        this.zCenter = idx;")
z_obj = must_replace(z_obj, "    this.setData({ center: c });",
                     "    this.zCenter = c;")
z_obj = must_replace(z_obj,
    "    const patch = {};\n"
    "    for (let k = 0; k < 14; k++) patch['L' + k] = lines[start + k] || '';\n"
    "    this.setData(patch);",
    "    this.zLines = [];\n"
    "    for (let k = 0; k < 14; k++) this.zLines.push(lines[start + k] || '');\n"
    "    this.syncDisplay();")
# renderSingle returns its lines so the combo display can use the
# raw (unwindowed) single-mode lines regardless of the zaisen mode.
z_obj = must_replace(z_obj,
    "    if (upT) {\n"
    "      if (upT.seg !== f) lines.push(this.zStationLine(upT.seg, true));\n"
    "      lines.push('　' + this.zTrainLabel(upT, all, false));\n"
    "    }\n"
    "    this.zApplyLines(lines, centerLine);",
    "    if (upT) {\n"
    "      if (upT.seg !== f) lines.push(this.zStationLine(upT.seg, true));\n"
    "      lines.push('　' + this.zTrainLabel(upT, all, false));\n"
    "    }\n"
    "    return { lines: lines, centerLine: centerLine };")
z_obj = must_replace(z_obj,
    "    if (this.zMode === 'single') { this.zRenderSingle(all); return; }",
    "    if (this.zMode === 'single') { const rs = this.zRenderSingle(all); this.zApplyLines(rs.lines, rs.centerLine); return; }")
# The shell owns the gesture stamps; drop the engines' copies.
z_obj = z_obj.replace("  _lastBackAt: 0,\n", "")
z_obj = z_obj.replace("  _lastInteractAt: 0,\n", "")
z_members = z_obj.rstrip()
assert z_members.endswith(','), 'zaisen members should end with a comma'

# ---------------------------------------------------------------- radar
R_METHODS = [
    ('postOpenPing', 'rPostOpenPing'),
    ('pollHomeFresh', 'rPollHomeFresh'),
    ('pollHereBase', 'rPollHereBase'),
    ('loadMeta', 'rLoadMeta'),
    ('startHere', 'rStartHere'),
    ('hereFailed', 'rHereFailed'),
    ('pollHere', 'rPollHere'),
    ('applyView', 'rApplyView'),
    ('cycleView', 'rCycleView'),
    ('stepTime', 'rStepTime'),
    ('reload', 'rReload'),
    ('onLoad', 'rOnLoad'),
]
R_FIELDS = [
    ('_hereBaseReady', 'rHereBaseReady'),
    ('_lastFrameSrc', 'rLastFrameSrc'),
    ('_homeTimer', 'rHomeTimer'),
    ('_pollTimer', 'rPollTimer'),
    ('_baseTimer', 'rBaseTimer'),
    ('_pollLeft', 'rPollLeft'),
    ('_baseLeft', 'rBaseLeft'),
    ('_hereReqAt', 'rHereReqAt'),
    ('_hereLat', 'rHereLat'),
    ('_hereLon', 'rHereLon'),
    ('_openAt', 'rOpenAt'),
    ('_paintedVt', 'rPaintedVt'),
    ('_homeReady', 'rHomeReady'),
    ('_hereReady', 'rHereReady'),
    ('_basesAt', 'rBasesAt'),
    ('_frames', 'rFrames'),
    ('_fIdx', 'rFIdx'),
    ('_view', 'rView'),
    ('_modes', 'rModes'),
    ('_mode', 'rMode'),
    ('_base', 'rBase'),
    ('_token', 'rToken'),
    ('pollMs', 'rPollMs'),
]

r = script_body(R_IN)
r_pre, r_obj = r.split('export default {', 1)
r_obj = re.sub(r'  data: \{.*?\n  \},\n(?=  _base:)', '', r_obj, flags=re.S)
# Truncate at fireTap: it and onKeyUp belong to the shell.
r_obj = r_obj[:r_obj.index('\n  fireTap() {')]
r_obj = rename(r_obj, R_METHODS + R_FIELDS)
# setData reroutes -> display buffers + rChanged.
r_obj = re.sub(r"this\.setData\(\{ hint: (.+?) \}\);",
               r"this.rHintText = \1; this.rChanged();", r_obj)
r_obj = must_replace(r_obj,
    "    this.setData({ status: '再読込中…', hint: 'もう一度バック: 終了' });",
    "    this.rStatusText = '再読込中…'; this.rHintText = 'もう一度バック: 終了'; this.rChanged();")
r_obj = must_replace(r_obj,
    "        this.setData({ status: v.label + '（更新中…）' });",
    "        this.rStatusText = v.label + '（更新中…）';\n        this.rChanged();")
r_obj = must_replace(r_obj,
    "      this.setData({\n"
    "        imgSrc: this.rBase + 'base_' + v.key + '.png' + bust,\n"
    "        status: v.label + ' の地図（作成中…）'\n"
    "      });",
    "      this.rImgSrc = this.rBase + 'base_' + v.key + '.png' + bust;\n"
    "      this.rStatusText = v.label + ' の地図（作成中…）';\n"
    "      this.rChanged();")
r_obj = must_replace(r_obj,
    "    this.setData({\n"
    "      imgSrc: src,\n"
    "      status: v.label + '  ' + (f.off ? ('+' + f.off + '分予測 ' + f.display) : (f.display + ' の雨雲'))\n"
    "    });",
    "    this.rImgSrc = src;\n"
    "    this.rStatusText = v.label + '  ' + (f.off ? ('+' + f.off + '分予測 ' + f.display) : (f.display + ' の雨雲'));\n"
    "    this.rChanged();")
r_obj = must_replace(r_obj,
    "    if (this._tapTimer) { clearTimeout(this._tapTimer); this._tapTimer = null; }",
    "    this.clearTapArm();")
# Track the last radar request time for the mode-entry refresh,
# and keep the radar view when a here re-request lands again.
r_obj = r_obj.replace(
    "    this.rOpenAt = Math.floor(Date.now() / 1000);",
    "    this.rOpenAt = Math.floor(Date.now() / 1000);\n    this.rLastReqAtS = this.rOpenAt;")
r_obj = r_obj.replace(
    "            this.rMode = 'here';\n            this.rView = 0;",
    "            const wasHere = this.rMode === 'here';\n"
    "            this.rMode = 'here';\n"
    "            if (!wasHere) this.rView = 0;")
# The comment block above fireTap trails stepTime; trim back to
# the last member's closing comma.
_rlines = r_obj.rstrip().split('\n')
while _rlines and not _rlines[-1].rstrip().endswith(','):
    _rlines.pop()
r_members = '\n'.join(_rlines)
assert r_members.endswith(','), 'radar members should end with a comma'
for _f in ("  _tapTimer: null,\n", "  _tapLockUntil: 0,\n",
           "  _lastReloadAt: 0,\n", "  _lastInteractAt: 0,\n"):
    assert _f in r_members, 'radar field initializer missing: ' + _f
    r_members = r_members.replace(_f, "")
r_comment = r_pre.rstrip()

print('zaisen members:', len(z_members), 'chars; radar members:', len(r_members))

# ---------------------------------------------------------------- shell
HEADER = """// odekake (おでかけ): zaisen + rain radar in one agent, for
// going-out checks (user request 2026-11-17). Three display
// modes, switched by a tap followed within 3 s by a swipe:
//   combo  (default): zaisen 'single' lines on top, the radar
//          wide view below (home/here auto-switch as in radar);
//          overflow scrolls with swipes. Tap cycles the radar
//          forecast 現在 -> +5 -> +10 -> +30 (no +60 here);
//          BACK reloads both.
//   zaisen: the zaisen agent (zai-b40) as-is.
//   radar:  the radar agent (rdr-b12) as-is.
// A tap applies its mode-local action at once; if a swipe
// follows within 3 s, the tap's effect is reverted and the
// swipe switches the odekake mode instead (down = next,
// up = previous, wrapping combo -> zaisen -> radar -> combo).
// The mode switched TO keeps its previous display state.
// BACK follows the zai-b40 / rdr-b12 rule in every mode: a
// press within 3 s of the last reload or of the last tap/swipe
// passes through (exit); otherwise it reloads the current
// mode (both engines in combo).
// ASSEMBLED by tools/merge.py from aiui-zaisen (zai-b40) and
// aiui-radar (rdr-b12): engine identifiers are prefixed (z*/r*)
// and their setData calls write display buffers that
// syncDisplay() composes per mode. Port fixes by editing the
// source agent and re-running the merge script.
// odk-b1: first build.
"""

SHELL_FIELDS = """  data: {
    build: 'odk-b1',
    head: 'おでかけ 読込中…',
    L0: '', L1: '', L2: '', L3: '', L4: '', L5: '', L6: '', L7: '',
    L8: '', L9: '', L10: '', L11: '', L12: '', L13: '',
    foot: '',
    status: '読込中…',
    hint: '',
    imgSrc: ''
  },
  // ---- odekake shell state ----
  _oMode: 'combo',
  _tapTimer: null,
  _tapLockUntil: 0,
  _lastTapAt: 0,
  _tapSnap: null,
  _lastReloadAt: 0,
  _lastInteractAt: 0,
  cFIdx: 0,
  rLastReqAtS: 0,
  // ---- display buffers (engines write, syncDisplay reads) ----
  zCenter: 4,
  zHeadText: '在線 読込中...',
  zFootText: '',
  zClockText: '--:--',
  zLines: [],
  rStatusText: '読込中…',
  rHintText: 'タップ: 切替 / スワイプ: 時刻 / バック: 再読込',
  rImgSrc: '',
  rComboStatusText: '読込中…',
  rComboImgSrc: '',
  rComboLastSrc: '',
"""

SHELL_METHODS = """  // ---- odekake shell ----
  onLoad() {
    this.zOnLoad();
    this.rOnLoad();
    this.syncDisplay();
  },
  onUnload() {
    this.zOnUnload();
    this.rStopTimers();
    this.clearTapArm();
  },
  rStopTimers() {
    if (this.rHomeTimer) { clearTimeout(this.rHomeTimer); this.rHomeTimer = null; }
    if (this.rPollTimer) { clearTimeout(this.rPollTimer); this.rPollTimer = null; }
    if (this.rBaseTimer) { clearTimeout(this.rBaseTimer); this.rBaseTimer = null; }
  },
  clearTapArm() {
    if (this._tapTimer) { clearTimeout(this._tapTimer); this._tapTimer = null; }
  },
  // Compose the visible fields for the current odekake mode
  // from the engine buffers. Layout is one column: head,
  // zaisen lines, foot, radar status, hint, radar image. In
  // zaisen mode the radar slots are '' and sit below the fold;
  // in radar mode the zaisen slots are '' above the image.
  syncDisplay() {
    const patch = { head: '', status: '', hint: '', imgSrc: '', foot: '' };
    for (let k = 0; k < 14; k++) patch['L' + k] = '';
    if (this._oMode === 'zaisen') {
      patch.head = this.zHeadText;
      for (let k = 0; k < 14; k++) patch['L' + k] = this.zLines[k] || '';
      patch.foot = [this.zClockText, this.zFootText, this.data.build].filter(Boolean).join(' ');
    } else if (this._oMode === 'radar') {
      patch.head = 'Radar ' + this.data.build;
      patch.status = this.rStatusText;
      patch.hint = this.rHintText;
      patch.imgSrc = this.rImgSrc;
    } else {
      patch.head = this.zHeadText;
      const rs = this.zRenderSingle(this.zParsedTrains());
      for (let k = 0; k < 14; k++) patch['L' + k] = rs.lines[k] || '';
      patch.foot = [this.zClockText, this.zFootText].filter(Boolean).join(' ');
      patch.status = this.rComboStatusText;
      patch.hint = 'タップ: 予測 / タップ→スワイプ: モード切替';
      patch.imgSrc = this.rComboImgSrc;
    }
    this.setData(patch);
  },
  rChanged() {
    this.rComboView();
    this.syncDisplay();
  },
  // Combo radar: the wide view of the current radar mode
  // (home -> 京都駅・広域, here -> 現在地・広域), forecast
  // offsets limited to 0/+5/+10/+30 (user spec: no +60 in
  // combo). Mirrors rApplyView's readiness handling.
  rComboFrames() {
    const list = this.rFrames.filter(f => f.off === 0 || f.off === 5 || f.off === 10 || f.off === 30);
    return list.length ? list : this.rFrames;
  },
  rComboView() {
    const key = this.rMode === 'home' ? 'wide' : 'widehere';
    const label = this.rMode === 'home' ? '京都駅・広域' : '現在地・広域';
    const frames = this.rComboFrames();
    if (this.cFIdx >= frames.length) this.cFIdx = frames.length - 1;
    if (this.cFIdx < 0) this.cFIdx = 0;
    const f = frames[this.cFIdx] || frames[0] || { off: 0, vt: '', display: '' };
    const ready = this.rMode === 'home' ? this.rHomeReady : this.rHereReady;
    if (!ready) {
      if (this.rComboLastSrc) {
        this.rComboStatusText = label + '（更新中…）';
        return;
      }
      const bust = this.rMode === 'here' && this.rBasesAt ? ('?v=' + this.rBasesAt) : '';
      this.rComboImgSrc = this.rBase + 'base_' + key + '.png' + bust;
      this.rComboStatusText = label + ' の地図（作成中…）';
      return;
    }
    const suffix = f.off ? ('_p' + f.off) : '';
    const q = f.vt ? ('?v=' + f.vt) : '';
    const src = this.rBase + key + suffix + '.png' + q;
    this.rComboLastSrc = src;
    this.rComboImgSrc = src;
    this.rComboStatusText = label + '  ' + (f.off ? ('+' + f.off + '分予測 ' + f.display) : (f.display + ' の雨雲'));
  },
  // One physical tap, detected as in radar (GlobalHook arm +
  // Enter confirm, 700 ms lockout). The tap applies its
  // mode-local action immediately and snapshots the pre-tap
  // state; a swipe within 3 s reverts it (see onKeyUp).
  fireTap() {
    this._tapLockUntil = Date.now() + 700;
    this._lastInteractAt = Date.now();
    this._lastTapAt = Date.now();
    if (this._oMode === 'combo') {
      this._tapSnap = { kind: 'combo', cf: this.cFIdx };
      const n = this.rComboFrames().length;
      if (n > 0) this.cFIdx = (this.cFIdx + 1) % n;
      this.rComboView();
    } else if (this._oMode === 'zaisen') {
      this._tapSnap = { kind: 'zaisen', zm: this.zMode };
      this.zMode = this.zMode === 'single' ? 'focus' : this.zMode === 'focus' ? 'omit' : this.zMode === 'omit' ? 'all' : 'single';
      this.zApplyHead();
      this.zRender();
    } else {
      this._tapSnap = { kind: 'radar', rv: this.rView };
      this.rCycleView();
    }
    this.syncDisplay();
  },
  revertTap() {
    const s = this._tapSnap;
    if (!s) return;
    this._tapSnap = null;
    if (s.kind === 'combo') {
      this.cFIdx = s.cf;
      this.rComboView();
    } else if (s.kind === 'zaisen') {
      this.zMode = s.zm;
      this.zApplyHead();
      this.zRender();
    } else {
      this.rView = s.rv;
      this.rApplyView();
    }
  },
  switchMode(dir) {
    const order = ['combo', 'zaisen', 'radar'];
    let i = order.indexOf(this._oMode);
    i = (i + dir + order.length) % order.length;
    this._oMode = order[i];
    this.enterMode();
    this.syncDisplay();
  },
  // On entering a mode, refresh whichever engine went stale
  // while it was off-screen (mirrors each agent's open-time
  // behaviour without resetting its display state).
  enterMode() {
    if (this._oMode !== 'radar') this.zEnsureFresh();
    if (this._oMode !== 'zaisen') this.rEnsureFresh();
    if (this._oMode === 'radar') this.rApplyView();
    if (this._oMode === 'combo') this.rComboView();
  },
  zEnsureFresh() {
    if (!this.zAutoActive()) {
      this.zStartAutoReload();
      this.zFetchData();
    }
  },
  rEnsureFresh() {
    const nowS = Math.floor(Date.now() / 1000);
    if (nowS - this.rLastReqAtS < 600) return;
    this.rLastReqAtS = nowS;
    this.rPostOpenPing();
    if (!this.rHomeReady) this.rPollHomeFresh();
    if (this.rHereLat != null && this.rHereLon != null) {
      this.rHereReqAt = nowS;
      try {
        wx.request({
          url: this.rBase + 'request',
          method: 'POST',
          header: { 'X-Talk-Token': this.rToken, 'content-type': 'application/json' },
          data: { lat: this.rHereLat, lon: this.rHereLon },
          success: () => {},
          fail: () => {}
        });
      } catch (e) {}
      this.rHereReady = false;
      this.rPollLeft = 40;
      this.rBaseLeft = 40;
      this.rPollHereBase();
      this.rPollHere();
    }
  },
  onKeyUp(event) {
    const code = event && event.code;
    const kc = event && (typeof event.keyCode === 'number' ? event.keyCode
      : (typeof event.which === 'number' ? event.which : -1));
    // BACK: reload the current mode (both engines in combo).
    // A press within 3 s of the last reload, tap or swipe is
    // left unconsumed so the OS exit sequence can proceed
    // (zai-b40 / rdr-b12 rule, confirmed for odekake).
    if (code === 'Backspace' || code === 'Escape' || code === 'BrowserBack'
        || code === 'Back' || code === 'GoBack' || kc === 4 || kc === 27) {
      if (Date.now() - this._lastReloadAt < 3000
          || Date.now() - this._lastInteractAt < 3000) return;
      event.preventDefault();
      this._lastReloadAt = Date.now();
      this._tapSnap = null;
      if (this._oMode === 'combo') {
        this.zStartAutoReload();
        this.zFetchData();
        this.zRender();
        this.rReload();
      } else if (this._oMode === 'zaisen') {
        this.zStartAutoReload();
        this.zFetchData();
        this.zRender();
      } else {
        this.rReload();
      }
      this.syncDisplay();
      return;
    }
    if (code === 'GlobalHook') {
      event.preventDefault();
      if (Date.now() < this._tapLockUntil) return;
      if (this._tapTimer) return;
      this._tapTimer = setTimeout(() => { this._tapTimer = null; this.fireTap(); }, 300);
      return;
    }
    if (code === 'Enter') {
      event.preventDefault();
      if (Date.now() < this._tapLockUntil) return;
      this.clearTapArm();
      this.fireTap();
      return;
    }
    if (code === 'ArrowUp' || code === 'ArrowDown') {
      const down = code === 'ArrowDown';
      // Mode switch: a swipe within 3 s of a tap reverts the
      // tap and switches the odekake mode (down = next,
      // up = previous, wrapping).
      if (this._tapSnap && Date.now() - this._lastTapAt <= 3000) {
        event.preventDefault();
        this.clearTapArm();
        this._lastInteractAt = Date.now();
        this.revertTap();
        this.switchMode(down ? 1 : -1);
        return;
      }
      this._lastInteractAt = Date.now();
      this.clearTapArm();
      if (this._oMode === 'combo') return; // unconsumed: native scroll
      event.preventDefault();
      if (this._oMode === 'zaisen') this.zMove(down ? 1 : -1);
      else this.rStepTime(down ? -1 : 1);
      this.syncDisplay();
    }
  }
"""

TEMPLATE = """<page>
  <view class="container">
    <text class="head">{{ head }}</text>
    <text class="line">{{ L0 }}</text>
    <text class="line">{{ L1 }}</text>
    <text class="line">{{ L2 }}</text>
    <text class="line">{{ L3 }}</text>
    <text class="line">{{ L4 }}</text>
    <text class="line">{{ L5 }}</text>
    <text class="line">{{ L6 }}</text>
    <text class="line">{{ L7 }}</text>
    <text class="line">{{ L8 }}</text>
    <text class="line">{{ L9 }}</text>
    <text class="line">{{ L10 }}</text>
    <text class="line">{{ L11 }}</text>
    <text class="line">{{ L12 }}</text>
    <text class="line">{{ L13 }}</text>
    <text class="foot">{{ foot }}</text>
    <text class="sub">{{ status }}</text>
    <text class="hint">{{ hint }}</text>
    <image class="radar" src="{{ imgSrc }}"></image>
  </view>
</page>

<style>
.container {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: flex-start;
  height: 100vh;
  padding: 6px;
}

.head {
  color: #40FF5E;
  font-size: 17px;
  line-height: 19px;
  margin-bottom: 3px;
}

.line {
  color: #40FF5E;
  font-size: 19px;
  line-height: 20px;
}

.foot {
  color: #40FF5E99;
  font-size: 15px;
  line-height: 17px;
  margin-top: 3px;
}

.sub {
  color: #40FF5E99;
  font-size: 18px;
  line-height: 22px;
}

.hint {
  color: #40FF5E99;
  font-size: 13px;
  line-height: 16px;
}

.radar {
  width: 448px;
  height: 286px;
  margin: 4px 0;
}
</style>
"""

out = []
out.append('<script def>\n{\n  "navigationBarTitleText": "Odekake"\n}\n</script>\n')
out.append('<script setup>\n')
out.append(HEADER)
out.append(z_consts)
out.append('export default {\n')
out.append(SHELL_FIELDS)
out.append(z_members + '\n')
out.append('  // ---- radar engine (rdr-b12, prefixed r*) ----\n')
out.append(r_comment + '\n')
out.append(r_members + '\n')
out.append(SHELL_METHODS)
out.append('}\n</script>\n\n')
out.append(TEMPLATE)
open(OUT, 'w', encoding='utf-8').write(''.join(out))
print('wrote', OUT)
