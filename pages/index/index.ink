<script def>
{
  "navigationBarTitleText": "Odekake"
}
</script>
<script setup>
// odekake (おでかけ): zaisen + rain radar in one agent, for
// going-out checks (user request 2026-11-17). Three display
// modes, switched by a tap followed within 3 s by a swipe:
//   combo  (default): zaisen 'single' lines on top, the radar
//          wide view below (home/here auto-switch as in radar);
//          overflow scrolls with swipes (the shell steps the
//          scroll-view's scroll-top). Tap cycles the radar
//          forecast 現在 -> +5 -> +10 -> +30 (no +60 here);
//          BACK reloads both.
//   zaisen: the zaisen agent (zai-b41) as-is.
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
// ASSEMBLED by tools/merge.py from aiui-zaisen (zai-b41) and
// aiui-radar (rdr-b12): engine identifiers are prefixed (z*/r*)
// and their setData calls write display buffers that
// syncDisplay() composes per mode. Port fixes by editing the
// source agent and re-running the merge script.
// odk-b1: first build.
// odk-b2: the whole column lives in a <scroll-view> whose
// scroll-top the shell drives (kensho vrf-b32/b33: no page
// scroll APIs exist, and arrow keys never scroll the inner
// view). A mode switch resets the scroll position (radar
// mode scrolls straight to its status/hint/image block).
// The zaisen footer rides in the line flow (zai-b41).
// Keihan Main Line stations, display order = Demachiyanagi (top) to Yodoyabashi.
// Diagram grid: station KHn occupies rows firstRow..firstRow+2,
// firstRow = 1 + (42 - n) * 3  (verified against the official page HTML).
// Row offset inside a station block (verified against live data 2026-10-31):
//   offset 0 = AT that station, offset 1/2 = in the section between that
//   station and the next station toward Yodoyabashi.
// Display rules (zai-b23):
//   - Train position lines show the car count (live carsOfTrain)
//     right after the type for every train, e.g. ↑準急8 出町柳行,
//     so 4/7/8-car trains are all identifiable there.
//   - In the next-departures display, a 4-car train (from the live
//     feed's carsOfTrain; known only while the train is running) is
//     marked with a '.' right after its type kanji, e.g. a 4-car
//     sub-express to Yodoyabashi shows as 準.淀5. Short trains stop
//     at different platform positions, so they are worth spotting
//     at a glance. (zai-b20/b21 tried boxing a kanji with U+20DE
//     COMBINING ENCLOSING SQUARE; on the glasses it rendered as a
//     blank gap — combining enclosing marks do not zRender there.)
//   - Next-departure countdown: a train normally drops off 1 minute
//     after its (delay-adjusted) departure time, showing '-' during
//     that minute. But while fresh live position data says the train
//     has not departed this station yet (still approaching it or
//     stopped at it), it stays listed as '-' past that minute.
//   - No blank lines: stations and trains are packed into a flat line list.
//   - The visible window never starts on a train line: if it would, the
//     window is shifted up to that train's station line.
//   - A train stopped at a station is wrapped in [ ].
//   - A stopped train waiting for a following train to pass it at that
//     station is wrapped in [[ ]] (judged from the official timetable:
//     startTimeList.json joined by wdfBlockNo; a station entry with a real
//     departure time = stop, "99:99" or absent = pass). Only stations with
//     passing facilities can host an overtake (OVERTAKE below); e.g.
//     Kiyomizu-Gojo has no refuge platform, so no [[ ]] there.
// Display rules (zai-b24):
//   - Departure types no longer depend on the live position join
//     alone (startTimeList.json carries no type field, so a train
//     that had not started running showed no type). TYPE_TABLE below
//     is generated from Keihan's official all-trains timetable PDFs:
//     each timetable entry is matched by its stop pattern
//     (dir|dest|stop set over the 42 stations) and annotated with
//     __type when the timetable is fetched. The live feed's type
//     still wins when the train is running (it reflects same-day
//     changes); the table covers everything else, including trains
//     that have not departed yet.
//   - If the table's coverage of the fetched timetable (share of
//     main-line services it can type) drops under 85%, the header
//     gains a "⚠種別表" suffix: the timetable in use no longer
//     matches the table (a diagram revision, most likely) and the
//     table needs regenerating (tools/type-table/).
// zai-b25: the timetable cache is keyed to the service date. The
// timetable file is a per-day operations file (weekday and holiday
// diagrams carry different trains and number assignments), so a
// cache is only reused while the position file's date matches the
// date the cache was fetched for; a new service day refetches once.
// (The old week-long cache let a holiday file drive a Monday
// morning's countdowns on 2026-11-02: the train-number join failed
// across the board and every countdown item lost its type.)
// zai-b26: the "date" in that key is the SERVICE date with a 03:00
// boundary (see zServiceDateStr): the last trains run past midnight
// (the timetable file spans 05:01-24:30, written as 24:xx), so
// between 00:00 and 03:00 the files still carry the previous
// service day even though their timestamps show the new calendar
// date. The same service date also drives the type table's
// weekday/holiday choice.
// zai-b29:
//   - Position-load failures no longer guess "メンテナンス中かも":
//     every failure kind (maintenance HTML, request failure,
//     exception) shows "読込失敗 最終H:MM" with the last successful
//     position file's creation time (hour without leading zero);
//     before the first successful load of the session it is just
//     "読込失敗".
//   - Third display mode: trains stay unfiltered, but stations
//     whose block holds no train are omitted (the centred station
//     always stays, as in focused mode). The Enter cycle (while
//     auto-reload is active) is now focus -> all -> omit -> focus;
//     the agent still starts in focus mode.
// zai-b30: the header tail shows the current display mode as one
// kanji (注 = focus, 全 = all, 省 = omit), before the type-table
// warning: with many trains running, 'all' and 'omit' zRender almost
// identically, so the mode needs to be visible at a glance.
// zai-b31: fourth display mode 'single' (単): only the centred
// station, any trains stopped there, and the single nearest train
// per direction that stops at the centred station (each shown with
// the station line of the block it is running in; a train already
// in the centred station's own section toward Yodoyabashi gets no
// extra station line). 'single' is the startup default, and the
// Enter cycle is single -> focus -> omit -> all -> single.
// zai-b32: walking-safety trim: in 'single' mode the approaching
// trains' station lines show the station name only (no next-train
// countdowns; those stay on the centred station's line), and the
// header font shrinks below the station lines (24px -> 17px, all
// modes) so the header reads as metadata, not content.
// zai-b33: two fixes. (A) Nakanoshima-line trains are placed by
// the position feed on the Kitahama / Yodoyabashi block rows
// (121+) while approaching Temmabashi on the branch; their
// timetables carry no Kitahama, so the stop filter dropped them
// and 'single' showed nothing at Kitahama. They are now
// attributed to Temmabashi's block (see zParsedTrains). (B) The
// timetable fetch now retries (at most once a minute) while it
// is still missing, instead of leaving the whole session
// unfiltered after one failed attempt.
// zai-b35: reload pacing, at the user's request. (A) A reload is
// skipped when the previous reload started less than 10 seconds
// ago (RELOAD_GUARD_MS; zFetchData used to carry a 2-second guard).
// (B) After a position-load failure, one extra reload is
// scheduled 30 seconds later (RETRY_MS) instead of waiting for
// the next 90-second tick; the retry chains while loads keep
// failing and is cancelled by the next success.
// zai-b36: a stopped train is also shown as an overtake wait
// ([[...]]) when another train in the same direction has an
// earlier countdown at that station (zIsCountdownOvertake) — e.g.
// a semi-express held at Sanjo while an express behind it is due
// to leave Sanjo sooner. Covers overtakers that stop at the
// station, which the passing-train check cannot see.
// zai-b39: tap must refresh the header too. b38's Enter branch
// called zRender() only, but the mode tail (単/注/省/全) lives in
// the header, which only zApplyHead() rebuilds — so after a tap
// the header kept showing the previous mode. Enter now calls
// zApplyHead() before zRender(), like the 10 s clock tick does.
// zai-b38: tap/back split, at the user's request (2026-11-14,
// once the radar work proved BACK reaches the page and can be
// consumed). Until b37 a tap (Enter) did everything at once:
// while auto-reload was active it reloaded, reset the window
// AND cycled the display mode; while inactive it reloaded
// only. Now: Enter cycles the display mode ONLY (no reload,
// no window reset), and BACK is the reload key — refetch +
// restart the auto-reload window, mode untouched. A second
// BACK within 3 s is left unconsumed so the OS exit sequence
// still works (the radar rdr-b9 pattern).
// zai-b37: the service-date boundary moves from 03:00 to 05:00.
// A week of overnight probing (2026-11-02..11-10) found Keihan's
// served files actually flip to the new service day at
// 04:20-04:35, about 1.5 hours after the old boundary, so between
// 03:00 and the flip the cache key and day type were judged on
// the new calendar day while the files still carried the previous
// service day. 05:00 sits after every observed flip and just
// before the first departure (05:01), so the only misjudged
// window left is the few minutes between the flip and 05:00,
// when nothing is running yet.
const STATIONS = [
  ['出町柳', 42], ['神宮丸太町', 41], ['三条', 40], ['祇園四条', 39],
  ['清水五条', 38], ['七条', 37], ['東福寺', 36], ['鳥羽街道', 35],
  ['伏見稲荷', 34], ['龍谷大前深草', 33], ['藤森', 32], ['墨染', 31],
  ['丹波橋', 30], ['伏見桃山', 29], ['中書島', 28], ['淀', 27],
  ['石清水八幡宮', 26], ['橋本', 25], ['樟葉', 24], ['牧野', 23],
  ['御殿山', 22], ['枚方市', 21], ['枚方公園', 20], ['光善寺', 19],
  ['香里園', 18], ['寝屋川市', 17], ['萱島', 16], ['大和田', 15],
  ['古川橋', 14], ['門真市', 13], ['西三荘', 12], ['守口市', 11],
  ['土居', 10], ['滝井', 9], ['千林', 8], ['森小路', 7],
  ['関目', 6], ['野江', 5], ['京橋', 4], ['天満橋', 3],
  ['北浜', 2], ['淀屋橋', 1]
];
// Station coordinates (WGS84), aligned with STATIONS. Source: OpenStreetMap.
const COORDS = [
  [35.03027, 135.77268], [35.01867, 135.77224], [35.00902, 135.77233],
  [35.00323, 135.77193], [34.99561, 135.76845], [34.98907, 135.76791],
  [34.98126, 135.77002], [34.97349, 135.77004], [34.96889, 135.76926],
  [34.96436, 135.77010], [34.95681, 135.77021], [34.94803, 135.76902],
  [34.93891, 135.76540], [34.93281, 135.76437], [34.92672, 135.76017],
  [34.90651, 135.72118], [34.88463, 135.70007], [34.88175, 135.68404],
  [34.86195, 135.67536], [34.84385, 135.66559], [34.82917, 135.65395],
  [34.81614, 135.64872], [34.81140, 135.63939], [34.79787, 135.63020],
  [34.78476, 135.63099], [34.76407, 135.62084], [34.74735, 135.61083],
  [34.74301, 135.60286], [34.74007, 135.59166], [34.73806, 135.58291],
  [34.73734, 135.57566], [34.73530, 135.56520], [34.73071, 135.55992],
  [34.72761, 135.55727], [34.72431, 135.55501], [34.71938, 135.55163],
  [34.71250, 135.54693], [34.70712, 135.54326], [34.69699, 135.53217],
  [34.69033, 135.51642], [34.69150, 135.50758], [34.69250, 135.50129]
];
// Stations where a stopped train can be overtaken (refuge/passing
// facilities). 'up' = up direction only (Iwashimizu-Hachimangu).
const OVERTAKE = {
  '三条': 'both', '龍谷大前深草': 'both', '丹波橋': 'both', '淀': 'both',
  '樟葉': 'both', '枚方市': 'both', '香里園': 'both', '萱島': 'both',
  '守口市': 'both', '京橋': 'both', '石清水八幡宮': 'up'
};
const URL_POS = 'https://www.keihan.co.jp/zaisen-up/trainPositionList.json';
const URL_TT = 'https://www.keihan.co.jp/zaisen-up/startTimeList.json';
// Auto-reload runs every 90 seconds for 10 minutes. The official JSON is
// regenerated roughly once a minute (measured gaps of 60-71 s, not
// published), so 90 s stays clear of hammering it while missing little.
const RELOAD_MS = 90 * 1000;
const RETRY_MS = 30 * 1000;
const RELOAD_GUARD_MS = 10 * 1000;
const RELOAD_WINDOW_MS = 10 * 60 * 1000;
const RELOAD_MARKS = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩'];
// Abbreviations for the next-trains display on each station line,
// grouped by direction (zai-b27), e.g. "清水五条↑準出1:準出3↓急淀3:準中8"
// (toward Demachiyanagi: semi-expresses in 1 and 3 min; the other way:
// an express for Yodoyabashi in 3 min, a semi-express in 8 min).
const TYPE_AB = {
  '普通': '普', '準急': '準', '急行': '急', '特急': '特',
  '快速急行': '快', '区間急行': '区', '通勤準急': '通',
  '通勤快急': '通', '快速特急': '快', 'ライナー': 'ラ'
};
const DEST_AB = {
  '淀屋橋': '屋', '出町柳': '出', '中之島': '中', '樟葉': '樟',
  '枚方市': '枚', '三条': '三', '丹波橋': '丹', '中書島': '書',
  '宇治': '宇', '私市': '私', '交野市': '交', '寝屋川市': '寝',
  '萱島': '萱', '守口市': '守', '京橋': '京', '天満橋': '天',
  '淀': '淀', '石清水八幡宮': '八', '伏見桃山': '桃', '墨染': '墨',
  '藤森': '藤', '龍谷大前深草': '龍', '伏見稲荷': '稲',
  '東福寺': '東', '七条': '七', '清水五条': '清', '祇園四条': '祇',
  '神宮丸太町': '神'
};
// Train-type table (zai-b24), generated from Keihan's official
// all-trains timetable PDFs (tools/type-table/build_table.py).
// W/H map "dir|dest|stopPattern" to a type abbreviation for the
// weekday / holiday diagrams; T disambiguates the few stop patterns
// shared by two types (Liner vs Limited Express, whose stop sets are
// identical) by Kitahama departure time ("H:MM", no leading zero).
const TYPE_TABLE = {"W":{"up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSS.......................................":"普","up|出町柳|SSSSSSSSSSSSSSSS..........................":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","up|出町柳|SSSSSS..S...S.SS..........................":"急","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS................":"急","up|樟葉|..................SSSSSSSSSSSSSSSSSSSSSSSS":"普","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","up|萱島|..........................SSSSSSSSSSSSSS..":"普","up|樟葉|..................SSSSSSSSSSSSSS......SSSS":"区","up|出町柳|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","up|枚方市|.....................SSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSSSSSSSSSSSSSSSSSS.......................":"普","up|樟葉|..................SSSSSSSSSSSSSSSSSSSSSS..":"普","up|樟葉|..................SSSSSSSSS....S......SSSS":"準","up|香里園|........................SSSSSSSS......SS..":"区","up|萱島|..........................SSSSSSSSSSSSSSSS":"普","up|枚方市|.....................SSSSSS....S......SSSS":"準","up|萱島|..........................SSSSSS......SSSS":"区","up|樟葉|..................S..S..SS.....S......SSSS":"快","up|萱島|..........................SSSSSS......SS..":"区","up|枚方市|.....................SSSSSSSSSSS......SSSS":"区","up|枚方市|.....................S..SS.....S......SSSS":"快","up|枚方市|.....................SSSSSSSSSSS......SS..":"区","up|出町柳|S.SS.S................................SSSS":"快","up|淀|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|三条|..SSSSSSSSSSSSSS..........................":"普","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|淀|...............SSSSSSSSSSSS....S......SSSS":"準","up|枚方市|.....................SSSSSS....S......SS..":"準","up|枚方市|.....................SS.SS.....S......SSSS":"急","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SS..":"準","up|枚方市|.....................S..SS.....S......SS..":"快","up|三条|..SS.S......S.S...S..S................SSSS":"特","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|..........................SSSSSSSSSSSSSSSS":"普","down|中之島|..........................SSSSSS......SS..":"区","down|中之島|..........................SSSSSSSSSSSSSS..":"普","down|淀屋橋|..................SSSSSSSSS....S......SSSS":"準","down|淀屋橋|..........................SSSSSS......SSSS":"区","down|淀屋橋|...............SSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|..................SSSSSSSSSSSSSS......SSSS":"区","down|淀屋橋|..................S..SS.SS.....S......SSSS":"急","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀|SSSSSSSSSSSSSSSS..........................":"普","down|三条|SSS.......................................":"普","down|淀屋橋|.....................SSSSSS....S......SSSS":"準","down|淀屋橋|.....................S................SSSS":"特","down|淀屋橋|.....................SSSSSSSSSSSSSSSSSSSSS":"普","down|淀屋橋|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","down|樟葉|SSSSSSSSSSSSSSSSSSS.......................":"普","down|淀屋橋|...............SS.S..SS.SS.....S......SSSS":"急","down|淀屋橋|.....................S..SS............SSSS":"通","down|中之島|.....................SSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|..................SSSSSSSSS...........SSSS":"通","down|淀屋橋|S.SS.S......S.S...S..S..SS............SSSS":"通","down|中之島|.....................SSSSSSSSSSS......SS..":"区","down|淀屋橋|..................SSSSSSSSSSSSSSSSSSSSSSSS":"普","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSS...........SSSS":"通","down|淀屋橋|.....................SSSSSS...........SSSS":"通","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","down|中之島|.....................SSSSSS...........SS..":"通","down|中之島|S.SS.S......S.S...S..S..SS............SS..":"通","down|中之島|..................SSSSSSSSS....S......SS..":"準","down|淀屋橋|.....................SSSSSSSSSSS......SSSS":"区","down|淀屋橋|..................S..S..SS.....S......SSSS":"快","down|淀屋橋|.....................S..SS.....S......SSSS":"快","down|中之島|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","down|淀屋橋|..................S..S................SSSS":"特","down|中之島|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|枚方市|SSSSSSSSSSSSSSSSSSSSSS....................":"普","down|中之島|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SS..":"準","down|樟葉|..SSSSSSSSSSSSSSSSS.......................":"普","down|枚方市|SSSSSS..S...S.S.S.S..S....................":"急","down|中之島|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SS..":"準","down|中之島|..................S..S..SS.....S......SS..":"快","down|淀屋橋|S.SS.S................................SSSS":"快","down|樟葉|SSSSSS..S...S.S.S.S.......................":"急","down|中之島|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|淀|SSSSSS..S...S.SS..........................":"急","down|淀|..SSSS..S...S.SS..........................":"急","down|守口市|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..........":"普","down|寝屋川市|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","down|寝屋川市|SSSSSS..S...S.S.S.S..SS.SS................":"急"},"H":{"up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSS.......................................":"普","up|出町柳|SSSSSSSSSSSSSSSS..........................":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","up|出町柳|SSSSSS..S...S.SS..........................":"急","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS................":"急","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","up|萱島|..........................SSSSSS......SSSS":"区","up|萱島|..........................SSSSSSSSSSSSSS..":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","up|樟葉|..................S..SS.SS.....S......SSSS":"急","up|枚方市|.....................S..SS.....S......SSSS":"快","up|萱島|..........................SSSSSS......SS..":"区","up|出町柳|S.SS.S................................SSSS":"快","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","up|淀|...............SS.S..SS.SS.....S......SSSS":"急","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","up|樟葉|..................SSSSSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSSSSSSSSSSSSSSSSSS.......................":"普","up|樟葉|..................S..S..SS.....S......SSSS":"快","up|樟葉|..................SSSSSSSSS....S......SSSS":"準","up|樟葉|..................SSSSSSSSSSSSSS......SSSS":"区","up|出町柳|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","up|枚方市|.....................SSSSSS....S......SSSS":"準","up|淀|...............SSSSSSSSSSSS....S......SSSS":"準","up|萱島|..........................SSSSSSSSSSSSSSSS":"普","up|淀|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|三条|..SS.S......S.S...S..S................SSSS":"特","up|枚方市|.....................SSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|..........................SSSSSSSSSSSSSSSS":"普","down|中之島|..........................SSSSSS......SS..":"区","down|中之島|..........................SSSSSSSSSSSSSS..":"普","down|淀屋橋|..................SSSSSSSSS....S......SSSS":"準","down|淀屋橋|..........................SSSSSS......SSSS":"区","down|淀屋橋|...............SSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|.....................SSSSSS....S......SSSS":"準","down|中之島|..................SSSSSSSSSSSSSSSSSSSSSS..":"普","down|中之島|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|三条|SSS.......................................":"普","down|淀屋橋|...............SS.S..SS.SS.....S......SSSS":"急","down|中之島|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","down|中之島|..................SSSSSSSSSSSSSS......SS..":"区","down|淀屋橋|..................S..S..SS.....S......SSSS":"快","down|中之島|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|中之島|..................S..S..SS.....S......SS..":"快","down|淀屋橋|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","down|中之島|.....................SSSSSSSSSSSSSSSSSSS..":"普","down|淀|SSSSSSSSSSSSSSSS..........................":"普","down|中之島|.....................SSSSSSSSSSS......SS..":"区","down|淀屋橋|.....................S..SS.....S......SSSS":"快","down|淀|..SSSSSSSSSSSSSS..........................":"普","down|樟葉|..SSSSSSSSSSSSSSSSS.......................":"普","down|淀屋橋|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|S.SS.S................................SSSS":"快","down|淀|SSSSSS..S...S.SS..........................":"急","down|守口市|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..........":"普","down|寝屋川市|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","down|寝屋川市|SSSSSS..S...S.S.S.S..SS.SS................":"急"},"T":{"down|淀屋橋|..................S..S..SS............SSSS":{"7:20":"ラ","7:31":"ラ","7:56":"通","8:12":"通","8:22":"ラ","8:32":"通","8:52":"ラ"},"down|淀屋橋|S.SS.S......S.S...S..S................SSSS":{"7:00":"特","7:13":"特","7:23":"特","7:37":"特","7:50":"特","8:02":"特","8:15":"特","8:28":"特","8:35":"特","8:41":"ラ","8:47":"特","8:55":"特","9:06":"特","9:15":"特","9:25":"特","9:34":"特","9:53":"特","10:11":"特","10:29":"特","10:42":"特","10:53":"特","11:05":"特","11:17":"特","11:29":"特","11:41":"特","11:53":"特","12:05":"特","12:17":"特","12:29":"特","12:41":"特","12:53":"特","13:05":"特","13:17":"特","13:29":"特","13:41":"特","13:53":"特","14:05":"特","14:17":"特","14:29":"特","14:41":"特","14:53":"特","15:05":"特","15:17":"特","15:29":"特","15:42":"特","15:54":"特","16:06":"特","16:18":"特","16:29":"特","16:41":"特","16:52":"特","17:04":"特","17:16":"特","17:29":"特","17:39":"特","17:53":"特","18:05":"特","18:17":"特","18:30":"特","18:54":"特","19:05":"ラ","19:07":"特","19:17":"特","19:29":"特","19:41":"特","19:51":"特","20:04":"特","20:14":"特","20:27":"特","20:40":"特","20:51":"特","21:03":"特","21:14":"特","21:27":"特","21:39":"特","21:51":"特","22:04":"特","22:18":"特","22:30":"特","22:43":"特","22:56":"特","23:14":"特","23:31":"特","7:01":"特","7:35":"特","7:48":"特","8:40":"特","8:51":"特","9:02":"特","9:16":"特","9:26":"特","9:39":"特","10:05":"特","10:16":"特","10:27":"特","10:40":"特","10:54":"特","13:28":"特","15:41":"特","15:53":"特","16:05":"特","16:17":"特","16:40":"特","16:51":"特","17:05":"特","17:28":"特","17:42":"特","18:04":"特","18:16":"特","18:41":"特","18:52":"特","19:06":"特","19:28":"特","19:54":"特","20:06":"特","20:17":"特","20:30":"特","20:53":"特","21:07":"特","21:21":"特","21:37":"特","21:52":"特","22:07":"特","22:23":"特","22:38":"特","22:54":"特","23:12":"特","23:30":"特","23:49":"特"},"down|淀屋橋|..SS.S......S.S...S..S................SSSS":{"6:29":"特","7:59":"ラ"},"up|出町柳|S.SS.S......S.S...S..S................SSSS":{"6:09":"特","6:39":"特","6:51":"特","7:01":"特","7:14":"特","7:22":"特","7:29":"特","7:39":"特","7:49":"特","7:58":"特","8:06":"特","8:21":"特","8:34":"特","8:48":"特","9:02":"特","9:24":"特","9:35":"特","9:46":"特","10:01":"特","10:12":"特","10:24":"特","10:37":"特","10:49":"特","11:01":"特","11:13":"特","11:25":"特","11:37":"特","11:49":"特","12:01":"特","12:13":"特","12:25":"特","12:37":"特","12:49":"特","13:01":"特","13:13":"特","13:25":"特","13:37":"特","13:49":"特","14:01":"特","14:13":"特","14:25":"特","14:37":"特","14:49":"特","15:01":"特","15:13":"特","15:25":"特","15:37":"特","15:49":"特","16:02":"特","16:13":"特","16:25":"特","16:37":"特","16:49":"特","17:02":"特","17:13":"特","17:24":"特","17:35":"特","17:37":"ラ","17:48":"特","17:59":"特","18:02":"ラ","18:15":"特","18:27":"特","18:36":"特","18:49":"特","19:01":"特","19:03":"ラ","19:14":"特","19:23":"特","19:26":"ラ","19:38":"特","19:51":"特","20:15":"特","20:27":"特","20:38":"特","21:03":"特","21:15":"特","21:27":"特","21:39":"特","21:51":"特","22:03":"特","22:16":"特","22:31":"特","22:52":"特","23:11":"特","6:16":"特","6:30":"特","6:46":"特","7:02":"特","7:13":"特","7:24":"特","7:36":"特","8:03":"特","8:14":"特","8:26":"特","8:38":"特","8:50":"特","9:03":"特","9:14":"特","9:25":"特","9:37":"特","9:49":"特","10:03":"特","10:14":"特","10:26":"特","10:38":"特","11:03":"特","16:01":"特","17:01":"特","17:14":"特","17:25":"特","17:38":"特","17:50":"特","18:01":"特","18:13":"特","18:25":"特","19:25":"特","19:37":"特","19:49":"特","20:16":"特","20:31":"特","21:02":"特","21:16":"特","21:31":"特","21:46":"特","22:01":"特"}},"meta":{"diagram":"2026-08-24","source":"keihan time01-1..4.pdf"}};
const STATION_IDX = {};
for (let si = 0; si < STATIONS.length; si++) STATION_IDX[STATIONS[si][0]] = si;

export default {
  data: {
    build: 'odk-b8',
    head: 'おでかけ 読込中…',
    L0: '', L1: '', L2: '', L3: '', L4: '', L5: '', L6: '', L7: '',
    L8: '', L9: '', L10: '', L11: '', L12: '', L13: '',
    L0c: 'line', L1c: 'line', L2c: 'line', L3c: 'line',
    L4c: 'line', L5c: 'line', L6c: 'line', L7c: 'line',
    L8c: 'line', L9c: 'line', L10c: 'line', L11c: 'line',
    L12c: 'line', L13c: 'line',
    foot: '',
    footc: 'foot',
    status: '読込中…',
    hint: '',
    imgSrc: '',
    svTop: 0
  },
  // ---- odekake shell state ----
  _oMode: 'combo',
  _tapTimer: null,
  _tapLockUntil: 0,
  _lastTapAt: 0,
  _tapSnap: null,
  _lastReloadAt: 0,
  _lastInteractAt: 0,
  // Scroll position of the page's <scroll-view>. syncDisplay
  // echoes it into data.svTop on every compose; only a mode
  // switch or a combo swipe changes it. RADAR_TOP is the
  // offset of the radar block (status element) inside the
  // column. Since odk-b8 the '' line slots collapse (bound
  // 'gone' class), so the block sits right below the head:
  // 19+3 = 22.
  svTopVal: 0,
  RADAR_TOP: 22,
  cFIdx: 0,
  rLastReqAtS: 0,
  // ---- display buffers (engines write, syncDisplay reads) ----
  zCenter: 4,
  zHeadText: '在線 読込中...',
  zFootText: '',
  zClockText: '--:--',
  zLines: [],
  zFootLine: '',
  rStatusText: '読込中…',
  rHintText: 'タップ: 切替 / スワイプ: 時刻 / バック: 再読込',
  rImgSrc: '',
  rComboStatusText: '読込中…',
  rComboImgSrc: '',
  rComboLastSrc: '',

  zTrains: [],
  zTt: null,
  zTtLastTry: 0,
  zLastFetch: 0,
  zPosAt: 0,
  zHeadBase: '在線 読込中...',
  zReloadUntil: 0,
  zReloadTimer: null,
  zRetryTimer: null,
  zClockTimer: null,
  zDelay: {},
  zPosByWdf: {},
  // Display mode: 'single' (centred station + nearest stopping
  // train per direction), 'focus' (trains stopping at the centred
  // station only), 'omit' (unfiltered, empty stations hidden), or
  // 'all'. The agent starts in single mode; Enter cycles
  // single -> focus -> omit -> all -> single (see onKeyUp).
  zMode: 'single',
  zLastOkHm: '',
  zNowMin: -1,
  zElapsedSec: 0,
  zOnLoad() {
    this.zProbeLocation();
    this.zStartAutoReload();
    this.zFetchData();
    // Recompute the "minutes left" displays every 10 seconds (no fetch).
    // The tick count also advances the anchored display clock.
    if (typeof setInterval !== 'undefined') {
      this.zClockTimer = setInterval(() => {
        this.zElapsedSec += 10;
        this.zApplyHead();
        this.zRender();
      }, 10000);
    }
  },
  zOnUnload() {
    this.zStopAutoReload();
    if (this.zClockTimer != null && typeof clearInterval !== 'undefined') {
      clearInterval(this.zClockTimer);
    }
    this.zClockTimer = null;
  },
  // Auto-reload: refetch positions every 90 seconds for 10 minutes after
  // the page is shown (or after Enter is pressed). While active, the
  // header carries a circled-number countdown of the remaining reload
  // slots (e.g. ⑦ at the start with a 90-second interval).
  zAutoActive() {
    return this.zReloadUntil && Date.now() < this.zReloadUntil;
  },
  zApplyHead() {
    let mark = '';
    if (this.zAutoActive()) {
      let n = Math.ceil((this.zReloadUntil - Date.now()) / RELOAD_MS);
      if (n < 1) n = 1;
      if (n > 10) n = 10;
      mark = RELOAD_MARKS[n - 1];
    }
    const modeMark = this.zMode === 'focus' ? ' 注' : this.zMode === 'omit' ? ' 省' : this.zMode === 'all' ? ' 全' : ' 単';
    this.zHeadText = mark + this.zHeadBase + modeMark + (this.zTypeWarn ? ' ⚠種別表' : '');
    this.zClockText = this.zClockStr();
    this.syncDisplay();
  },
  // Current time (HH:MM) for the footer's left end, from the same
  // anchored clock as the next-trains math.
  zClockStr() {
    const m = Math.floor(this.zNowMinutes());
    const hh = Math.floor(m / 60) % 24;
    const mm = m % 60;
    return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm;
  },
  zStartAutoReload() {
    this.zReloadUntil = Date.now() + RELOAD_WINDOW_MS;
    if (this.zReloadTimer == null && typeof setInterval !== 'undefined') {
      this.zReloadTimer = setInterval(() => this.zOnReloadTick(), RELOAD_MS);
    }
    this.zApplyHead();
  },
  zStopAutoReload() {
    if (this.zReloadTimer != null && typeof clearInterval !== 'undefined') {
      clearInterval(this.zReloadTimer);
    }
    this.zReloadTimer = null;
    this.zClearRetry();
  },
  // (zai-b35) Failure retry: one extra reload RETRY_MS after a
  // failed load. The retry chains while loads keep failing (each
  // failure schedules the next one) and is cancelled by the next
  // success or when the auto-reload window ends. A failure
  // replaces a still-pending retry rather than dropping its own:
  // otherwise a retry that comes due in the same instant as a
  // regular tick would be swallowed by the reload guard and the
  // chain would silently break back to the 90-second cadence.
  zScheduleRetry() {
    if (!this.zAutoActive()) return;
    if (typeof setTimeout === 'undefined') return;
    this.zClearRetry();
    this.zRetryTimer = setTimeout(() => {
      this.zRetryTimer = null;
      if (this.zAutoActive()) this.zFetchData();
    }, RETRY_MS);
  },
  zClearRetry() {
    if (this.zRetryTimer != null && typeof clearTimeout !== 'undefined') {
      clearTimeout(this.zRetryTimer);
    }
    this.zRetryTimer = null;
  },
  zNoteFetchFailure() {
    this.zFailHead();
    this.zScheduleRetry();
  },
  zOnReloadTick() {
    if (!this.zAutoActive()) {
      this.zStopAutoReload();
      this.zApplyHead();
      return;
    }
    this.zFetchData();
  },
  zProbeLocation() {
    const apply = (lat, lon) => {
      const idx = this.zNearestStation(lat, lon);
      this.zFootText = 'loc OK ' + STATIONS[idx][0] + ' ' + lat.toFixed(3) + ',' + lon.toFixed(3); this.syncDisplay();
      // Centre on the nearest station, unless the user has
      // already scrolled away from the initial view.
      if (!this.zUserMoved && idx !== this.zCenter) {
        this.zCenter = idx;
        this.zRender();
      }
    };
    try {
      // The real glasses expose location only via navigator.geolocation
      // (verified on-device with the kensho probe, vrf-b2: wx.getLocation
      // and friends do not exist; geolocation returned a real fix).
      if (typeof navigator !== 'undefined' && navigator.geolocation &&
          typeof navigator.geolocation.getCurrentPosition === 'function') {
        let answered = false;
        navigator.geolocation.getCurrentPosition(
          (p) => {
            answered = true;
            if (p && p.coords) apply(p.coords.latitude, p.coords.longitude);
          },
          () => {
            if (!answered) { answered = true; this.zFootText = 'loc NG'; this.syncDisplay(); }
          },
          { timeout: 8000 }
        );
        setTimeout(() => {
          if (!answered) { answered = true; this.zFootText = 'loc NG'; this.syncDisplay(); }
        }, 9000);
        return;
      }
      if (typeof wx !== 'undefined' && wx.getLocation) {
        wx.getLocation({
          type: 'wgs84',
          success: (r) => apply(r.latitude, r.longitude),
          fail: () => { this.zFootText = 'loc NG'; this.syncDisplay(); }
        });
      } else {
        this.zFootText = 'loc n/a'; this.syncDisplay();
      }
    } catch (e) {
      this.zFootText = 'loc err'; this.syncDisplay();
    }
  },
  zNearestStation(lat, lon) {
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < COORDS.length; i++) {
      const dLa = lat - COORDS[i][0];
      const dLo = (lon - COORDS[i][1]) * 0.82;
      const d = dLa * dLa + dLo * dLo;
      if (d < bestD) { bestD = d; best = i; }
    }
    return best;
  },
  zParseTrain(o) {
    const row = parseInt(o.locationRow, 10);
    // Rows 1..124 are the main line (Yodoyabashi is row 124). Rows
    // past 124 exist only on the Nakanoshima branch, whose grid
    // overlaps the Kitahama / Yodoyabashi blocks; zParsedTrains
    // decides what to do with them (zai-b33).
    if (isNaN(row) || row < 1 || row > 140) return null;
    const info = (o.trainInfoObjects && o.trainInfoObjects[0]) || {};
    return {
      row: row,
      off: (row - 1) % 3,
      seg: Math.floor((row - 1) / 3),
      dir: o.trainDirection === '0' ? '0' : '1',
      wdf: String(info.wdfBlockNo || ''),
      info: info,
      delay: o.delay || ''
    };
  },
  // True when the train runs via the Nakanoshima line: its
  // timetable entry names a branch station and never Kitahama.
  zIsNakanoshima(wdf) {
    if (!this.zTt) return false;
    const e = this.zTt[wdf];
    if (!e) return false;
    if (e['北浜'] !== undefined) return false;
    return e['中之島'] !== undefined || e['渡辺橋'] !== undefined ||
           e['なにわ橋'] !== undefined || e['大江橋'] !== undefined;
  },
  zParsedTrains() {
    const out = [];
    for (const o of this.zTrains) {
      const t = this.zParseTrain(o);
      if (!t) continue;
      if (t.row >= 121) {
        // (zai-b33) In the Kitahama (121-123) / Yodoyabashi (124)
        // block rows — and beyond them, up the branch — a
        // Nakanoshima-line train is really on the branch, before
        // or just past Temmabashi. Attribute it to Temmabashi's
        // block (in the section on the Yodoyabashi side) so it is
        // neither shown at, nor stop-filtered by, Kitahama /
        // Yodoyabashi, whose names its timetable does not carry.
        // Its row is kept for nearest-train ordering. Anything
        // else in rows past the terminus is dropped, as before.
        if (!this.zIsNakanoshima(t.wdf)) { if (t.row > 124) continue; }
        else { t.seg = 39; t.off = 2; }
      }
      out.push(t);
    }
    out.sort((a, b) => a.row - b.row);
    return out;
  },
  // true = stops at the station, false = passes, null = timetable unknown.
  // Values are either raw departure times ('99:99' = pass) from a fresh
  // fetch, or the pruned cache form ('1' = stop, '0' = pass).
  zStopsAt(wdf, stationName) {
    if (!this.zTt) return null;
    const entry = this.zTt[wdf];
    if (!entry) return null;
    const v = entry[stationName];
    if (v === undefined) return false;
    if (v === '99:99' || v === '0') return false;
    return true;
  },
  // Is stopped train A (at station S, row = firstRow of S) being held for a
  // following train that will pass S without stopping?
  zIsOvertakeWait(a, all) {
    if (!this.zTt) return false;
    const sName = STATIONS[a.seg][0];
    const cap = OVERTAKE[sName];
    if (!cap) return false;
    if (cap === 'up' && a.dir !== '0') return false;
    if (this.zStopsAt(a.wdf, sName) !== true) return false;
    // rows of the section immediately behind S (between the previous
    // station and S): down trains come from smaller rows, up from larger.
    let behind;
    if (a.dir === '1') behind = { lo: a.row - 2, hi: a.row - 1 };
    else behind = { lo: a.row + 4, hi: a.row + 5 };
    for (const b of all) {
      if (b === a || b.dir !== a.dir) continue;
      if (b.row < behind.lo || b.row > behind.hi) continue;
      if (this.zStopsAt(b.wdf, sName) === false) return true;
    }
    return false;
  },
  // (zai-b36) User rule: a stopped train is also an overtake wait
  // when another train in the SAME direction has an earlier
  // countdown at this station — e.g. a semi-express held at Sanjo
  // while an express behind it is due to leave Sanjo sooner.
  // Timetable-based (the same delay-adjusted departure diffs as
  // zNextTrainsText), so it also covers overtakers that stop here,
  // which zIsOvertakeWait (passing trains only) cannot see.
  // Skipped at the train's origin terminus, where an earlier
  // departure is just another service leaving first.
  zIsCountdownOvertake(a) {
    if (!this.zTt) return false;
    if (a.dir === '1' && a.seg === 0) return false;
    if (a.dir === '0' && a.seg === STATIONS.length - 1) return false;
    const sName = STATIONS[a.seg][0];
    const nowMin = this.zNowMinutes();
    // Delay-adjusted minutes until wdf's departure from this
    // station, or null when it does not depart here (passes,
    // originates, terminates, or no timetable entry).
    const diffOf = (wdf) => {
      const e = this.zTt[wdf];
      if (!e) return null;
      const dep = e[sName];
      if (!dep || dep === '99:99' || dep === '-') return null;
      const destName = e['__dest'] || this.zLastDestOf(e);
      if (destName === sName) return null;
      const parts = dep.split(':');
      if (parts.length !== 2) return null;
      let diff = (parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10))
        + (this.zDelay[wdf] || 0) - nowMin;
      if (diff < -30) diff += 1440;
      else if (diff > 720) diff -= 1440;
      return diff;
    };
    const diffA = diffOf(a.wdf);
    if (diffA === null || diffA < -1 || diffA > 90) return false;
    for (const wdf in this.zTt) {
      if (wdf === a.wdf) continue;
      const e = this.zTt[wdf];
      const pos = this.zPosByWdf[wdf];
      let dirB;
      if (pos) dirB = pos.dir;
      else {
        const destName = e['__dest'] || this.zLastDestOf(e);
        const destIdx = STATION_IDX[destName];
        if (destIdx === undefined || destIdx === a.seg) continue;
        dirB = destIdx > a.seg ? '1' : '0';
      }
      if (dirB !== a.dir) continue;
      // A train live data says has already left this station is
      // ahead of A, not an overtaker still to come.
      if (pos) {
        if (a.dir === '1') {
          if (pos.seg > a.seg || (pos.seg === a.seg && pos.off > 0)) continue;
        } else {
          if (pos.seg < a.seg) continue;
        }
      }
      const diffB = diffOf(wdf);
      if (diffB === null) continue;
      // Long past its departure with no live "not departed" word,
      // the train is treated as gone (same rule as zNextTrainsText).
      if (diffB < -1 && !(pos && Date.now() - this.zPosAt < RELOAD_MS * 2)) continue;
      if (diffB < diffA) return true;
    }
    return false;
  },
  zTrainLabel(t, all, compact) {
    const info = t.info;
    const arrow = t.dir === '0' ? '↑' : '↓';
    // Car count goes right after the type (↑準急8 出町柳行).
    // When several trains share a line, drop the trailing 行 to save width.
    let s = arrow + (info.trainTypeJp || '') + String(info.carsOfTrain || '') + ' ' + (info.destStationNameJp || '') + (compact ? '' : '行');
    if (t.delay && t.delay !== '±0' && t.delay !== '+0') s += ' ' + t.delay;
    if (t.off === 0) {
      const sName = STATIONS[t.seg][0];
      if (this.zStopsAt(t.wdf, sName) === false) return s; // passing through
      if (this.zIsOvertakeWait(t, all) || this.zIsCountdownOvertake(t)) return '[[' + s + ']]';
      return '[' + s + ']';
    }
    return s;
  },
  // (zai-b29) Unified position-load failure header: "読込失敗" plus
  // the last successful load time when this session has one.
  zFailHead() {
    this.zHeadBase = '読込失敗' + (this.zLastOkHm ? ' 最終' + this.zLastOkHm : '');
  },
  zFetchData() {
    const now = Date.now();
    if (now - this.zLastFetch < RELOAD_GUARD_MS) return;
    this.zLastFetch = now;
    this.zHeadBase = '在線 読込中...';
    this.zApplyHead();
    try {
      wx.request({
        url: URL_POS,
        method: 'GET',
        success: (res) => {
          this.zClearRetry();
          try {
            const d = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
            this.zTrains = d.locationObjects || [];
            // Anchor the display clock to the position file's server-side
            // creation time (JST wall time). Some preview runtimes have a
            // broken Date implementation that produced absurd minute
            // counts, so the minute math below uses NO Date at all: just
            // this wall-clock anchor plus the 10-second tick count.
            if (d.fileCreatedTime) {
              const fc = String(d.fileCreatedTime);
              this.zPosDate = this.zServiceDateStr(fc);
              const hh = parseInt(fc.slice(8, 10), 10);
              const mi = parseInt(fc.slice(10, 12), 10);
              const ss = parseInt(fc.slice(12, 14), 10);
              if (!isNaN(hh) && !isNaN(mi)) {
                this.zNowMin = hh * 60 + mi + (isNaN(ss) ? 0 : ss) / 60;
                this.zElapsedSec = 0;
              }
            }
            this.zDelay = {};
            this.zPosByWdf = {};
            this.zPosAt = Date.now();
            for (const t of this.zParsedTrains()) {
              this.zPosByWdf[t.wdf] = t;
              let dm = parseInt(t.info.delayMinutes, 10);
              if (isNaN(dm)) dm = parseInt(String(t.delay).replace('+', ''), 10);
              this.zDelay[t.wdf] = isNaN(dm) ? 0 : dm;
            }
            const t = String(d.fileCreatedTime || '');
            const hh = t.slice(8, 10), mm = t.slice(10, 12);
            this.zHeadBase = '京阪 在線 ' + hh + ':' + mm + '現在';
            const hNum = parseInt(hh, 10);
            if (!isNaN(hNum) && mm) this.zLastOkHm = hNum + ':' + mm;
          } catch (e) {
            // Keihan shows a maintenance page (HTML) during maintenance,
            // which lands here as a JSON parse failure.
            this.zNoteFetchFailure();
          }
          this.zApplyHead();
          this.zRender();
          this.zFetchTimetable();
        },
        fail: () => {
          this.zNoteFetchFailure();
          this.zApplyHead();
          this.zRender();
        }
      });
    } catch (e) {
      this.zNoteFetchFailure();
      this.zApplyHead();
      this.zRender();
    }
  },
  // Timetable (for stop/pass judgement) is cached on the device, keyed
  // to the service date (zai-b25): the file is regenerated per service
  // day and weekday/holiday diagrams differ, so the cached copy is
  // reused only when it was fetched for the same date as the current
  // position file. A new service day refetches once (the file is
  // ~4MB over the phone link, so per-launch refetching is not an
  // option). If storage or the fetch fails, display falls back to
  // geometry-only brackets.
  zFetchTimetable() {
    // (zai-b33) Retry while the timetable is still missing: the
    // first attempt runs right after the first position fetch,
    // and later position fetches retry at most once a minute
    // until it lands. (Before b33, a failed first attempt —
    // cache miss plus a failed ~4MB fetch over the phone link —
    // left the whole session without stop/pass filtering.)
    if (this.zTt) return;
    const now = Date.now();
    if (this.zTtLastTry && now - this.zTtLastTry < 60000) return;
    this.zTtLastTry = now;
    try {
      if (typeof wx !== 'undefined' && wx.getStorage) {
        wx.getStorage({
          key: 'zaisen_tt3',
          success: (r) => {
            const saved = r && r.data;
            if (saved && saved.map && saved.forDate && this.zPosDate && saved.forDate === this.zPosDate) {
              this.zTt = saved.map;
              this.zUpdateTypeWarn();
              this.zRender();
            } else {
              this.zFetchTimetableRemote();
            }
          },
          fail: () => { this.zFetchTimetableRemote(); }
        });
        return;
      }
    } catch (e) { /* fall through to remote fetch */ }
    this.zFetchTimetableRemote();
  },
  zFetchTimetableRemote() {
    try {
      wx.request({
        url: URL_TT,
        method: 'GET',
        success: (res) => {
          try {
            const d = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
            const map = {};
            const dayType = this.zTtDayType(d.fileCreatedTime);
            let covTotal = 0, covHit = 0;
            for (const t of (d.TrainInfo || [])) {
              const m = {};
              const dia = t.diaStationInfoObjects || [];
              for (const s of dia) {
                m[s.stationNameJp] = s.stationDepTime;
              }
              if (dia.length) m['__dest'] = dia[dia.length - 1].stationNameJp;
              const ann = this.zTypeKeyFor(m, dia);
              if (ann) {
                if (ann.nstop >= 2) covTotal++;
                const resolved = this.zResolveType(ann.key, ann.kitahama, dayType);
                if (resolved) {
                  m['__type'] = resolved;
                  if (ann.nstop >= 2) covHit++;
                }
              }
              map[String(t.wdfBlockNo)] = m;
            }
            this.zTypeCov = covTotal ? covHit / covTotal : 1;
            this.zTt = map;
            this.zUpdateTypeWarn();
            this.zSaveTimetable(map, this.zServiceDateStr(d.fileCreatedTime));
          } catch (e) {
            this.zTt = null;
          }
          this.zRender();
        },
        fail: () => { /* keep geometry-only display */ }
      });
    } catch (e) { /* keep geometry-only display */ }
  },
  // Save a pruned copy: main-line stations only, keeping the raw
  // departure-time strings (needed for the next-trains display).
  // fcDate is the timetable file's own date; forDate is the position
  // file's date at fetch time — the cache is valid only for that
  // service date (zai-b25).
  zSaveTimetable(fullMap, fcDate) {
    try {
      if (typeof wx === 'undefined' || !wx.setStorage) return;
      const names = {};
      for (const pair of STATIONS) names[pair[0]] = 1;
      const pruned = {};
      for (const wdf in fullMap) {
        const src = fullMap[wdf];
        const m = {};
        for (const nm in src) {
          if (names[nm] || nm === '__dest' || nm === '__type') m[nm] = src[nm];
        }
        pruned[wdf] = m;
      }
      wx.setStorage({ key: 'zaisen_tt3', data: { at: Date.now(), fcDate: fcDate || '', forDate: this.zPosDate || '', map: pruned } });
    } catch (e) { /* cache is best-effort */ }
  },
  // (zai-b26) Service date (yyyymmdd) of a fileCreatedTime, with the
  // day boundary at 05:00 instead of midnight (03:00 until zai-b36;
  // moved to 05:00 in zai-b37 after overnight probing showed the
  // served files flip at 04:20-04:35). Keihan's files describe
  // an operational day — the timetable spans 05:01-24:30, with
  // past-midnight times written as 24:xx — and in the small hours the
  // served files still carry the previous service day even though
  // their creation timestamp already shows the new calendar date.
  // Keying the timetable cache by calendar date would poison it when
  // the agent is opened between 00:00 and the content flip; with a
  // 05:00 boundary, 00:00-04:59 counts as the previous service day.
  zServiceDateStr(fc) {
    const t = String(fc || '');
    const y = parseInt(t.slice(0, 4), 10), mo = parseInt(t.slice(4, 6), 10), dd = parseInt(t.slice(6, 8), 10);
    const hh = parseInt(t.slice(8, 10), 10);
    if (isNaN(y) || isNaN(mo) || isNaN(dd) || isNaN(hh) || hh >= 5) return t.slice(0, 8);
    const serial = (yy, mm, d) => {
      const y2 = mm <= 2 ? yy - 1 : yy;
      const era = Math.floor(y2 / 400);
      const yoe = y2 - era * 400;
      const mp = (mm + 9) % 12;
      const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
      return era * 146097 + yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    };
    const s = serial(y, mo, dd) - 1;
    const era = Math.floor(s / 146097);
    const doe = s - era * 146097;
    const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    const y2 = yoe + era * 400;
    const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    const mp = Math.floor((5 * doy + 2) / 153);
    const d2 = doy - Math.floor((153 * mp + 2) / 5) + 1;
    const m2 = mp < 10 ? mp + 3 : mp - 9;
    const y3 = m2 <= 2 ? y2 + 1 : y2;
    const p2 = (n) => String(n).padStart(2, '0');
    return '' + y3 + p2(m2) + p2(d2);
  },
  // (zai-b24) Day type ('weekday' | 'holiday') of a timetable file from
  // its fileCreatedTime (yyyymmdd...): Saturdays and Sundays use the
  // holiday diagram. (zai-b26) Judged on the SERVICE date (see
  // zServiceDateStr; boundary 05:00 since zai-b37), so a file fetched
  // in the small hours is typed by the operational day it actually
  // carries.
  // Day-of-week comes from a civil-date serial number anchored on
  // 2026-11-02 (a Monday) — no Date parsing involved.
  zTtDayType(fc) {
    const t = this.zServiceDateStr(fc);
    const y = parseInt(t.slice(0, 4), 10), mo = parseInt(t.slice(4, 6), 10), dd = parseInt(t.slice(6, 8), 10);
    if (isNaN(y) || isNaN(mo) || isNaN(dd)) return 'weekday';
    const serial = (yy, mm, d) => {
      const y2 = mm <= 2 ? yy - 1 : yy;
      const era = Math.floor(y2 / 400);
      const yoe = y2 - era * 400;
      const mp = (mm + 9) % 12;
      const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
      return era * 146097 + yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    };
    let dow = (serial(y, mo, dd) - serial(2026, 11, 2)) % 7;
    if (dow < 0) dow += 7;
    return dow >= 5 ? 'holiday' : 'weekday';
  },
  // (zai-b24) The TYPE_TABLE lookup key for one timetable entry:
  // "dir|dest|stopPattern" over the 42 main-line stations (stop set
  // only; '-' counts as a stop — it marks the run's boundary station).
  // Depot-terminating entries (dest = Neyagawa signal yard) are keyed
  // by their last passenger stop, as in the official PDF. Also returns
  // the Kitahama departure time (normalized to "H:MM") used by the T
  // disambiguation table, and the main-line stop count.
  zTypeKeyFor(m, dia) {
    let pat = '', nstop = 0, first = -1, last = -1, lastStop = '';
    for (let i = 0; i < STATIONS.length; i++) {
      const v = m[STATIONS[i][0]];
      if (v && v !== '99:99') { pat += 'S'; nstop++; } else pat += '.';
    }
    for (const s of dia) {
      const ix = STATION_IDX[s.stationNameJp];
      if (ix === undefined) continue;
      if (first < 0) first = ix;
      last = ix;
      if (s.stationDepTime && s.stationDepTime !== '99:99') lastStop = s.stationNameJp;
    }
    if (first < 0) return null;
    let dest = m['__dest'] || lastStop;
    if (dest === '寝屋川信号場') dest = lastStop;
    const dir = last < first ? 'up' : 'down';
    let kitahama = m['北浜'] || '';
    if (kitahama.indexOf(':') > 0) {
      const p = kitahama.split(':');
      kitahama = String(parseInt(p[0], 10)) + ':' + p[1];
    } else kitahama = '';
    return { key: dir + '|' + dest + '|' + pat, nstop, kitahama };
  },
  // (zai-b24) Resolve a type abbreviation: the file's own day-type
  // table first, then the Kitahama-time table for shared patterns,
  // then the other day type's table (covers national-holiday
  // weekdays, which are served by the holiday diagram).
  zResolveType(key, kitahama, dayType) {
    if (!TYPE_TABLE) return '';
    const own = dayType === 'holiday' ? TYPE_TABLE.H : TYPE_TABLE.W;
    const other = dayType === 'holiday' ? TYPE_TABLE.W : TYPE_TABLE.H;
    if (own[key]) return own[key];
    const t = TYPE_TABLE.T[key];
    if (t && kitahama && t[kitahama]) return t[kitahama];
    return other[key] || '';
  },
  // (zai-b24) Keep the header's type-table warning in sync with the
  // coverage measured when the timetable was fetched (or recomputed
  // from the cached __type fields). Under 85% coverage the table no
  // longer matches the timetable in use — time to regenerate it.
  zUpdateTypeWarn() {
    if (typeof this.zTypeCov !== 'number') {
      if (!this.zTt) return;
      let total = 0, hit = 0;
      for (const wdf in this.zTt) {
        const e = this.zTt[wdf];
        let nstop = 0;
        for (let i = 0; i < STATIONS.length; i++) {
          const v = e[STATIONS[i][0]];
          if (v && v !== '99:99') nstop++;
        }
        if (nstop >= 2) { total++; if (e.__type) hit++; }
      }
      this.zTypeCov = total ? hit / total : 1;
    }
    this.zTypeWarn = this.zTypeCov < 0.85;
  },
  // Next departures at a station, grouped by direction (zai-b27):
  // "↑準出1:準出3↓急淀3:準中8" — up to 2 toward Demachiyanagi under
  // '↑', then up to 2 the other way under '↓'. Computed from
  // the timetable (scheduled departure + the train's current delay).
  // Type abbreviations come from the live position feed when the
  // train is running, else from the official-timetable type table
  // (zai-b24, the entry's __type).
  // Origin stations have no departure time in the data ("-"), so termini
  // starting there show nothing.
  // Current time-of-day in minutes (float) for the next-trains math:
  // the server-anchored wall clock when available, else the local clock.
  // Deliberately avoids epoch/Date arithmetic (see zNowMin note).
  zNowMinutes() {
    if (this.zNowMin >= 0) return this.zNowMin + this.zElapsedSec / 60;
    const d = new Date();
    return d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60;
  },
  zNextTrainsText(segIdx) {
    if (!this.zTt) return '';
    const sName = STATIONS[segIdx][0];
    const nowMin = this.zNowMinutes();
    const cands = [];
    for (const wdf in this.zTt) {
      const entry = this.zTt[wdf];
      const dep = entry[sName];
      if (!dep || dep === '99:99' || dep === '-') continue;
      // A train whose destination IS this station only arrives here;
      // its listed time is not a departure.
      const destName = entry['__dest'] || this.zLastDestOf(entry);
      if (destName === sName) continue;
      const parts = dep.split(':');
      if (parts.length !== 2) continue;
      let diff = (parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10))
        + (this.zDelay[wdf] || 0) - nowMin;
      if (diff < -30) diff += 1440;
      else if (diff > 720) diff -= 1440;
      const pos = this.zPosByWdf[wdf];
      // Live position verdict for this station: has the train already
      // departed it? Down trains depart into this station's own block
      // sections toward Yodoyabashi (off > 0) or beyond; up trains
      // depart into the next block toward Demachiyanagi (seg < segIdx).
      let notDeparted = false;
      if (pos) {
        if (pos.dir === '1') {
          if (pos.seg > segIdx || (pos.seg === segIdx && pos.off > 0)) continue;
          notDeparted = true;
        } else {
          if (pos.seg < segIdx) continue;
          notDeparted = true;
        }
      }
      // Past the usual 1-minute grace, a train is kept (shown '-')
      // only while fresh position data says it has not departed this
      // station yet. The freshness bound (~2 reload cycles) keeps a
      // frozen position snapshot from holding an entry forever after
      // auto-reload ends or the feed stalls.
      if (diff < -1 &&
          !(notDeparted && Date.now() - this.zPosAt < RELOAD_MS * 2)) continue;
      cands.push({ diff: diff, wdf: wdf, entry: entry });
    }
    cands.sort((a, b) => a.diff - b.diff);
    // Grouped display (zai-b27, user request): departures toward
    // Demachiyanagi first under '↑', all other departures under '↓',
    // at most 2 per group, e.g. "↑準出1:準出3↓急淀3:準中8". A train's
    // group is set by which side of this station its destination is on
    // (live direction as fallback for destinations outside STATIONS).
    const upItems = [];
    const downItems = [];
    for (let k = 0; k < cands.length; k++) {
      if (upItems.length >= 2 && downItems.length >= 2) break;
      const c = cands[k];
      let dest = '';
      const pos = this.zPosByWdf[c.wdf];
      if (pos && pos.info.destStationNameJp) dest = pos.info.destStationNameJp;
      let typeAb = '';
      if (pos && pos.info.trainTypeJp) {
        typeAb = TYPE_AB[pos.info.trainTypeJp] || String(pos.info.trainTypeJp).slice(0, 1);
      }
      if (!typeAb && c.entry.__type) typeAb = c.entry.__type;
      if (!dest) dest = c.entry['__dest'] || this.zLastDestOf(c.entry);
      const destIdx = STATION_IDX[dest];
      let up;
      if (destIdx !== undefined) up = destIdx < segIdx;
      else if (pos) up = pos.dir === '0';
      else up = false;
      const bucket = up ? upItems : downItems;
      if (bucket.length >= 2) continue;
      const destAb = DEST_AB[dest] || String(dest).slice(0, 1);
      // 4-car trains get a '.' after the type (see display rules).
      if (typeAb && pos && String(pos.info.carsOfTrain || '') === '4') typeAb += '.';
      // A train stays listed until 1 minute after its (delay-adjusted)
      // departure — or longer while live data says it has not departed
      // yet (see the hold rule above); whenever the remaining time is
      // past, it is shown as '-'.
      const mins = c.diff < 0 ? '-' : Math.floor(c.diff);
      bucket.push(typeAb + destAb + mins);
    }
    let out = '';
    if (upItems.length) out += '↑' + upItems.join(':');
    if (downItems.length) out += '↓' + downItems.join(':');
    return out;
  },
  zLastDestOf(entry) {
    // dia entries are in travel order per train; the destination is the
    // entry whose station is farthest along the itinerary. The timetable
    // object preserves insertion order, so take the last station name.
    let last = '';
    for (const nm in entry) {
      if (nm.indexOf('__') === 0) continue;
      last = nm;
    }
    return last;
  },
  // Focused mode: has this train already passed the focused station?
  // Down trains travel toward larger display indexes, up trains toward
  // smaller ones. A train inside the focused station's block counts as
  // "not passed" while it is at the station (down) or still approaching
  // it from below (up).
  zNotPassedFocus(t) {
    const f = this.zCenter;
    if (t.dir === '1') return t.seg < f || (t.seg === f && t.off === 0);
    return t.seg > f || t.seg === f;
  },
  // A station's display line. With bare set, the next-trains
  // countdown text is omitted (used by 'single' mode for the
  // approaching trains' stations, zai-b32).
  zStationLine(i, bare) {
    let s = (i === this.zCenter ? '>' : ' ') + STATIONS[i][0];
    if (!bare) {
      const nt = this.zNextTrainsText(i);
      if (nt) s += nt;
    }
    return s;
  },
  // Window the packed line list around the centred station's line
  // and push it into the L0..L13 display fields.
  zApplyLines(lines, centerLine) {
    let start = centerLine - 5;
    if (start < 0) start = 0;
    if (start > lines.length - 14) start = Math.max(0, lines.length - 14);
    // If the window would start on a train line (indented with a
    // full-width space), back up to that train's station line so the
    // first visible line always identifies the station.
    while (start > 0 && lines[start].charAt(0) === '　') start--;
    this.zLines = [];
    for (let k = 0; k < 14; k++) this.zLines.push(lines[start + k] || '');
    const realCount = Math.min(14, lines.length - start);
    const footText = this.zClockText + ' ' + this.zFootText + ' ' + this.data.build;
    if (realCount < 14) {
      this.zLines[realCount] = footText;
      this.zFootLine = '';
    } else {
      this.zFootLine = footText;
    }
    this.syncDisplay();
  },
  // (zai-b31) 'single' mode: the centred station, any trains stopped
  // there, and the nearest train per direction that stops at the
  // centred station and is still approaching it. An approaching
  // train is shown under the station line of the block it runs in,
  // except an up train already inside the centred station's own
  // section (toward Yodoyabashi), which follows the centred
  // station's lines directly.
  zRenderSingle(all) {
    const f = this.zCenter;
    const focusName = STATIONS[f][0];
    let downT = null, upT = null;
    const atStation = [];
    for (const t of all) {
      if (this.zStopsAt(t.wdf, focusName) === false) continue;
      if (t.seg === f && t.off === 0) { atStation.push(t); continue; }
      if (t.dir === '1') {
        if (t.seg < f && (!downT || t.row > downT.row)) downT = t;
      } else {
        if ((t.seg > f || (t.seg === f && t.off > 0)) && (!upT || t.row < upT.row)) upT = t;
      }
    }
    const lines = [];
    if (downT) {
      lines.push(this.zStationLine(downT.seg, true));
      lines.push('　' + this.zTrainLabel(downT, all, false));
    }
    const centerLine = lines.length;
    lines.push(this.zStationLine(f));
    for (let s2 = 0; s2 < atStation.length; s2 += 3) {
      const chunk = atStation.slice(s2, s2 + 3);
      const multi = chunk.length > 1;
      lines.push('　' + chunk.map(t => this.zTrainLabel(t, all, multi)).join(' '));
    }
    if (upT) {
      if (upT.seg !== f) lines.push(this.zStationLine(upT.seg, true));
      lines.push('　' + this.zTrainLabel(upT, all, false));
    }
    return { lines: lines, centerLine: centerLine };
  },
  zRender() {
    const all = this.zParsedTrains();
    if (this.zMode === 'single') { const rs = this.zRenderSingle(all); this.zApplyLines(rs.lines, rs.centerLine); return; }
    const focusName = STATIONS[this.zCenter][0];
    const bySeg = {};
    for (const t of all) {
      if (this.zMode === 'focus') {
        // Hide trains that do not stop at the focused station (the
        // timetable also excludes trains that never reach it), and
        // trains that have already passed it.
        if (this.zStopsAt(t.wdf, focusName) === false) continue;
        if (!this.zNotPassedFocus(t)) continue;
      }
      if (!bySeg[t.seg]) bySeg[t.seg] = [];
      bySeg[t.seg].push(t);
    }
    const lines = [];
    let centerLine = 0;
    for (let i = 0; i < STATIONS.length; i++) {
      const name = STATIONS[i][0];
      const tr = bySeg[i] || [];
      // In focus and omit modes, stations with no (relevant) train
      // are hidden too (the centred station itself always stays).
      if (this.zMode !== 'all' && i !== this.zCenter && tr.length === 0) continue;
      if (i === this.zCenter) centerLine = lines.length;
      lines.push(this.zStationLine(i));
      // Combine the block's trains onto lines of up to 3 trains each;
      // any remaining trains continue on the next line.
      for (let s2 = 0; s2 < tr.length; s2 += 3) {
        const chunk = tr.slice(s2, s2 + 3);
        const multi = chunk.length > 1;
        const line = chunk.map(t => this.zTrainLabel(t, all, multi)).join(' ');
        // Indent train lines with one full-width space: leading half-width
        // spaces are ignored by the Ink text renderer (seen in previews).
        lines.push('　' + line);
      }
    }
    this.zApplyLines(lines, centerLine);
  },
  zMove(d) {
    this.zUserMoved = true;
    let c = this.zCenter + d;
    if (c < 0) c = 0;
    if (c > STATIONS.length - 1) c = STATIONS.length - 1;
    this.zCenter = c;
    this.zRender();
  },
  // ---- radar engine (rdr-b12, prefixed r*) ----
// rdr-b11: a third here-mode view, 詳細 (detail): the current
// location at 1.5x the near zoom (user request 2026-11-14).
// The here cycle is now here -> widehere -> detail -> here.
// Server-side the detail view is the z12 View at scale 1.5
// (base_detail.png / detail[_pN].png from RadarGen).
// rdr-b10: never blank the picture during an update
// (2026-11-14, user request). Until b9, any not-ready moment
// (reload, here-mode staging) swapped the <image> back to the
// base map, and every swap left a blank while the PNG loaded.
// Now applyView remembers the last painted rain frame: while
// the current mode is not ready, a session that has already
// painted a frame KEEPS showing it (status switches to
// （更新中…）) and swaps exactly once when the fresh frame is
// ready. The base-map stage remains only for a cold open,
// when nothing has been painted yet.
// rdr-b12: BACK right after an interaction also exits
// (2026-11-16, user request). A tap or swipe arms the same
// 3 s pass-through window the reload-BACK arms: BACK within
// 3 s of the last tap/swipe is NOT consumed, so e.g. swipe
// then BACK leaves at once instead of reloading first.
// rdr-b9: BACK twice to exit (2026-11-14, device report on b8:
// the reload worked but the page ate EVERY back press, so the
// AIUI exit sequence never ran and the agent could not be
// closed). Now: a back press more than 3 s after the last
// reload consumes + reloads; a second press inside 3 s is NOT
// consumed and passes through to the OS exit.
// rdr-b8: BACK key reloads (2026-11-14, user request). Back is
// the first stage of the OS exit gesture, but it is delivered
// to the app first (seen in another app), so the page consumes
// it and re-runs the whole open sequence: back to the fixed
// set at the current frame, fresh /radar/request, geolocation
// and polling restarted.
// rdr-b7: dedicated rain-radar agent (2026-11-13).
// Changes from b6 (user device feedback):
// - Tap lockout: one physical temple tap could advance the view
//   TWICE (an extra GlobalHook after the Enter confirm armed a
//   second tap). After a confirmed tap, further tap gestures are
//   ignored for 700 ms.
// - Zooms: the z9 regional view is gone. Both modes are now
//   near z12 / wide z11 (the old z11 "current" range is the new
//   wide; near is a 2x zoom of it). Labels are the local set at
//   both zooms (off-frame ones clip, thinning the near view).
// - The fixed set is centred on KYOTO STATION, not home — the
//   startup map must not give away the home location in
//   screenshots. (View keys stay home/wide for file compat.)
// Layout: hint line moved ABOVE the image (user device report:
// text below the image falls outside the visible band).
// Generation is ON DEMAND inside the laptop listener (RadarGen):
// nothing is rendered periodically. On open the page POSTs a bare
// /radar/request to trigger a home-set refresh (the listener
// regenerates only when its stored frame is stale).
// Staged display (user design): at open, show the base MAP only
// for the current view — the map itself never changes, so it is
// served as its own file (base_<view>.png). Scale taps swap the
// base immediately; time swipes are remembered as the wanted
// offset. When the rendered frame is ready (meta answered_at /
// validtime change), the display switches to the rain image at
// the remembered view + offset. The here mode stages the same
// way: base-meta-here.json lands first (map), meta-here.json
// second (rain).
// - Home mode: frames centred on Kyoto Station; views home
//   (z12, 京都駅周辺) / wide (z11, 京都駅・広域).
// - Here mode: the page reads navigator.geolocation, POSTs
//   {lat,lon} to the listener (/radar/request), and polls
//   meta-here.json until the listener has rendered frames centred
//   on the current location; views here (z12) / widehere (z11).
//   Falls back to home mode when geolocation or generation fails.
// - Gestures (temple model from kensho b16 + b7 lockout): tap
//   (GlobalHook arm + Enter confirm, or a bare Enter) cycles the
//   view; swipe (ArrowUp/ArrowDown) steps the frame time through
//   the nowcast forecasts +5/+10/+30/+60 min and back.
// Layout follows the kensho b24 device findings: status above the
// image, nothing essential below it.

  rBase: 'http://100.124.235.107:18765/radar/',
  rToken: 'gchat-4c1d9a72',
  rModes: {
    home: { meta: 'meta.json', views: [
      { key: 'home', label: '京都駅周辺' },
      { key: 'wide', label: '京都駅・広域' } ] },
    here: { meta: 'meta-here.json', views: [
      { key: 'here', label: '現在地' },
      { key: 'widehere', label: '現在地・広域' },
      { key: 'detail', label: '現在地・詳細' } ] }
  },
  rMode: 'home',
  rView: 0,
  rFIdx: 0,
  rFrames: [{ off: 0, vt: '', display: '' }],
  rPollTimer: null,
  rPollLeft: 0,
  rHereReqAt: 0,
  rHereLat: null,
  rHereLon: null,
  rOpenAt: 0,
  rPaintedVt: '',
  rLastFrameSrc: '',
  rHomeReady: false,
  rHereReady: false,
  rHereBaseReady: false,
  rBasesAt: 0,
  rBaseLeft: 0,
  rPollMs: 3000,
  rOnLoad() {
    this.rOpenAt = Math.floor(Date.now() / 1000);
    this.rLastReqAtS = this.rOpenAt;
    this.rLoadMeta('home', (m) => {
      if (m && Array.isArray(m.frames) && m.frames.length) this.rPaintedVt = m.frames[0].vt;
      this.rApplyView();
    });
    this.rPostOpenPing();
    this.rPollHomeFresh();
    this.rStartHere();
  },
  rPostOpenPing() {
    try {
      wx.request({
        url: this.rBase + 'request',
        method: 'POST',
        header: { 'X-Talk-Token': this.rToken, 'content-type': 'application/json' },
        data: {},
        success: () => {},
        fail: () => {}
      });
    } catch (e) {}
  },
  // The home frame counts as ready when the listener has answered
  // this open (answered_at) or a newer frame has landed; after ~2
  // min of silence, fall back to the stored (stale) frames.
  rPollHomeFresh() {
    let left = 40;
    const step = () => {
      if (this.rHomeReady) return;
      if (left-- <= 0) {
        this.rHomeReady = true;
        if (this.rMode === 'home') this.rApplyView();
        return;
      }
      this.rLoadMeta('home', (m) => {
        const answered = m && typeof m.answered_at === 'number' && m.answered_at >= this.rOpenAt - 5;
        const newer = m && Array.isArray(m.frames) && m.frames.length
          && this.rPaintedVt && m.frames[0].vt !== this.rPaintedVt;
        if (answered || newer) {
          this.rHomeReady = true;
          if (this.rMode === 'home') this.rApplyView();
          return;
        }
        this.rHomeTimer = setTimeout(step, this.rPollMs);
      });
    };
    this.rHomeTimer = setTimeout(step, this.rPollMs);
  },
  rLoadMeta(mode, cb) {
    try {
      wx.request({
        url: this.rBase + this.rModes[mode].meta,
        success: (res) => {
          const m = (res && res.data) || {};
          if (Array.isArray(m.frames) && m.frames.length) {
            if (mode === this.rMode) {
              this.rFrames = m.frames;
              if (this.rFIdx >= this.rFrames.length) this.rFIdx = this.rFrames.length - 1;
            }
          }
          if (cb) cb(m);
        },
        fail: () => { if (cb) cb(null); }
      });
    } catch (e) { if (cb) cb(null); }
  },
  rStartHere() {
    let geo = null;
    try { geo = (typeof navigator !== 'undefined') ? navigator.geolocation : null; } catch (e) { geo = null; }
    if (!geo || !geo.getCurrentPosition) return;
    this.rHintText = '現在地を取得中…'; this.rChanged();
    try {
      geo.getCurrentPosition(
        (pos) => {
          const c = (pos && pos.coords) || {};
          if (typeof c.latitude !== 'number' || typeof c.longitude !== 'number') { this.rHereFailed(); return; }
          this.rHereLat = c.latitude; this.rHereLon = c.longitude;
          this.rHereReqAt = Math.floor(Date.now() / 1000);
          this.rHintText = '現在地レーダーを作成中…'; this.rChanged();
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
          this.rPollLeft = 40;
          this.rBaseLeft = 40;
          this.rPollHereBase();
          this.rPollHere();
        },
        () => this.rHereFailed(),
        { timeout: 15000 }
      );
    } catch (e) { this.rHereFailed(); }
  },
  rHereFailed() {
    this.rHintText = '現在地が取れませんでした（京都駅を表示）'; this.rChanged();
  },
  // Stage 1 of here mode: the listener writes base maps + this
  // meta before rendering frames; switch to the current-location
  // MAP as soon as it matches this request.
  rPollHereBase() {
    if (this.rMode === 'here' || this.rBaseLeft <= 0) return;
    this.rBaseLeft--;
    try {
      wx.request({
        url: this.rBase + 'base-meta-here.json',
        success: (res) => {
          const m = (res && res.data) || {};
          const ctr = Array.isArray(m.centre) ? m.centre : null;
          const fresh = typeof m.bases_at === 'number' && m.bases_at >= this.rHereReqAt - 660;
          const near = ctr && Math.abs(ctr[0] - this.rHereLat) + Math.abs(ctr[1] - this.rHereLon) <= 0.02;
          if (ctr && fresh && near) {
            const wasHere = this.rMode === 'here';
            this.rMode = 'here';
            if (!wasHere) this.rView = 0;
            this.rHereBaseReady = true;
            this.rBasesAt = m.bases_at;
            this.rApplyView();
            return;
          }
          this.rBaseTimer = setTimeout(() => this.rPollHereBase(), this.rPollMs);
        },
        fail: () => { this.rBaseTimer = setTimeout(() => this.rPollHereBase(), this.rPollMs); }
      });
    } catch (e) {
      this.rBaseTimer = setTimeout(() => this.rPollHereBase(), this.rPollMs);
    }
  },
  rPollHere() {
    if (this.rPollLeft <= 0) {
      this.rHintText = '現在地レーダーが間に合いませんでした'; this.rChanged();
      return;
    }
    this.rPollLeft--;
    try {
      wx.request({
        url: this.rBase + 'meta-here.json',
        success: (res) => {
          const m = (res && res.data) || {};
          const ctr = Array.isArray(m.centre) ? m.centre : null;
          const fresh = typeof m.generated_at === 'number' && m.generated_at >= this.rHereReqAt - 660;
          const near = ctr && Math.abs(ctr[0] - this.rHereLat) + Math.abs(ctr[1] - this.rHereLon) <= 0.02;
          if (ctr && fresh && near && Array.isArray(m.frames) && m.frames.length) {
            const wasHere = this.rMode === 'here';
            this.rMode = 'here';
            if (!wasHere) this.rView = 0;
            if (this.rFIdx >= m.frames.length) this.rFIdx = 0;
            this.rFrames = m.frames;
            this.rHereReady = true;
            this.rHintText = 'タップ: 切替 / スワイプ: 時刻 / バック: 再読込'; this.rChanged();
            this.rApplyView();
            return;
          }
          this.rPollTimer = setTimeout(() => this.rPollHere(), this.rPollMs);
        },
        fail: () => { this.rPollTimer = setTimeout(() => this.rPollHere(), this.rPollMs); }
      });
    } catch (e) {
      this.rPollTimer = setTimeout(() => this.rPollHere(), this.rPollMs);
    }
  },
  rApplyView() {
    const views = this.rModes[this.rMode].views;
    const v = views[this.rView % views.length];
    const f = this.rFrames[this.rFIdx] || this.rFrames[0];
    const ready = this.rMode === 'home' ? this.rHomeReady : this.rHereReady;
    if (!ready) {
      if (this.rLastFrameSrc) {
        // rdr-b10: a frame was already painted this session —
        // keep showing it until the fresh frame is ready, and
        // swap exactly once then. Only the status changes.
        this.rStatusText = v.label + '（更新中…）';
        this.rChanged();
        return;
      }
      // Map-only stage (cold open): the base map for the
      // current view. Scale taps and time swipes already took
      // effect on rView/rFIdx and will apply to the frame
      // when it lands.
      const bust = this.rMode === 'here' && this.rBasesAt ? ('?v=' + this.rBasesAt) : '';
      this.rImgSrc = this.rBase + 'base_' + v.key + '.png' + bust;
      this.rStatusText = v.label + ' の地図（作成中…）';
      this.rChanged();
      return;
    }
    const suffix = f.off ? ('_p' + f.off) : '';
    const q = f.vt ? ('?v=' + f.vt) : '';
    const src = this.rBase + v.key + suffix + '.png' + q;
    this.rLastFrameSrc = src;
    this.rImgSrc = src;
    this.rStatusText = v.label + '  ' + (f.off ? ('+' + f.off + '分予測 ' + f.display) : (f.display + ' の雨雲'));
    this.rChanged();
  },
  // BACK key: full rReload, identical to closing and reopening
  // the agent — reset to the fixed set at the current frame,
  // drop all ready flags, stop every poll, then run the open
  // sequence again (request ping, home poll, geolocation).
  // Since rdr-b10 the picture itself is NOT dropped: rApplyView
  // keeps the last painted frame on screen until the fresh
  // one is ready.
  rReload() {
    this.clearTapArm();
    if (this.rHomeTimer) { clearTimeout(this.rHomeTimer); this.rHomeTimer = null; }
    if (this.rPollTimer) { clearTimeout(this.rPollTimer); this.rPollTimer = null; }
    if (this.rBaseTimer) { clearTimeout(this.rBaseTimer); this.rBaseTimer = null; }
    this.rMode = 'home';
    this.rView = 0;
    this.rFIdx = 0;
    this.rFrames = [{ off: 0, vt: '', display: '' }];
    this.rPaintedVt = '';
    this.rHomeReady = false;
    this.rHereReady = false;
    this.rHereBaseReady = false;
    this.rOpenAt = Math.floor(Date.now() / 1000);
    this.rLastReqAtS = this.rOpenAt;
    this.rStatusText = '再読込中…'; this.rHintText = 'もう一度バック: 終了'; this.rChanged();
    this.rLoadMeta('home', (m) => {
      if (m && Array.isArray(m.frames) && m.frames.length) this.rPaintedVt = m.frames[0].vt;
      this.rApplyView();
    });
    this.rPostOpenPing();
    this.rPollHomeFresh();
    this.rStartHere();
  },
  rCycleView() {
    const views = this.rModes[this.rMode].views;
    this.rView = (this.rView + 1) % views.length;
    this.rApplyView();
  },
  rStepTime(dir) {
    const n = this.rFIdx + dir;
    if (n < 0 || n >= this.rFrames.length) return;
    this.rFIdx = n;
    this.rApplyView();
  },
  // ---- odekake shell ----
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
  // from the engine buffers. The whole column (head, zaisen
  // lines, foot, radar status, hint, radar image) lives in
  // one <scroll-view>; syncDisplay echoes the shell's scroll
  // position (svTopVal) so engine updates never move the
  // view. In radar mode svTopVal points at the radar block,
  // so the '' zaisen slots above it are scrolled past.
  syncDisplay() {
    const patch = { head: '', status: '', hint: '', imgSrc: '', foot: '', svTop: this.svTopVal };
    for (let k = 0; k < 14; k++) patch['L' + k] = '';
    if (this._oMode === 'zaisen') {
      patch.head = this.zHeadText;
      for (let k = 0; k < 14; k++) patch['L' + k] = this.zLines[k] || '';
      patch.foot = this.zFootLine;
    } else if (this._oMode === 'radar') {
      patch.head = 'Radar ' + this.data.build;
      patch.status = this.rStatusText;
      patch.hint = this.rHintText;
      patch.imgSrc = this.rImgSrc;
    } else {
      patch.head = this.zHeadText;
      const rs = this.zRenderSingle(this.zParsedTrains());
      // The footer rides in the line flow here too (zai-b41):
      // into the first slot after the single lines when one is
      // spare, else into the foot element.
      const footText = [this.zClockText, this.zFootText].filter(Boolean).join(' ');
      let used = 0;
      for (let k = 0; k < 14 && k < rs.lines.length; k++) { patch['L' + k] = rs.lines[k]; used++; }
      if (used < 14) patch['L' + used] = footText;
      else patch.foot = footText;
      patch.status = this.rComboStatusText;
      patch.hint = 'タップ: 予測 / タップ→スワイプ: モード切替';
      patch.imgSrc = this.rComboImgSrc;
    }
    // odk-b8: collapse every '' slot (and an '' foot) so its
    // retained height cannot push the blocks below it down.
    // Kensho vrf-b35 proved a bound class that zeroes
    // line-height/font-size/height collapses a retained slot.
    for (let k = 0; k < 14; k++) patch['L' + k + 'c'] = patch['L' + k] ? 'line' : 'line gone';
    patch.footc = patch.foot ? 'foot' : 'foot gone';
    this.setData(patch);
  },
  // Combo scrolling: step the scroll-view by 3 lines per
  // swipe, clamped to the combo column's rough extent.
  stepScroll(down) {
    let v = this.svTopVal + (down ? 63 : -63);
    if (v < 0) v = 0;
    if (v > 320) v = 320;
    this.svTopVal = v;
    this.setData({ svTop: v });
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
    // Every mode starts from its top: combo/zaisen from the
    // column head, radar from its status/hint/image block.
    this.svTopVal = this._oMode === 'radar' ? this.RADAR_TOP : 0;
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
  // DEBUG drive (user suggestion 2026-11-17): the daemon's
  // send_key cadence (~5 s per token) cannot fit the 3 s
  // tap->swipe window, so development verification drives
  // mode switches with a dedicated key. Measured facts
  // (kensho vrf-b34 keylog, 2026-11-18): ink key events
  // carry ONLY `code` (key / keyCode are always undefined);
  // a physical temple swipe delivers GlobalHook, then
  // ArrowRight/Left x1-2 and ArrowDown/Up x1 — the count
  // varies, so count-based fingerprints are unreliable;
  // daemon scan 149 (SETTINGS) delivers a 'Shortcut'
  // keyDOWN only, which a temple swipe can never produce;
  // scan 148 and letter scans deliver nothing. Hence:
  // 'Shortcut' (onKeyDown) = next mode. Development exit
  // needs no page support: the launcher is brought forward
  // over adb (am start SpriteMainActivity).
  onKeyDown(event) {
    const code = event && event.code;
    if (code === 'ArrowUp' || code === 'ArrowDown'
        || code === 'ArrowLeft' || code === 'ArrowRight') {
      // A swipe's first arrow keyDOWN cancels the pending
      // tap arm (odk-b7): a long swipe's ArrowDown keyUP can
      // land past the tap window (its horizontal repeats
      // stretch the sequence), but the first arrow keyDOWN
      // arrives early — the tap must not fire for a swipe.
      this.clearTapArm();
    }
    if (code === 'Shortcut') {
      this._lastInteractAt = Date.now();
      this._tapSnap = null;
      this.clearTapArm();
      this.switchMode(1);
    }
  },
  onKeyUp(event) {
    const code = event && event.code;
    const kc = event && (typeof event.keyCode === 'number' ? event.keyCode
      : (typeof event.which === 'number' ? event.which : -1));
    // BT keyboard only: a = next mode, s = previous mode.
    // (Daemon-sent letter scans never reach the page; the
    // daemon drives via 'Shortcut' in onKeyDown instead.)
    const key = event && event.key;
    if (code === 'KeyA' || key === 'a' || kc === 65) {
      event.preventDefault();
      this._lastInteractAt = Date.now();
      this._tapSnap = null;
      this.clearTapArm();
      this.switchMode(1);
      return;
    }
    if (code === 'KeyS' || key === 's') {
      event.preventDefault();
      this._lastInteractAt = Date.now();
      this._tapSnap = null;
      this.clearTapArm();
      this.switchMode(-1);
      return;
    }
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
      this._tapTimer = setTimeout(() => { this._tapTimer = null; this.fireTap(); }, 500);
      return;
    }
    if (code === 'Enter') {
      event.preventDefault();
      if (Date.now() < this._tapLockUntil) return;
      this.clearTapArm();
      this.fireTap();
      return;
    }
    if (code === 'ArrowLeft' || code === 'ArrowRight') {
      // Horizontal swipe components: not page actions, but
      // they prove a gesture is a swipe — cancel any pending
      // tap arm (odk-b7, belt-and-braces with onKeyDown).
      this.clearTapArm();
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
      event.preventDefault();
      if (this._oMode === 'combo') { this.stepScroll(down); return; }
      if (this._oMode === 'zaisen') this.zMove(down ? 1 : -1);
      else this.rStepTime(down ? -1 : 1);
      this.syncDisplay();
    }
  }
}
</script>

<page>
  <view class="container">
    <scroll-view class="sv" scroll-y="true" scroll-top="{{ svTop }}">
    <text class="head">{{ head }}</text>
    <text class="{{ L0c }}">{{ L0 }}</text>
    <text class="{{ L1c }}">{{ L1 }}</text>
    <text class="{{ L2c }}">{{ L2 }}</text>
    <text class="{{ L3c }}">{{ L3 }}</text>
    <text class="{{ L4c }}">{{ L4 }}</text>
    <text class="{{ L5c }}">{{ L5 }}</text>
    <text class="{{ L6c }}">{{ L6 }}</text>
    <text class="{{ L7c }}">{{ L7 }}</text>
    <text class="{{ L8c }}">{{ L8 }}</text>
    <text class="{{ L9c }}">{{ L9 }}</text>
    <text class="{{ L10c }}">{{ L10 }}</text>
    <text class="{{ L11c }}">{{ L11 }}</text>
    <text class="{{ L12c }}">{{ L12 }}</text>
    <text class="{{ L13c }}">{{ L13 }}</text>
    <text class="{{ footc }}">{{ foot }}</text>
    <text class="sub">{{ status }}</text>
    <text class="hint">{{ hint }}</text>
    <image class="radar" src="{{ imgSrc }}"></image>
    </scroll-view>
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

.sv {
  width: 448px;
  height: 338px;
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

.gone {
  line-height: 0px;
  font-size: 0px;
  height: 0px;
  margin-top: 0px;
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
