/// Web UI（毛玻璃 + 專輯封面模糊背景）。
///
/// 整個頁面是單一 HTML（零外部依賴），由 [MediaControlServer] 在 `/` 提供。
/// 網址加上 `?demo` 可以不連手機、用假資料預覽。
String buildWebUiHtml({String updateMode = 'sse'}) {
  return r'''
<!doctype html>
<html lang="zh-TW" data-theme="dark">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<meta name="color-scheme" content="dark light" />
<title>大便媒體控制</title>
<script>(function(){var m='auto';try{m=localStorage.getItem('mc-theme')||'auto'}catch(e){}var l=m==='light'||(m==='auto'&&matchMedia('(prefers-color-scheme: light)').matches);document.documentElement.dataset.theme=l?'light':'dark'})()</script>
<style>
  /* ---------- 色彩 token：--a1/--a2/--a3 由專輯封面抽色後即時寫入 ---------- */
  @property --a1 { syntax: '<color>'; inherits: true; initial-value: #62b6c4; }
  @property --a2 { syntax: '<color>'; inherits: true; initial-value: #7d8cd8; }
  @property --a3 { syntax: '<color>'; inherits: true; initial-value: #1f3a4a; }

  :root {
    --on-a1: #0e1016;
    --font: "Inter", "SF Pro Display", "PingFang TC", "Noto Sans TC", "Microsoft JhengHei", system-ui, -apple-system, "Segoe UI", sans-serif;
    --ease: cubic-bezier(.2, .8, .2, 1);
    transition: --a1 .9s ease, --a2 .9s ease, --a3 .9s ease;
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --base: #0c0d12;
    --fg: #f4f5f8;
    --fg2: rgba(244, 245, 248, .70);
    --fg3: rgba(244, 245, 248, .46);
    --glass: rgba(22, 24, 32, .40);
    --glass-2: rgba(255, 255, 255, .07);
    --glass-3: rgba(255, 255, 255, .13);
    --rim: rgba(255, 255, 255, .16);
    --rim-soft: rgba(255, 255, 255, .08);
    --shadow: 0 40px 90px -20px rgba(0, 0, 0, .55);
    --bg-bright: .62;
    --bg-op: .95;
    --veil: linear-gradient(180deg, rgba(0,0,0,.10), rgba(0,0,0,.38));
    --track: rgba(255, 255, 255, .16);
    --card: rgba(26, 28, 36, .86);
    --err: #ff8a8a;
  }
  :root[data-theme="light"] {
    color-scheme: light;
    --base: #e9ebf0;
    --fg: #14161c;
    --fg2: rgba(20, 22, 28, .70);
    --fg3: rgba(20, 22, 28, .50);
    --glass: rgba(255, 255, 255, .50);
    --glass-2: rgba(255, 255, 255, .55);
    --glass-3: rgba(255, 255, 255, .8);
    --rim: rgba(255, 255, 255, .85);
    --rim-soft: rgba(20, 22, 28, .06);
    --shadow: 0 40px 90px -30px rgba(40, 50, 80, .35);
    --bg-bright: 1.12;
    --bg-op: .6;
    --veil: linear-gradient(180deg, rgba(255,255,255,.28), rgba(255,255,255,.12));
    --track: rgba(20, 22, 28, .14);
    --card: rgba(255, 255, 255, .9);
    --err: #c62828;
  }

  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body {
    min-height: 100vh;
    min-height: 100dvh;
    font-family: var(--font);
    color: var(--fg);
    background: var(--base);
    -webkit-font-smoothing: antialiased;
    -webkit-tap-highlight-color: transparent;
  }
  button { font: inherit; color: inherit; border: 0; background: none; padding: 0; cursor: pointer; }
  svg { display: block; width: 100%; height: 100%; fill: currentColor; }
  :focus-visible { outline: 2px solid var(--a1); outline-offset: 3px; border-radius: 12px; }
  [hidden] { display: none !important; }

  /* ---------- 跑馬燈：文字比容器寬時來回滾動 ---------- */
  .mq { overflow: hidden; min-width: 0; }
  .mq > .mq-inner { display: inline-block; white-space: nowrap; vertical-align: top; will-change: transform; }
  .mq.on > .mq-inner { animation: mq-scroll var(--mq-dur, 8s) ease-in-out infinite alternate; }
  @keyframes mq-scroll {
    0%, 8% { transform: translateX(0); }
    92%, 100% { transform: translateX(var(--mq-x, 0px)); }
  }

  /* ---------- 場景：封面模糊背景 ---------- */
  .scene { position: fixed; inset: 0; z-index: -1; overflow: hidden; background: var(--base); }
  .bg {
    position: absolute; inset: -14%;
    background-size: cover; background-position: center;
    opacity: 0; transform: scale(1.12);
    filter: blur(72px) saturate(1.7) brightness(var(--bg-bright));
    transition: opacity 1.2s ease;
  }
  .bg.on { opacity: var(--bg-op); }
  .blob { position: absolute; border-radius: 50%; opacity: .5; filter: blur(30px); }
  .blob.one { width: 62vmax; height: 62vmax; left: -22vmax; top: -28vmax; background: radial-gradient(circle, var(--a1), transparent 66%); }
  .blob.two { width: 56vmax; height: 56vmax; right: -22vmax; bottom: -28vmax; background: radial-gradient(circle, var(--a2), transparent 66%); }
  .veil { position: absolute; inset: 0; background: var(--veil); }
  .grain {
    position: absolute; inset: 0; opacity: .08; mix-blend-mode: overlay; pointer-events: none;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  }

  /* ---------- 玻璃 ---------- */
  .glass {
    background: var(--glass);
    -webkit-backdrop-filter: blur(44px) saturate(1.6);
    backdrop-filter: blur(44px) saturate(1.6);
    box-shadow: var(--shadow), inset 0 0 0 1px var(--rim-soft), inset 0 1px 0 var(--rim);
  }

  /* ---------- 外框 ---------- */
  .app {
    max-width: 1360px; margin: 0 auto; min-height: 100vh; min-height: 100dvh;
    padding: 22px clamp(16px, 3vw, 44px) 22px;
    display: flex; flex-direction: column;
  }
  .top { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 22px; }
  .brand { display: flex; align-items: center; gap: 12px; font-weight: 700; font-size: 17px; letter-spacing: .02em; }
  .brand .mark { width: 34px; height: 34px; border-radius: 11px; display: grid; place-items: center; color: var(--on-a1);
    background: linear-gradient(135deg, var(--a1), var(--a2)); box-shadow: 0 8px 24px -6px var(--a1); }
  .brand .mark svg { width: 20px; height: 20px; }
  .top-actions { display: flex; align-items: center; gap: 8px; }

  .conn { display: inline-flex; align-items: center; gap: 8px; height: 38px; padding: 0 14px; border-radius: 999px;
    font-size: 13px; font-weight: 600; color: var(--fg2); background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft); }
  .conn i { width: 8px; height: 8px; border-radius: 50%; background: var(--fg3); }
  .conn[data-state="live"] i { background: #3ddc97; box-shadow: 0 0 0 0 rgba(61, 220, 151, .55); animation: ping 2.2s ease-out infinite; }
  .conn[data-state="poll"] i { background: #f3b43f; }
  .conn[data-state="offline"] i { background: #ff6b6b; }
  @keyframes ping { 70% { box-shadow: 0 0 0 8px rgba(61, 220, 151, 0); } 100% { box-shadow: 0 0 0 0 rgba(61, 220, 151, 0); } }

  .ib { width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; color: var(--fg); transition: background .2s, transform .2s var(--ease), opacity .2s; }
  .ib > span { display: block; width: 22px; height: 22px; }
  .ib:hover { background: var(--glass-3); }
  .ib:active { transform: scale(.92); }
  .ib.round { width: 38px; height: 38px; background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft); }
  .ib.round > span { width: 19px; height: 19px; }
  .soft { opacity: .42; }

  /* ---------- 版面 ---------- */
  .layout { flex: 1; display: grid; grid-template-columns: minmax(0, 1fr) 372px; gap: 22px; align-items: stretch; }

  /* ---------- 舞台（現正播放） ---------- */
  .stage {
    border-radius: 44px; padding: clamp(26px, 3.6vw, 52px);
    display: grid; grid-template-columns: minmax(0, 5fr) minmax(0, 6fr);
    gap: clamp(26px, 4.4vw, 64px); align-items: center; min-height: 560px;
  }
  .cover-col { perspective: 900px; }
  .cover {
    position: relative; width: 100%; max-width: 460px; aspect-ratio: 1; margin: 0 auto;
    border-radius: 30px; overflow: hidden;
    background: linear-gradient(135deg, var(--a1), var(--a3));
    box-shadow: 0 50px 90px -28px color-mix(in srgb, var(--a1) 70%, #000), 0 18px 40px -16px rgba(0, 0, 0, .5);
    transform: scale(.93) rotateX(var(--rx, 0deg)) rotateY(var(--ry, 0deg));
    transition: transform .7s var(--ease), box-shadow .7s var(--ease), filter .7s;
    filter: saturate(.8);
  }
  .stage.playing .cover { transform: scale(1) rotateX(var(--rx, 0deg)) rotateY(var(--ry, 0deg)); filter: none; }
  .cover.tilting { transition: transform .12s linear, box-shadow .7s var(--ease), filter .7s; }
  .cover::after { content: ""; position: absolute; inset: 0; border-radius: inherit; pointer-events: none;
    background: linear-gradient(135deg, rgba(255,255,255,.30), rgba(255,255,255,0) 42%); box-shadow: inset 0 0 0 1px rgba(255,255,255,.16); }
  .cover img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .cover .fallback { position: absolute; inset: 0; display: grid; place-items: center; color: var(--on-a1); opacity: .75; }
  .cover .fallback svg { width: 34%; height: 34%; fill: none; stroke: currentColor; stroke-width: 1.4; stroke-linecap: round; stroke-linejoin: round; }

  .info { display: flex; flex-direction: column; gap: 28px; min-width: 0; }
  .head { display: flex; flex-direction: column; gap: 10px; min-width: 0; }
  .chip { display: inline-flex; align-items: center; gap: 10px; align-self: flex-start; height: 34px; padding: 0 14px 0 12px; border-radius: 999px;
    font-size: 14px; font-weight: 600; color: var(--fg2); background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft); max-width: 100%; }
  .chip .name { min-width: 0; }
  .chip .state { color: var(--fg3); font-weight: 500; white-space: nowrap; }
  .eq { display: inline-flex; align-items: flex-end; gap: 2px; height: 14px; flex: none; }
  .eq i { width: 3px; height: 100%; border-radius: 2px; background: var(--a1); transform-origin: bottom; transform: scaleY(.28); }
  .stage.playing .eq i { animation: eq 1s ease-in-out infinite; }
  .stage.playing .eq i:nth-child(2) { animation-delay: -.45s; }
  .stage.playing .eq i:nth-child(3) { animation-delay: -.2s; animation-duration: 1.2s; }
  .stage.playing .eq i:nth-child(4) { animation-delay: -.7s; }
  @keyframes eq { 0%, 100% { transform: scaleY(.28); } 50% { transform: scaleY(1); } }

  h1.title { margin: 6px 0 0; font-size: clamp(30px, 3.5vw, 54px); line-height: 1.14; font-weight: 800; letter-spacing: -.02em; min-width: 0; }
  .artist { margin: 0; font-size: clamp(17px, 1.5vw, 22px); font-weight: 600; color: var(--fg2); min-width: 0; }
  .album { margin: 0; font-size: 15px; color: var(--fg3); min-width: 0; }

  /* 切歌時的演出：封面淡入、文字由下方浮現 */
  .stage.swap .cover img, .stage.swap .cover .fallback { animation: coverIn .9s var(--ease) both; }
  .stage.swap .head > * { animation: textIn .7s var(--ease) both; }
  .stage.swap .head > *:nth-child(2) { animation-delay: .05s; }
  .stage.swap .head > *:nth-child(3) { animation-delay: .1s; }
  .stage.swap .head > *:nth-child(4) { animation-delay: .15s; }
  @keyframes coverIn { from { opacity: 0; transform: scale(1.08); filter: blur(14px); } to { opacity: 1; transform: none; filter: none; } }
  @keyframes textIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }

  /* 進度 */
  .seek { display: flex; flex-direction: column; gap: 4px; max-width: 520px; }
  .bar { position: relative; height: 26px; display: flex; align-items: center; cursor: pointer; touch-action: none; }
  .bar.soft { cursor: default; opacity: .55; }
  .track { position: relative; width: 100%; height: 6px; border-radius: 999px; background: var(--track); overflow: hidden; transition: height .18s var(--ease); }
  .bar:hover .track, .bar.drag .track { height: 10px; }
  .fill { position: absolute; inset: 0; transform-origin: left; transform: scaleX(0); background: linear-gradient(90deg, var(--a2), var(--a1)); border-radius: inherit; }
  .knob { position: absolute; top: 50%; left: 0; width: 16px; height: 16px; margin: -8px 0 0 -8px; border-radius: 50%; background: #fff;
    box-shadow: 0 2px 10px rgba(0, 0, 0, .35); transform: scale(0); transition: transform .18s var(--ease); pointer-events: none; }
  .bar:hover .knob, .bar.drag .knob, .bar:focus-visible .knob { transform: scale(1); }
  .bar.soft .knob { display: none; }
  .tip { position: absolute; bottom: 24px; left: 0; padding: 4px 9px; border-radius: 9px; font-size: 12px; font-weight: 600;
    background: rgba(12, 13, 18, .82); color: #fff; transform: translateX(-50%); pointer-events: none; opacity: 0; transition: opacity .15s; font-variant-numeric: tabular-nums; }
  .bar:hover .tip, .bar.drag .tip { opacity: 1; }
  .times { display: flex; justify-content: space-between; font-size: 13px; font-weight: 600; color: var(--fg3); font-variant-numeric: tabular-nums; }

  /* 播放控制 */
  .transport { display: flex; align-items: center; justify-content: space-between; max-width: 520px; }
  .transport .ib { width: 52px; height: 52px; }
  .transport .ib > span { width: 28px; height: 28px; }
  .transport .ib.seek10 > span { width: 30px; height: 30px; }
  .flip svg { transform: scaleX(-1); }
  .play { width: 84px !important; height: 84px !important; border-radius: 50%; display: grid; place-items: center; color: var(--on-a1);
    background: linear-gradient(135deg, var(--a1), color-mix(in srgb, var(--a1) 70%, var(--a2)));
    box-shadow: 0 18px 44px -10px var(--a1), inset 0 1px 0 rgba(255, 255, 255, .35); transition: transform .2s var(--ease), box-shadow .3s; }
  .play:hover { background: linear-gradient(135deg, var(--a1), color-mix(in srgb, var(--a1) 70%, var(--a2))); transform: scale(1.05); }
  .play > span { width: 36px !important; height: 36px !important; }

  /* 空狀態 */
  .empty { display: none; grid-column: 1 / -1; flex-direction: column; align-items: center; text-align: center; gap: 14px; padding: 40px 20px; }
  .is-empty .empty { display: flex; }
  .is-empty .cover-col, .is-empty .info { display: none; }
  .is-empty .stage { grid-template-columns: 1fr; }
  .empty .orb { width: 112px; height: 112px; border-radius: 50%; display: grid; place-items: center; color: var(--a1); margin-bottom: 10px;
    background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft), 0 24px 60px -20px var(--a1); }
  .empty .orb svg { width: 46px; height: 46px; fill: none; stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; }
  .empty h2 { margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -.01em; }
  .empty p { margin: 0; max-width: 420px; line-height: 1.75; color: var(--fg2); font-size: 16px; }

  /* ---------- 右側欄 ---------- */
  .rail { display: flex; flex-direction: column; gap: 18px; min-width: 0; }
  .panel { border-radius: 32px; padding: 22px; }
  .panel.sources { flex: 1; display: flex; flex-direction: column; min-height: 0; }
  .panel h2 { margin: 0; font-size: 18px; font-weight: 800; }
  .panel-head { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 16px; min-height: 34px; }
  .count { font-size: 13px; font-weight: 700; color: var(--fg2); background: var(--glass-2); border-radius: 999px; padding: 4px 11px; box-shadow: inset 0 0 0 1px var(--rim-soft); }
  .auto { height: 32px; padding: 0 12px; border-radius: 999px; font-size: 13px; font-weight: 700; color: var(--on-a1); background: var(--a1); transition: transform .2s var(--ease); }
  .auto:active { transform: scale(.95); }
  .sources-list { display: flex; flex-direction: column; gap: 8px; overflow-y: auto; margin: 0 -6px; padding: 0 6px 6px; }
  .src { position: relative; display: grid; grid-template-columns: 56px minmax(0, 1fr) auto; align-items: center; gap: 14px; width: 100%; text-align: left;
    padding: 10px 14px 10px 10px; border-radius: 20px; background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft); overflow: hidden;
    transition: background .2s, box-shadow .2s, transform .2s var(--ease); }
  .src:hover { background: var(--glass-3); }
  .src:active { transform: scale(.985); }
  .src.sel { box-shadow: inset 0 0 0 1.5px var(--a1); background: var(--glass-3); }
  .src .thumb { width: 56px; height: 56px; border-radius: 14px; overflow: hidden; display: grid; place-items: center; color: var(--on-a1);
    background: linear-gradient(135deg, var(--a1), var(--a3)); }
  .src .thumb img { width: 100%; height: 100%; object-fit: cover; }
  .src .thumb svg { width: 24px; height: 24px; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
  .src .meta { min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .src .meta b { font-size: 15px; font-weight: 700; min-width: 0; }
  .src .meta span { font-size: 13px; color: var(--fg3); min-width: 0; }
  .src .st { width: 18px; height: 18px; color: var(--fg3); }
  .src .st .eq { height: 16px; }
  .src .st.is-play .eq i { animation: eq 1s ease-in-out infinite; }
  .src .st.is-play .eq i:nth-child(2) { animation-delay: -.45s; }
  .src .st.is-play .eq i:nth-child(3) { animation-delay: -.2s; }
  .src .st svg { width: 16px; height: 16px; }
  .src .mini { position: absolute; left: 0; right: 0; bottom: 0; height: 3px; background: transparent; }
  .src .mini i { display: block; height: 100%; background: var(--a1); transform-origin: left; transform: scaleX(0); opacity: .9; }
  .rail-empty { margin: 8px 0; text-align: center; color: var(--fg3); font-size: 14px; line-height: 1.7; }

  .rows { display: flex; flex-direction: column; margin-top: 6px; }
  .row { display: flex; justify-content: space-between; align-items: center; padding: 11px 0; font-size: 14px; color: var(--fg2); }
  .row + .row { border-top: 1px solid var(--rim-soft); }
  .row b { font-weight: 700; color: var(--fg); font-variant-numeric: tabular-nums; }
  .row .ok { color: #3ddc97; } .row .no { color: #f3b43f; }
  :root[data-theme="light"] .row .ok { color: #0f9d63; } :root[data-theme="light"] .row .no { color: #b36b00; }

  .keys { display: flex; flex-wrap: wrap; justify-content: center; gap: 8px 22px; margin-top: 22px; font-size: 13px; color: var(--fg3); }
  .keys span { display: inline-flex; align-items: center; gap: 8px; }
  kbd { font: 600 12px/1 var(--font); min-width: 26px; height: 26px; padding: 0 8px; display: inline-grid; place-items: center; border-radius: 8px; color: var(--fg2);
    background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft), 0 2px 0 var(--rim-soft); }

  /* ---------- 登入 ---------- */
  .login { position: fixed; inset: 0; z-index: 10; display: none; place-items: center; padding: 20px; background: rgba(8, 9, 12, .45);
    -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); }
  .login.show { display: grid; }
  .login .card { width: min(420px, 100%); border-radius: 36px; padding: 34px; display: flex; flex-direction: column; gap: 14px; background: var(--card); }
  .login .lock { width: 56px; height: 56px; border-radius: 18px; display: grid; place-items: center; color: var(--on-a1); background: linear-gradient(135deg, var(--a1), var(--a2)); box-shadow: 0 14px 34px -10px var(--a1); }
  .login .lock svg { width: 26px; height: 26px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .login h2 { margin: 8px 0 0; font-size: 26px; font-weight: 800; }
  .login p { margin: 0; line-height: 1.7; color: var(--fg2); font-size: 15px; }
  .login input { width: 100%; height: 52px; padding: 0 18px; border-radius: 16px; border: 0; font: inherit; font-size: 16px; color: var(--fg);
    background: var(--glass-2); box-shadow: inset 0 0 0 1px var(--rim-soft); outline: none; }
  .login input:focus { box-shadow: inset 0 0 0 2px var(--a1); }
  .login .err { min-height: 20px; font-size: 14px; color: var(--err); font-weight: 600; }
  .login .go { height: 52px; border-radius: 16px; font-size: 16px; font-weight: 800; color: var(--on-a1); background: var(--a1); transition: transform .2s var(--ease), opacity .2s; }
  .login .go:active { transform: scale(.98); }
  .login .go:disabled { opacity: .6; cursor: wait; }

  .toast { position: fixed; left: 50%; bottom: 28px; z-index: 20; transform: translate(-50%, 20px); opacity: 0; pointer-events: none; max-width: calc(100% - 32px);
    padding: 12px 20px; border-radius: 999px; font-size: 14px; font-weight: 600; color: #fff; background: rgba(14, 15, 20, .88);
    -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); transition: opacity .25s, transform .35s var(--ease); }
  .toast.show { opacity: 1; transform: translate(-50%, 0); }
  .toast.err { background: rgba(140, 30, 40, .92); }

  /* ---------- 響應式 ---------- */
  @media (max-width: 1060px) {
    .layout { grid-template-columns: 1fr; }
    .panel.sources { flex: none; }
    .sources-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); overflow: visible; }
    .rail { gap: 18px; }
  }
  @media (max-width: 720px) {
    .app { padding-top: 14px; }
    .stage { grid-template-columns: 1fr; border-radius: 32px; padding: 22px; gap: 26px; min-height: 0; }
    .cover { max-width: 340px; border-radius: 26px; }
    .conn b { display: none; }
    .conn { padding: 0 12px; }
    .transport .ib { width: 46px; height: 46px; }
    .play { width: 76px !important; height: 76px !important; }
    .keys { display: none; }
    .panel { border-radius: 26px; padding: 18px; }
  }
  @media (hover: none) { .keys { display: none; } }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { animation: none !important; transition-duration: .01ms !important; }
  }
</style>
</head>
<body class="is-empty">
  <div class="scene" aria-hidden="true">
    <div class="bg" id="bgA"></div>
    <div class="bg" id="bgB"></div>
    <div class="blob one"></div>
    <div class="blob two"></div>
    <div class="veil"></div>
    <div class="grain"></div>
  </div>

  <div class="app" id="app">
    <header class="top">
      <div class="brand">
        <span class="mark"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="9" width="2.6" height="6" rx="1.3"/><rect x="7.6" y="5" width="2.6" height="14" rx="1.3"/><rect x="12.2" y="7.5" width="2.6" height="9" rx="1.3"/><rect x="16.8" y="3.5" width="2.6" height="17" rx="1.3"/></svg></span>
        <span>大便媒體控制</span>
      </div>
      <div class="top-actions">
        <span class="conn" id="conn" data-state="connecting" role="status"><i></i><b id="connText">連線中</b></span>
        <button class="ib round" id="themeBtn" type="button" title="切換主題" aria-label="切換主題"><span data-icon="auto"></span></button>
        <button class="ib round" id="copyBtn" type="button" title="複製網址" aria-label="複製網址"><span data-icon="link"></span></button>
      </div>
    </header>

    <main class="layout">
      <section class="stage glass" id="stage" aria-label="現正播放">
        <div class="empty" id="empty">
          <div class="orb"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 18V5l11-2v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/></svg></div>
          <h2 id="emptyTitle">現在沒有播放中的內容</h2>
          <p id="emptyText">在手機上用任何音樂或影片 App 開始播放，這裡會自動出現。</p>
        </div>

        <div class="cover-col">
          <div class="cover" id="cover">
            <div class="fallback" id="coverFb"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 18V5l11-2v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/></svg></div>
            <img id="coverImg" alt="專輯封面" hidden />
          </div>
        </div>

        <div class="info">
          <div class="head">
            <div class="chip"><span class="eq" aria-hidden="true"><i></i><i></i><i></i><i></i></span><span class="name" id="appName">-</span><span class="state" id="stateText" hidden>已暫停</span></div>
            <h1 class="title" id="title">-</h1>
            <p class="artist" id="artist"></p>
            <p class="album" id="album"></p>
          </div>

          <div class="seek">
            <div class="bar progress" id="bar" role="slider" tabindex="0" aria-label="播放進度" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" title="點一下跳轉播放位置">
              <div class="track"><div class="fill" id="fill"></div></div>
              <div class="knob" id="knob"></div>
              <div class="tip" id="tip">0:00</div>
            </div>
            <div class="times"><span id="tNow">0:00</span><span id="tEnd">--:--</span></div>
          </div>

          <div class="transport">
            <button class="ib seek10" id="bBack" type="button" title="倒轉 10 秒" aria-label="倒轉 10 秒"><span data-icon="back10"></span></button>
            <button class="ib" id="bPrev" type="button" title="上一首" aria-label="上一首"><span data-icon="prev"></span></button>
            <button class="ib play" id="bPlay" type="button" title="播放" aria-label="播放"><span id="playIcon" data-icon="play"></span></button>
            <button class="ib flip" id="bNext" type="button" title="下一首" aria-label="下一首"><span data-icon="prev"></span></button>
            <button class="ib seek10" id="bFwd" type="button" title="快轉 10 秒" aria-label="快轉 10 秒"><span data-icon="fwd10"></span></button>
          </div>
        </div>
      </section>

      <aside class="rail">
        <section class="panel glass sources" aria-label="播放來源">
          <div class="panel-head">
            <h2>播放來源</h2>
            <span style="display:flex;gap:8px;align-items:center">
              <button class="auto" id="autoBtn" type="button" hidden>跟隨播放中</button>
              <span class="count" id="count">0 個</span>
            </span>
          </div>
          <div class="sources-list" id="sources"></div>
          <p class="rail-empty" id="railEmpty">還沒有 App 在播放。</p>
        </section>
        <section class="panel glass" aria-label="連線狀態">
          <div class="panel-head" style="margin-bottom:0"><h2>狀態</h2></div>
          <div class="rows">
            <div class="row"><span>通知存取</span><b id="stListener">-</b></div>
            <div class="row"><span>更新方式</span><b id="stMode">-</b></div>
            <div class="row"><span>最後更新</span><b id="stTime">--:--:--</b></div>
          </div>
        </section>
      </aside>
    </main>

    <footer class="keys">
      <span><kbd>空白鍵</kbd>播放 / 暫停</span>
      <span><kbd>←</kbd><kbd>→</kbd>倒轉 / 快轉 10 秒</span>
      <span><kbd>Shift</kbd>+<kbd>←</kbd><kbd>→</kbd>上一首 / 下一首</span>
    </footer>
  </div>

  <!-- 需要密碼時顯示的登入面板 -->
  <div class="login" id="authPanel" role="dialog" aria-modal="true" aria-labelledby="authTitle">
    <form class="card glass" id="authForm" autocomplete="off">
      <div class="lock"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4.5" y="10.5" width="15" height="10" rx="3"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/></svg></div>
      <h2 id="authTitle">需要密碼</h2>
      <p>這台手機的 Web UI 已設定密碼。請輸入手機 App「設定」裡的密碼。</p>
      <input type="password" id="authInput" placeholder="輸入密碼" autocomplete="current-password" aria-label="密碼" />
      <div class="err" id="authErr" role="alert"></div>
      <button class="go" id="authBtn" type="submit">登入</button>
    </form>
  </div>
  <div class="toast" id="toast" role="status"></div>

<script>
'use strict';
/* 由伺服器在提供頁面時填入：'sse'（即時推送）或 'polling'（每秒輪詢）。
   這個值來自手機 App「設定」裡的「Web UI 更新方式」。 */
const UPDATE_MODE = '__UPDATE_MODE__';
/* 加上 ?demo 可以不連手機、用假資料預覽整個介面。 */
const DEMO = /[?&]demo(=|&|$)/.test(location.search);
/* 用相對於目前網址的路徑呼叫 API，這樣 /<密碼>/ 前綴的網址也能運作。 */
const BASE = location.pathname.endsWith('/') ? location.pathname : location.pathname + '/';

const $ = (id) => document.getElementById(id);
const root = document.documentElement;

/* ---------- 圖示 ---------- */
const ICONS = {
  play: '<path d="M8 5.14v13.72a1 1 0 0 0 1.52.85l11.04-6.86a1 1 0 0 0 0-1.7L9.52 4.29A1 1 0 0 0 8 5.14z"/>',
  pause: '<rect x="6" y="4.5" width="4.2" height="15" rx="1.4"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1.4"/>',
  prev: '<path d="M6 5.5a1 1 0 0 1 2 0v5.2l9.6-5.55A1 1 0 0 1 19 6v12a1 1 0 0 1-1.4.87L8 13.3v5.2a1 1 0 0 1-2 0z"/>',
  back10: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12a8 8 0 1 0 2.6-5.9"/><path d="M4 4.2v4.2h4.2"/></g><text x="12" y="15.3" font-size="7.4" font-weight="700" text-anchor="middle" fill="currentColor">10</text>',
  fwd10: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4.2v4.2h-4.2"/></g><text x="12" y="15.3" font-size="7.4" font-weight="700" text-anchor="middle" fill="currentColor">10</text>',
  link: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3A4 4 0 0 0 11 18.7l1-1"/></g>',
  auto: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.2"/></g><path d="M12 3.8a8.2 8.2 0 0 1 0 16.4z"/>',
  light: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2.8v2M12 19.2v2M2.8 12h2M19.2 12h2M5.5 5.5l1.4 1.4M17.1 17.1l1.4 1.4M5.5 18.5l1.4-1.4M17.1 6.9l1.4-1.4"/></g>',
  dark: '<path d="M20.2 14.3A8.4 8.4 0 0 1 9.7 3.8a.6.6 0 0 0-.8-.7A9.3 9.3 0 1 0 20.9 15.1a.6.6 0 0 0-.7-.8z"/>',
  note: '<path d="M9 18V5l11-2v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/>',
  pausedSm: '<rect x="6" y="5" width="4" height="14" rx="1.3"/><rect x="14" y="5" width="4" height="14" rx="1.3"/>',
};
function setIcon(el, name) {
  el.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + ICONS[name] + '</svg>';
  el.dataset.icon = name;
}
document.querySelectorAll('[data-icon]').forEach((el) => setIcon(el, el.dataset.icon));

/* ---------- 工具 ---------- */
function fmt(ms) {
  if (!ms || ms < 0) ms = 0;
  const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  const rr = String(r).padStart(2, '0');
  return h > 0 ? h + ':' + String(m).padStart(2, '0') + ':' + rr : m + ':' + rr;
}
function hash(str) { let h = 0; for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) | 0; return Math.abs(h); }
function setText(el, v) { if (el.textContent !== v) el.textContent = v; }

/* ---------- 跑馬燈：文字比容器寬時來回滾動 ---------- */
const mqPending = new Set();
let mqRaf = 0;
function scheduleMarquee(el) {
  mqPending.add(el);
  if (!mqRaf) mqRaf = requestAnimationFrame(flushMarquee);
}
function flushMarquee() {
  mqRaf = 0;
  mqPending.forEach((el) => measureMarquee(el));
  mqPending.clear();
}
function measureMarquee(el) {
  const inner = el.querySelector('.mq-inner');
  if (!inner) return;
  const avail = el.clientWidth;
  if (!avail) return; // 元素被隱藏時先略過，等下次可見再量
  const over = inner.scrollWidth - avail;
  const cur = Number(el.dataset.over || 0);
  if (Math.abs(over - cur) < 1) return;
  el.dataset.over = String(over);
  if (over > 6) {
    el.style.setProperty('--mq-x', '-' + over + 'px');
    el.style.setProperty('--mq-dur', Math.max(4, Math.min(18, over / 30)) + 's');
    el.classList.remove('on');
    void el.offsetWidth; // 讓動畫從頭開始
    el.classList.add('on');
  } else {
    el.classList.remove('on');
    el.style.removeProperty('--mq-x');
    el.style.removeProperty('--mq-dur');
  }
}
function setMarqueeText(el, text) {
  let inner = el.firstElementChild;
  if (!inner || !inner.classList.contains('mq-inner')) {
    inner = document.createElement('span');
    inner.className = 'mq-inner';
    while (el.firstChild) inner.appendChild(el.firstChild);
    el.appendChild(inner);
    el.classList.add('mq');
  }
  if (inner.textContent !== text) {
    inner.textContent = text;
    delete el.dataset.over;
    el.classList.remove('on');
  }
  scheduleMarquee(el);
}
addEventListener('resize', () => {
  document.querySelectorAll('.mq').forEach((el) => {
    delete el.dataset.over;
    el.classList.remove('on');
    scheduleMarquee(el);
  });
});

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, l = (mx + mn) / 2;
  let h = 0, s = 0;
  if (d > 0) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  return [h, s, l];
}
function hslToRgb(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  let r = 0, g = 0, b = 0;
  if (h < 60) { r = c; g = x; } else if (h < 120) { r = x; g = c; } else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
function luminance(rgb) {
  const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2]);
}
const rgbCss = (c) => 'rgb(' + c[0] + ',' + c[1] + ',' + c[2] + ')';

let toastTimer = 0;
function toast(msg, kind) {
  const t = $('toast');
  t.textContent = msg;
  t.className = 'toast show' + (kind ? ' ' + kind : '');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.className = 'toast'; }, 2600);
}

/* ---------- 狀態 ---------- */
const S = {
  snap: null, active: null, pinned: null,
  trackKey: '', artKey: '', palette: null, bgFlip: false,
  clocks: {}, hold: null, dragging: false, lastSec: -1,
  themeMode: 'auto', conn: '', lastAt: 0, loginShown: false,
};
const IDLE_PALETTE = { c1: { h: 200, s: 0.34, l: 0.5 }, c2: { h: 262, s: 0.3, l: 0.5 } };

/* ---------- 主題 ---------- */
const THEME_NAME = { auto: '跟隨系統', light: '淺色', dark: '深色' };
function resolveTheme() {
  return S.themeMode === 'auto' ? (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark') : S.themeMode;
}
function applyTheme() {
  root.dataset.theme = resolveTheme();
  const btn = $('themeBtn');
  setIcon(btn.firstElementChild, S.themeMode);
  btn.title = '主題：' + THEME_NAME[S.themeMode] + '（點一下切換）';
  if (S.palette) applyPalette(S.palette);
}
try { S.themeMode = localStorage.getItem('mc-theme') || 'auto'; } catch (e) { /* 無痕模式可能不能存 */ }
if (!THEME_NAME[S.themeMode]) S.themeMode = 'auto';
$('themeBtn').addEventListener('click', () => {
  const order = ['auto', 'light', 'dark'];
  S.themeMode = order[(order.indexOf(S.themeMode) + 1) % order.length];
  try { localStorage.setItem('mc-theme', S.themeMode); } catch (e) { /* ignore */ }
  applyTheme();
  toast('主題：' + THEME_NAME[S.themeMode]);
});
matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => { if (S.themeMode === 'auto') applyTheme(); });

/* ---------- 封面抽色 ---------- */
function extractPalette(url) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      try {
        const N = 40, cv = document.createElement('canvas');
        cv.width = cv.height = N;
        const g = cv.getContext('2d', { willReadFrequently: true });
        g.drawImage(img, 0, 0, N, N);
        const d = g.getImageData(0, 0, N, N).data;
        const B = 24, bins = [];
        for (let i = 0; i < B; i++) bins.push({ w: 0, s: 0, l: 0, hx: 0, hy: 0 });
        for (let i = 0; i < d.length; i += 4) {
          if (d[i + 3] < 128) continue;
          const p = rgbToHsl(d[i], d[i + 1], d[i + 2]);
          const w = p[1] * (1 - Math.abs(2 * p[2] - 1)) + 0.02;
          const b = bins[Math.floor(p[0] / 360 * B) % B];
          b.w += w; b.s += p[1] * w; b.l += p[2] * w;
          b.hx += Math.cos(p[0] * Math.PI / 180) * w; b.hy += Math.sin(p[0] * Math.PI / 180) * w;
        }
        const out = bins.filter((b) => b.w > 0).sort((a, b) => b.w - a.w).map((b) => {
          let h = Math.atan2(b.hy, b.hx) * 180 / Math.PI; if (h < 0) h += 360;
          return { h: h, s: b.s / b.w, l: b.l / b.w, w: b.w };
        });
        if (!out.length) { resolve(null); return; }
        const c1 = out[0];
        let c2 = out.find((c) => {
          const dh = Math.abs(((c.h - c1.h + 540) % 360) - 180);
          return (180 - dh) >= 50 && c.w >= c1.w * 0.12;
        });
        if (!c2) c2 = { h: (c1.h + 38) % 360, s: c1.s, l: c1.l };
        resolve({ c1: c1, c2: c2 });
      } catch (e) { resolve(null); }
    };
    img.onerror = () => resolve(null);
    img.src = url;
  });
}
function applyPalette(p) {
  S.palette = p;
  const light = root.dataset.theme === 'light';
  const mk = (c, ld, ll) => {
    const s = c.s < 0.15 ? c.s : Math.max(0.42, Math.min(0.88, c.s));
    return hslToRgb(c.h, s, light ? ll : ld);
  };
  const a1 = mk(p.c1, 0.64, 0.45), a2 = mk(p.c2, 0.58, 0.5);
  const a3 = hslToRgb(p.c1.h, Math.min(0.6, p.c1.s), light ? 0.8 : 0.22);
  root.style.setProperty('--a1', rgbCss(a1));
  root.style.setProperty('--a2', rgbCss(a2));
  root.style.setProperty('--a3', rgbCss(a3));
  root.style.setProperty('--on-a1', luminance(a1) > 0.32 ? '#0e1016' : '#ffffff');
}
function setBackdrop(url) {
  const next = S.bgFlip ? $('bgA') : $('bgB'), prev = S.bgFlip ? $('bgB') : $('bgA');
  S.bgFlip = !S.bgFlip;
  if (url) { next.style.backgroundImage = 'url("' + url + '")'; next.classList.add('on'); }
  else next.classList.remove('on');
  prev.classList.remove('on');
}
async function syncArt(a) {
  const art = a.artworkDataUrl || '';
  const key = a.packageName + '|' + (art ? art.length + ':' + art.slice(-40) : 'none:' + a.title);
  if (key === S.artKey) return;
  S.artKey = key;
  const myKey = key;
  let pal = null;
  if (art) pal = await extractPalette(art);
  if (S.artKey !== myKey) return;
  if (!pal) {
    const h = hash(a.appName + a.title) % 360;
    pal = { c1: { h: h, s: 0.5, l: 0.5 }, c2: { h: (h + 48) % 360, s: 0.5, l: 0.5 } };
  }
  applyPalette(pal);
  setBackdrop(art || null);
}

/* ---------- 播放時鐘：在兩次更新之間順順地往前走 ---------- */
function updateClock(s) {
  const now = performance.now();
  const key = s.title + '|' + s.artist + '|' + s.durationMs;
  let c = S.clocks[s.packageName];
  if (!c || c.key !== key) {
    S.clocks[s.packageName] = { key: key, base: s.positionMs, at: now, reported: s.positionMs, playing: s.isPlaying };
    return;
  }
  if (S.hold && S.hold.pkg === s.packageName && now < S.hold.until) { c.playing = s.isPlaying; return; }
  if (!s.isPlaying) { c.base = s.positionMs; c.at = now; c.playing = false; c.reported = s.positionMs; return; }
  /* Android 回報的進度只有在 App 更新播放狀態時才會變；
     位置沒變就繼續自己往前算，變了才用伺服器的值校正。 */
  if (s.positionMs !== c.reported || !c.playing) {
    c.reported = s.positionMs; c.base = s.positionMs; c.at = now; c.playing = true;
  }
}
function clockPos(s) {
  const c = S.clocks[s.packageName];
  if (!c) return s.positionMs;
  const now = performance.now();
  let p = c.base + (c.playing ? now - c.at : 0);
  if (s.durationMs > 0) p = Math.min(p, s.durationMs);
  return Math.max(0, p);
}

/* ---------- 畫面 ---------- */
function pickActive(list) {
  if (S.pinned) {
    const p = list.find((x) => x.packageName === S.pinned);
    if (p) return p;
    S.pinned = null;
  }
  return list.find((x) => x.isPlaying) || list[0] || null;
}

function onSnapshot(snap) {
  S.snap = snap; S.lastAt = Date.now();
  hideLogin();
  (snap.sessions || []).forEach(updateClock);
  render();
}

function render() {
  const snap = S.snap; if (!snap) return;
  const list = snap.sessions || [];
  const a = pickActive(list);
  S.active = a;
  document.body.classList.toggle('is-empty', !a);
  renderStage(a, snap);
  renderRail(list, a);
  renderStatus(snap);
}

function renderStage(a, snap) {
  const stage = $('stage');
  if (!a) {
    const noPerm = !snap.listenerEnabled;
    setText($('emptyTitle'), noPerm ? '需要通知存取權限' : '現在沒有播放中的內容');
    setText($('emptyText'), noPerm
      ? '到手機的「設定」找到「通知存取」，開啟「大便媒體控制」，這裡才看得到其他 App 正在播放的內容。'
      : '在手機上用任何音樂或影片 App 開始播放，這裡會自動出現。');
    stage.classList.remove('playing');
    if (S.artKey !== 'idle') { S.artKey = 'idle'; S.trackKey = ''; applyPalette(IDLE_PALETTE); setBackdrop(null); }
    setText(document.querySelector('title'), '大便媒體控制');
    return;
  }

  const tk = a.packageName + '|' + a.title + '|' + a.artist + '|' + a.durationMs;
  if (tk !== S.trackKey) {
    const first = S.trackKey === '';
    S.trackKey = tk;
    if (!first) {
      stage.classList.remove('swap'); void stage.offsetWidth; stage.classList.add('swap');
      setTimeout(() => stage.classList.remove('swap'), 1000);
    }
  }

  setMarqueeText($('appName'), a.appName);
  setMarqueeText($('title'), a.title);
  const artist = a.artist || a.album || '未知演出者';
  setMarqueeText($('artist'), artist);
  setMarqueeText($('album'), a.artist && a.album ? a.album : '');
  $('album').hidden = !(a.artist && a.album);
  $('stateText').hidden = a.isPlaying;
  stage.classList.toggle('playing', !!a.isPlaying);

  const img = $('coverImg');
  if (a.artworkDataUrl) {
    if (img.dataset.src !== a.artworkDataUrl) { img.dataset.src = a.artworkDataUrl; img.src = a.artworkDataUrl; }
    img.hidden = false; $('coverFb').hidden = true;
  } else {
    img.hidden = true; img.removeAttribute('src'); img.dataset.src = ''; $('coverFb').hidden = false;
  }
  syncArt(a);

  setIcon($('playIcon'), a.isPlaying ? 'pause' : 'play');
  $('bPlay').title = a.isPlaying ? '暫停' : '播放';
  $('bPlay').setAttribute('aria-label', a.isPlaying ? '暫停' : '播放');
  $('bPlay').classList.toggle('soft', a.isPlaying ? !a.canPause : !a.canPlay);
  $('bPrev').classList.toggle('soft', !a.canSkipPrevious);
  $('bNext').classList.toggle('soft', !a.canSkipNext);
  $('bBack').classList.toggle('soft', !a.canSeekTo);
  $('bFwd').classList.toggle('soft', !a.canSeekTo);
  $('bar').classList.toggle('soft', !a.canSeekTo || a.durationMs <= 0);
  setText(document.querySelector('title'), a.title + ' - 大便媒體控制');
}

function makeSrc(pkg) {
  const b = document.createElement('button');
  b.type = 'button'; b.className = 'src'; b.dataset.pkg = pkg;
  b.innerHTML = '<span class="thumb"></span><span class="meta"><b></b><span></span></span><span class="st"></span><span class="mini"><i></i></span>';
  b.addEventListener('click', () => {
    S.pinned = pkg;
    S.trackKey = ''; // 換來源時不要播放切歌動畫
    render();
  });
  return b;
}

function renderRail(list, active) {
  const box = $('sources');
  const have = {};
  Array.prototype.forEach.call(box.children, (c) => { have[c.dataset.pkg] = c; });
  const wanted = [];
  list.forEach((s) => {
    let el = have[s.packageName];
    if (!el) el = makeSrc(s.packageName);
    wanted.push(el);
    el.title = s.packageName;
    el.classList.toggle('sel', !!active && s.packageName === active.packageName);
    el.setAttribute('aria-pressed', el.classList.contains('sel') ? 'true' : 'false');
    const meta = el.querySelector('.meta');
    setMarqueeText(meta.children[0], s.title);
    setMarqueeText(meta.children[1], s.appName + (s.artist ? ' / ' + s.artist : ''));
    const th = el.querySelector('.thumb');
    if (s.artworkDataUrl) {
      let im = th.querySelector('img');
      if (!im) { th.innerHTML = ''; im = document.createElement('img'); im.alt = ''; th.appendChild(im); }
      if (im.dataset.src !== s.artworkDataUrl) { im.dataset.src = s.artworkDataUrl; im.src = s.artworkDataUrl; }
    } else if (!th.querySelector('svg')) {
      th.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + ICONS.note + '</svg>';
    }
    const st = el.querySelector('.st');
    const want = s.isPlaying ? 'play' : 'pause';
    if (st.dataset.k !== want) {
      st.dataset.k = want;
      st.className = 'st' + (s.isPlaying ? ' is-play' : '');
      st.innerHTML = s.isPlaying
        ? '<span class="eq" aria-label="播放中"><i></i><i></i><i></i><i></i></span>'
        : '<svg viewBox="0 0 24 24" aria-label="已暫停">' + ICONS.pausedSm + '</svg>';
    }
  });
  const cur = Array.prototype.slice.call(box.children);
  const same = cur.length === wanted.length && cur.every((c, i) => c === wanted[i]);
  if (!same) {
    cur.forEach((c) => { if (wanted.indexOf(c) < 0) box.removeChild(c); });
    wanted.forEach((c) => box.appendChild(c));
  }
  setText($('count'), list.length + ' 個');
  $('railEmpty').hidden = list.length > 0;
  $('autoBtn').hidden = !S.pinned;
}

function renderStatus(snap) {
  const l = $('stListener');
  l.textContent = snap.listenerEnabled ? '已開啟' : '尚未開啟';
  l.className = snap.listenerEnabled ? 'ok' : 'no';
  setText($('stMode'), DEMO ? '示範資料' : (S.conn === 'live' ? '即時推送' : '每秒輪詢'));
  const d = new Date(S.lastAt);
  setText($('stTime'), [d.getHours(), d.getMinutes(), d.getSeconds()].map((n) => String(n).padStart(2, '0')).join(':'));
}

/* ---------- 進度條動畫迴圈 ---------- */
function tick() {
  requestAnimationFrame(tick);
  const a = S.active; if (!a) return;
  const dur = a.durationMs;
  if (!S.dragging) {
    const pos = clockPos(a);
    const f = dur > 0 ? Math.max(0, Math.min(1, pos / dur)) : 0;
    $('fill').style.transform = 'scaleX(' + f + ')';
    $('knob').style.left = (f * 100) + '%';
    const sec = Math.floor(pos / 1000);
    if (sec !== S.lastSec) {
      S.lastSec = sec;
      setText($('tNow'), fmt(pos));
      $('bar').setAttribute('aria-valuenow', String(Math.round(f * 100)));
    }
  }
  setText($('tEnd'), dur > 0 ? fmt(dur) : '--:--');
  const items = $('sources').children;
  const list = (S.snap && S.snap.sessions) || [];
  for (let i = 0; i < items.length; i++) {
    const s = list.find((x) => x.packageName === items[i].dataset.pkg);
    if (!s) continue;
    const f = s.durationMs > 0 ? clockPos(s) / s.durationMs : 0;
    items[i].querySelector('.mini i').style.transform = 'scaleX(' + Math.max(0, Math.min(1, f)) + ')';
  }
}

/* ---------- 控制 ---------- */
async function control(action, payload) {
  if (DEMO) { demo.control(action, payload); return; }
  const r = await fetch(BASE + 'api/control/' + action, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload || {}),
  });
  if (r.status === 401) { showLogin(); throw new Error('401'); }
  if (!r.ok) {
    let msg = 'HTTP ' + r.status;
    try { const j = await r.json(); if (j.error) msg = j.error; } catch (e) { /* ignore */ }
    throw new Error(msg);
  }
}
async function act(action, extra) {
  const a = S.active; if (!a) return;
  try {
    await control(action, Object.assign({ packageName: a.packageName }, extra || {}));
    await pull();
  } catch (e) {
    if (e.message !== '401') toast('指令沒有送出：' + e.message, 'err');
  }
}
function seekTo(ms) {
  const a = S.active; if (!a || a.durationMs <= 0) return;
  ms = Math.max(0, Math.min(a.durationMs - 300, Math.round(ms)));
  const c = S.clocks[a.packageName];
  if (c) { c.base = ms; c.at = performance.now(); }
  S.hold = { pkg: a.packageName, until: performance.now() + 1800 };
  act('seek', { positionMs: ms });
}
const seekBy = (delta) => { const a = S.active; if (a) seekTo(clockPos(a) + delta); };
const togglePlay = () => { const a = S.active; if (a) act(a.isPlaying ? 'pause' : 'play'); };

$('bPlay').addEventListener('click', togglePlay);
$('bPrev').addEventListener('click', () => act('previous'));
$('bNext').addEventListener('click', () => act('next'));
$('bBack').addEventListener('click', () => seekBy(-10000));
$('bFwd').addEventListener('click', () => seekBy(10000));
$('autoBtn').addEventListener('click', () => { S.pinned = null; S.trackKey = ''; render(); });

/* 進度條：點一下或拖曳來跳轉 */
(function () {
  const bar = $('bar');
  const frac = (e) => { const r = bar.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); };
  const showAt = (f) => {
    const a = S.active; if (!a) return;
    $('tip').style.left = (f * 100) + '%';
    setText($('tip'), fmt(f * a.durationMs));
  };
  bar.addEventListener('pointerdown', (e) => {
    const a = S.active; if (!a || a.durationMs <= 0) return;
    S.dragging = true; bar.classList.add('drag'); bar.setPointerCapture(e.pointerId);
    const f = frac(e); showAt(f);
    $('fill').style.transform = 'scaleX(' + f + ')'; $('knob').style.left = (f * 100) + '%';
    setText($('tNow'), fmt(f * a.durationMs));
  });
  bar.addEventListener('pointermove', (e) => {
    const a = S.active; if (!a || a.durationMs <= 0) return;
    const f = frac(e); showAt(f);
    if (S.dragging) {
      $('fill').style.transform = 'scaleX(' + f + ')'; $('knob').style.left = (f * 100) + '%';
      setText($('tNow'), fmt(f * a.durationMs));
    }
  });
  const end = (e) => {
    if (!S.dragging) return;
    S.dragging = false; bar.classList.remove('drag');
    const a = S.active; if (a) seekTo(frac(e) * a.durationMs);
  };
  bar.addEventListener('pointerup', end);
  bar.addEventListener('pointercancel', () => { S.dragging = false; bar.classList.remove('drag'); });
})();

/* 封面跟著滑鼠輕微傾斜（只在有滑鼠的裝置上） */
(function () {
  if (!matchMedia('(hover: hover)').matches || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const cv = $('cover');
  cv.addEventListener('pointermove', (e) => {
    const r = cv.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
    cv.classList.add('tilting');
    cv.style.setProperty('--ry', (x * 9).toFixed(2) + 'deg');
    cv.style.setProperty('--rx', (-y * 9).toFixed(2) + 'deg');
  });
  cv.addEventListener('pointerleave', () => {
    cv.classList.remove('tilting');
    cv.style.setProperty('--ry', '0deg'); cv.style.setProperty('--rx', '0deg');
  });
})();

/* 鍵盤快捷鍵 */
document.addEventListener('keydown', (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (S.loginShown || e.target.closest('input, textarea')) return;
  const onButton = !!e.target.closest('button');
  if (e.key === ' ') { if (onButton) return; e.preventDefault(); togglePlay(); }
  else if (e.key === 'ArrowLeft') { e.preventDefault(); e.shiftKey ? act('previous') : seekBy(-10000); }
  else if (e.key === 'ArrowRight') { e.preventDefault(); e.shiftKey ? act('next') : seekBy(10000); }
});

$('copyBtn').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(location.href); toast('已複製網址'); }
  catch (e) { toast('這個瀏覽器不能自動複製，請直接從網址列複製', 'err'); }
});

/* ---------- 登入 ---------- */
function showLogin() {
  S.loginShown = true; stopLive();
  $('authPanel').classList.add('show');
  $('app').setAttribute('inert', '');
  setTimeout(() => $('authInput').focus(), 50);
}
function hideLogin() {
  if (!S.loginShown) return;
  S.loginShown = false; $('authPanel').classList.remove('show'); $('app').removeAttribute('inert');
}
$('authForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const token = $('authInput').value.trim();
  if (!token) { $('authErr').textContent = '請輸入密碼'; return; }
  /* 密碼用網址前綴帶入（/<密碼>/），之後所有的 API 與 SSE 請求都會沿用。 */
  const target = location.origin + '/' + encodeURIComponent(token) + '/';
  $('authBtn').disabled = true; $('authErr').textContent = '';
  try {
    const r = await fetch(target + 'api/auth/check', { cache: 'no-store' });
    if (r.status === 401) { $('authErr').textContent = '密碼不正確，請再試一次'; $('authBtn').disabled = false; return; }
  } catch (err) { /* 連不上時照樣導向，讓瀏覽器顯示實際錯誤 */ }
  location.href = target;
});

/* ---------- 連線 ---------- */
const CONN_TEXT = { connecting: '連線中', live: '即時連線', poll: '每秒更新', offline: '連線中斷', demo: '示範模式' };
function setConn(state) {
  if (S.conn === state) return;
  const was = S.conn; S.conn = state;
  const el = $('conn');
  el.dataset.state = state === 'demo' ? 'live' : state;
  setText($('connText'), CONN_TEXT[state]);
  el.title = CONN_TEXT[state];
  if (state === 'offline') toast('連不上手機，正在重試。請確認手機仍在同一個網路', 'err');
  else if (was === 'offline') toast('已重新連線');
  if (S.snap) renderStatus(S.snap);
}
let es = null, pollTimer = 0, retryTimer = 0;
async function pull() {
  if (DEMO) { onSnapshot(demo.snapshot()); return true; }
  try {
    const r = await fetch(BASE + 'api/state', { cache: 'no-store' });
    if (r.status === 401) { showLogin(); return false; }
    if (!r.ok) throw new Error('HTTP ' + r.status);
    onSnapshot(await r.json());
    if (!es) setConn('poll');
    return true;
  } catch (e) { setConn('offline'); return false; }
}
function startPolling() { if (!pollTimer) pollTimer = setInterval(pull, 1000); }
function stopPolling() { clearInterval(pollTimer); pollTimer = 0; }
function stopLive() {
  stopPolling(); clearTimeout(retryTimer);
  if (es) { es.close(); es = null; }
}
function connectSSE() {
  if (typeof EventSource === 'undefined') { startPolling(); return; }
  try {
    es = new EventSource(BASE + 'api/events');
    es.onmessage = (ev) => {
      try { onSnapshot(JSON.parse(ev.data)); stopPolling(); setConn('live'); }
      catch (err) { console.error('SSE 訊息解析失敗', err); }
    };
    es.onerror = () => {
      if (es) { es.close(); es = null; }
      startPolling(); pull();
      clearTimeout(retryTimer); retryTimer = setTimeout(connectSSE, 5000);
    };
  } catch (err) { startPolling(); }
}
document.addEventListener('visibilitychange', () => { if (!document.hidden && !S.loginShown) pull(); });

/* ---------- 示範資料（?demo） ---------- */
const demo = (function () {
  function art(h1, h2, h3, kind) {
    const shapes = kind === 0
      ? '<circle cx="268" cy="150" r="84" fill="hsl(' + h3 + ' 90% 70%)" opacity=".92"/><path d="M0 262 Q100 222 200 262 T400 262 V400 H0Z" fill="hsl(' + h2 + ' 60% 18%)" opacity=".72"/><path d="M0 312 Q100 276 200 312 T400 312 V400 H0Z" fill="hsl(' + h2 + ' 60% 12%)" opacity=".8"/>'
      : kind === 1
        ? '<circle cx="150" cy="170" r="110" fill="hsl(' + h3 + ' 85% 62%)" opacity=".85"/><circle cx="250" cy="230" r="90" fill="hsl(' + h1 + ' 80% 70%)" opacity=".6"/><rect x="0" y="330" width="400" height="70" fill="hsl(' + h2 + ' 50% 14%)" opacity=".7"/>'
        : '<rect x="60" y="60" width="280" height="280" rx="40" fill="hsl(' + h3 + ' 80% 66%)" opacity=".85"/><circle cx="200" cy="200" r="70" fill="hsl(' + h2 + ' 60% 20%)" opacity=".8"/>';
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(' + h1 + ' 70% 56%)"/><stop offset="1" stop-color="hsl(' + h2 + ' 65% 28%)"/></linearGradient></defs><rect width="400" height="400" fill="url(#g)"/>' + shapes + '</svg>';
    return 'data:image/svg+xml;base64,' + btoa(svg);
  }
  const pool = [
    { title: '慢速海岸線', artist: '潮間帶樂團', album: '退潮之前', dur: 228000, art: art(18, 330, 42, 0) },
    { title: '午夜的窗', artist: '深藍俱樂部', album: '城市低語', dur: 251000, art: art(215, 262, 330, 1) },
    { title: '把月亮留在樓頂', artist: '林曉', album: '夏末', dur: 196000, art: art(150, 190, 60, 2) },
  ];
  let idx = 0;
  const base = { canPlay: true, canPause: true, canSkipNext: true, canSkipPrevious: true, canSeekTo: true };
  const sessions = [
    Object.assign({}, base, { packageName: 'demo.music', appName: '音樂', playbackState: 'playing', isPlaying: true, positionMs: 74000 }),
    Object.assign({}, base, { packageName: 'demo.video', appName: '影片', title: '週末雜談 第 42 集', artist: '晚安廣播', album: '', durationMs: 2712000, positionMs: 905000, playbackState: 'paused', isPlaying: false, artworkDataUrl: art(32, 8, 48, 2) }),
  ];
  function sync() {
    const t = pool[idx];
    Object.assign(sessions[0], { title: t.title, artist: t.artist, album: t.album, durationMs: t.dur, artworkDataUrl: t.art });
  }
  sync();
  setInterval(() => { sessions.forEach((s) => { if (s.isPlaying) s.positionMs = Math.min(s.durationMs, s.positionMs + 1000); }); }, 1000);
  return {
    snapshot: () => JSON.parse(JSON.stringify({ listenerEnabled: true, timestampMs: Date.now(), sessions: sessions })),
    control(action, p) {
      const s = sessions.find((x) => x.packageName === p.packageName) || sessions[0];
      if (action === 'play') s.isPlaying = true;
      else if (action === 'pause') s.isPlaying = false;
      else if (action === 'seek') s.positionMs = p.positionMs;
      else if ((action === 'next' || action === 'previous') && s === sessions[0]) {
        idx = (idx + (action === 'next' ? 1 : pool.length - 1)) % pool.length; s.positionMs = 0; sync();
      }
      s.playbackState = s.isPlaying ? 'playing' : 'paused';
    },
  };
})();

/* ---------- 啟動 ---------- */
applyTheme();
applyPalette(IDLE_PALETTE);
requestAnimationFrame(tick);
if (DEMO) {
  setConn('demo');
  pull(); setInterval(pull, 1000);
} else {
  setConn('connecting');
  pull().then((ok) => {
    if (!ok && S.loginShown) return;
    if (UPDATE_MODE === 'polling') startPolling(); else connectSSE();
  });
}
</script>
</body>
</html>
'''
      .replaceAll(
        '__UPDATE_MODE__',
        updateMode == 'polling' ? 'polling' : 'sse',
      );
}