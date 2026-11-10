String buildWebUiHtml({String updateMode = 'sse'}) {
  return r'''
<!doctype html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>大便媒體控制</title>
  <style>
    /* 定義全域 CSS 變數與色彩配置 */
    :root {
      color-scheme: dark;
      --bg: #07111d;
      --panel: rgba(14, 23, 39, 0.6);
      --panel-border: rgba(255, 255, 255, 0.1);
      --muted: rgba(226, 232, 240, 0.72);
      --accent: #5ce1e6;
      --accent-strong: #15c89a;
      --warning: #f59e0b;
      --shadow: 0 24px 80px rgba(0, 0, 0, 0.4);
      --glass-blur: blur(24px);
    }

    /* 基礎重置與排版設定 */
    * { 
      box-sizing: border-box; 
    }

    body {
      margin: 0;
      min-height: 100vh;
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(92, 225, 230, 0.15), transparent 30%),
        radial-gradient(circle at bottom right, rgba(21, 200, 154, 0.15), transparent 30%),
        linear-gradient(180deg, #08111f 0%, #0b1729 50%, #050b14 100%);
      color: white;
      -webkit-font-smoothing: antialiased;
    }

    .shell {
      width: min(1120px, calc(100% - 48px));
      margin: 0 auto;
      padding: 32px 0 64px;
    }

    /* 英雄區塊樣式（Hero Section） */
    .hero {
      border: 1px solid var(--panel-border);
      border-radius: 32px;
      padding: 40px;
      background: linear-gradient(135deg, rgba(20, 49, 73, 0.8), rgba(10, 20, 36, 0.9));
      box-shadow: var(--shadow);
      backdrop-filter: var(--glass-blur);
      position: relative;
      overflow: hidden;
    }

    /* 裝飾性標籤 */
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 16px;
      border-radius: 999px;
      border: 1px solid rgba(92, 225, 230, 0.3);
      background: rgba(92, 225, 230, 0.1);
      color: var(--accent);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.1em;
      text-transform: uppercase;
    }

    h1 {
      margin: 20px 0 16px;
      font-size: clamp(40px, 6vw, 72px);
      line-height: 1.1;
      letter-spacing: -0.03em;
      background: linear-gradient(to right, #fff, #a5b4fc);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .lede {
      max-width: 600px;
      margin: 0;
      color: var(--muted);
      font-size: 18px;
      line-height: 1.6;
    }

    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      margin-top: 32px;
    }

    /* 按鈕共用樣式 */
    button {
      appearance: none;
      border: 0;
      border-radius: 16px;
      padding: 14px 24px;
      font: inherit;
      font-size: 15px;
      font-weight: 600;
      color: white;
      cursor: pointer;
      transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    }

    button:hover { 
      transform: translateY(-2px); 
    }
    
    button:active {
      transform: translateY(0);
    }

    button:disabled { 
      opacity: 0.5; 
      cursor: not-allowed; 
      transform: none; 
    }

    .primary {
      background: linear-gradient(135deg, var(--accent), #3b82f6);
      box-shadow: 0 8px 24px rgba(59, 130, 246, 0.3);
      color: #000;
    }

    .primary:hover {
      box-shadow: 0 12px 32px rgba(59, 130, 246, 0.4);
    }

    .secondary {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.15);
    }

    .secondary:hover {
      background: rgba(255, 255, 255, 0.12);
    }

    /* 網格系統配置 */
    .grid {
      display: grid;
      grid-template-columns: repeat(12, minmax(0, 1fr));
      gap: 24px;
      margin-top: 24px;
    }

    /* 卡片模組化樣式 */
    .card {
      grid-column: span 12;
      border: 1px solid var(--panel-border);
      border-radius: 28px;
      background: var(--panel);
      backdrop-filter: var(--glass-blur);
      box-shadow: var(--shadow);
      padding: 28px;
      transition: transform 0.3s ease;
    }
    
    .card:hover {
      border-color: rgba(255, 255, 255, 0.2);
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-start;
      margin-bottom: 24px;
    }

    .title { 
      margin: 0; 
      font-size: 22px; 
      font-weight: 700; 
    }

    .subtitle { 
      margin: 8px 0 0; 
      color: var(--muted); 
      line-height: 1.5; 
      font-size: 14px;
    }

    /* 狀態標籤指示器 */
    .pill {
      border-radius: 999px;
      padding: 6px 14px;
      font-size: 13px;
      font-weight: 700;
      white-space: nowrap;
    }

    .pill.success { background: rgba(21, 200, 154, 0.15); color: var(--accent-strong); border: 1px solid rgba(21, 200, 154, 0.3); }
    .pill.warn { background: rgba(245, 158, 11, 0.15); color: var(--warning); border: 1px solid rgba(245, 158, 11, 0.3); }
    .pill.info { background: rgba(96, 165, 250, 0.15); color: #93c5fd; border: 1px solid rgba(96, 165, 250, 0.3); }

    /* 數據面板 */
    .meta {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap: 16px;
    }

    .metric {
      padding: 16px;
      border-radius: 20px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.08);
      transition: background 0.2s;
    }
    
    .metric:hover {
      background: rgba(255, 255, 255, 0.05);
    }

    .metric label {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
    }

    .metric strong { 
      font-size: 20px; 
      font-weight: 600;
    }

    .sessions { 
      display: grid; 
      gap: 16px; 
    }

    /* 媒體會話控制項 */
    .session {
      padding: 20px;
      border-radius: 24px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.08);
      transition: background 0.2s;
    }

    .session:hover {
      background: rgba(255, 255, 255, 0.05);
    }

    .session-top {
      display: flex;
      gap: 20px;
      justify-content: space-between;
      align-items: center;
    }

    /* 媒體封面圖片 */
    .now-cover {
      width: 96px;
      height: 96px;
      flex: 0 0 auto;
      border-radius: 20px;
      overflow: hidden;
      display: grid;
      place-items: center;
      font-size: 32px;
      color: rgba(255, 255, 255, 0.8);
      background: linear-gradient(135deg, rgba(92, 225, 230, 0.2), rgba(59, 130, 246, 0.2));
      border: 1px solid rgba(255, 255, 255, 0.1);
      box-shadow: 0 8px 16px rgba(0,0,0,0.2);
    }

    .now-cover.small {
      width: 72px;
      height: 72px;
      border-radius: 16px;
      font-size: 24px;
    }

    .now-cover img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .now-meta {
      flex: 1;
      min-width: 0;
    }

    .session h3 { 
      margin: 0; 
      font-size: 20px; 
      font-weight: 600;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    
    .session .artist { 
      margin: 8px 0 0; 
      color: var(--muted);
      font-size: 15px; 
    }
    
    .session .package, .session .timing { 
      margin: 6px 0 0; 
      color: rgba(255,255,255,0.4);
      font-size: 13px;
    }

    /* 播放進度條 */
    .progress {
      margin: 20px 0 12px;
      height: 8px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.08);
      overflow: hidden;
      cursor: pointer;
    }

    .progress:hover {
      height: 12px;
      margin-top: 18px;
    }

    /* 需要密碼時顯示的登入面板（平時隱藏） */
    .auth-panel {
      display: none;
      margin-top: 24px;
      padding: 20px;
      border-radius: 20px;
      border: 1px solid rgba(245, 158, 11, 0.4);
      background: rgba(245, 158, 11, 0.08);
    }

    .auth-panel input {
      width: 100%;
      box-sizing: border-box;
      margin: 12px 0;
      padding: 12px 16px;
      border-radius: 12px;
      border: 1px solid rgba(255, 255, 255, 0.2);
      background: rgba(0, 0, 0, 0.25);
      color: white;
      font: inherit;
    }

    .progress > div {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, var(--accent), #3b82f6);
      border-radius: inherit;
      transition: width 1s linear;
      box-shadow: 0 0 10px rgba(92, 225, 230, 0.5);
    }

    .controls {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 20px;
    }
    
    .controls button {
      padding: 10px 20px;
      font-size: 14px;
    }

    .danger {
      color: #fecaca;
      background: rgba(251, 113, 133, 0.15);
      border: 1px solid rgba(251, 113, 133, 0.3);
      padding: 16px 20px;
      border-radius: 16px;
      margin-top: 24px;
      display: none;
      font-weight: 500;
    }

    .hint { 
      color: var(--muted); 
      line-height: 1.6; 
      font-size: 15px;
    }

    /* 響應式佈局調整 */
    @media (max-width: 640px) {
      .shell {
        width: calc(100% - 32px);
        padding: 20px 0 48px;
      }
      .hero { padding: 24px; border-radius: 24px; }
      .card { padding: 20px; border-radius: 20px; }
      .session-top { flex-wrap: wrap; }
      .now-cover { width: 72px; height: 72px; border-radius: 16px; }
      .controls button { flex: 1 1 auto; }
    }

    @media (min-width: 860px) {
      .span-7 { grid-column: span 7; }
      .span-5 { grid-column: span 5; }
      .span-4 { grid-column: span 4; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <div class="eyebrow">LOCAL</div>
      <h1>大便媒體遙控</h1>
      <p class="lede">
        即時讀取您的 Android 媒體進程，優雅地顯示歌曲資訊與播放進度。並提供播放、暫停、切換曲目等遠端控制指令。
      </p>
      <div class="toolbar">
        <button class="primary" id="refreshBtn">重刷媒體狀態</button>
        <button class="secondary" id="copyBtn">複製控制網址</button>
      </div>
      <div class="danger" id="errorBox"></div>
      <div class="auth-panel" id="authPanel">
        <strong>需要密碼</strong>
        <p class="hint" style="margin: 8px 0 0;">這台手機的 Web UI 已設定密碼。請輸入手機 App「設定」裡的密碼，密碼只會存在這次瀏覽的網址裡，不會傳給其他地方。</p>
        <input type="password" id="authInput" placeholder="輸入 Web UI 密碼" autocomplete="current-password" />
        <button class="primary" id="authBtn">登入</button>
      </div>
    </section>

    <section class="grid" id="mainGrid">
      <article class="card span-7">
        <div class="card-header">
          <div>
            <h2 class="title">即時快照</h2>
            <p class="subtitle">狀態會即時推送；連線中斷時自動改為每秒輪詢。</p>
          </div>
          <div class="pill info" id="serverState">系統載入中</div>
        </div>
        <div class="meta" id="metrics"></div>
      </article>

      <article class="card span-5">
        <div class="card-header">
          <div>
            <h2 class="title">使用說明</h2>
            <p class="subtitle">就字面上的意思啊</p>
          </div>
        </div>
        <p class="hint">
          若未顯示任何媒體資訊，請至手機的系統設定內開啟此應用程式的「通知存取權限」。接著在裝置上開始播放音樂或影片，即可在此進行控制。
        </p>
        <p class="hint" id="urlHint" style="word-break: break-all; opacity: 0.7; font-family: monospace;"></p>
      </article>

      <article class="card span-12">
        <div class="card-header">
          <div>
            <h2 class="title">現正播放</h2>
            <p class="subtitle">此處顯示目前處於活躍狀態的最相關播放進程。</p>
          </div>
          <div class="pill success" id="sessionCount">0 個進程</div>
        </div>
        <div id="nowPlaying"></div>
      </article>

      <article class="card span-12">
        <div class="card-header">
          <div>
            <h2 class="title">活躍進程列表</h2>
            <p class="subtitle">可獨立控制各應用程式的背景播放進程（依據該應用程式開放之 API 權限而定）。</p>
          </div>
        </div>
        <div class="sessions" id="sessions"></div>
      </article>
    </section>
  </main>

  <script>
    /* 由伺服器在提供頁面時填入：'sse'（即時推送）或 'polling'（每秒輪詢）。
       這個值來自手機 App「設定」裡的「Web UI 更新方式」。 */
    const UPDATE_MODE = '__UPDATE_MODE__';

    /* 取得 DOM 節點參考 */
    const domNodes = {
      metrics: document.getElementById('metrics'),
      sessionsContainer: document.getElementById('sessions'),
      nowPlaying: document.getElementById('nowPlaying'),
      errorBox: document.getElementById('errorBox'),
      serverState: document.getElementById('serverState'),
      sessionCount: document.getElementById('sessionCount'),
      urlHint: document.getElementById('urlHint'),
      refreshBtn: document.getElementById('refreshBtn'),
      copyBtn: document.getElementById('copyBtn'),
      authPanel: document.getElementById('authPanel'),
      authInput: document.getElementById('authInput'),
      authBtn: document.getElementById('authBtn'),
      mainGrid: document.getElementById('mainGrid')
    };

    /* 需要密碼時顯示登入面板，並把主要內容藏起來，直到登入為止。 */
    function showAuthPrompt() {
      domNodes.authPanel.style.display = 'block';
      domNodes.mainGrid.style.display = 'none';
      domNodes.authInput.focus();
    }

    function loginWithPassword() {
      const token = domNodes.authInput.value.trim();
      if (!token) return;
      /* 密碼用網址前綴帶入（/<密碼>/），之後所有的 API 與 SSE 請求
         都會沿用這個前綴，不需要再另外輸入。 */
      window.location.href = window.location.origin + '/' + encodeURIComponent(token) + '/';
    }

    domNodes.authBtn.addEventListener('click', loginWithPassword);
    domNodes.authInput.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') loginWithPassword();
    });

    /**
     * 將毫秒轉換為 MM:SS 格式的字串
     * @param {number} ms - 毫秒數
     * @returns {string} 格式化後的時間字串
     */
    function formatTime(ms) {
      if (!ms || ms <= 0) {
        return '--:--';
      }
      const totalSeconds = Math.floor(ms / 1000);
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    }

    /**
     * 跳脫 HTML 特殊字元以防止 XSS 攻擊
     * @param {string} value - 原始字串
     * @returns {string} 跳脫後的安全字串
     */
    function escapeHtml(value) {
      if (!value) return '';
      return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    /**
     * 發送控制指令至後端 API
     * @param {string} action - 控制動作 (play, pause, next, previous)
     * @param {Object} payload - 附帶資料，通常包含目標套件名稱
     */
    async function sendControl(action, payload = {}) {
      try {
        await fetch('api/control/' + action, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        await refresh();
      } catch (error) {
        console.error('API 控制請求失敗', error);
      }
    }

    /* 點進度條跳轉播放位置：用事件委派處理所有進程卡片。 */
    document.addEventListener('click', async (event) => {
      const bar = event.target.closest('.progress');
      if (!bar) return;
      const duration = Number(bar.dataset.duration || 0);
      if (duration <= 0) return;
      const rect = bar.getBoundingClientRect();
      const fraction = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
      await sendControl('seek', {
        packageName: bar.dataset.package,
        positionMs: Math.round(duration * fraction),
      });
    });

    /**
     * 渲染系統狀態數據區塊
     * @param {Object} snapshot - 後端回傳的狀態快照
     */
    function renderMetrics(snapshot) {
      const active = snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null;
      domNodes.metrics.innerHTML = `
        <div class="metric"><label>通知監聽器</label><strong>${snapshot.listenerEnabled ? '運作中' : '需設定權限'}</strong></div>
        <div class="metric"><label>活動進程數</label><strong>${snapshot.sessions.length}</strong></div>
        <div class="metric"><label>當前焦點</label><strong>${escapeHtml(active ? active.appName : '無')}</strong></div>
      `;
      
      domNodes.serverState.textContent = snapshot.listenerEnabled ? '系統權限已就緒' : '請啟用通知存取權限';
      domNodes.serverState.className = 'pill ' + (snapshot.listenerEnabled ? 'success' : 'warn');
      domNodes.sessionCount.textContent = snapshot.sessions.length + ' 個進程';
      domNodes.urlHint.textContent = window.location.href;
    }

    /**
     * 產生單一進程的 HTML 結構
     * @param {Object} session - 媒體進程資料
     * @param {boolean} isMain - 是否為主播放區塊
     * @returns {string} HTML 結構字串
     */
    function createSessionHTML(session, isMain = false) {
      const progress = session.durationMs > 0 
        ? Math.max(0, Math.min(100, (session.positionMs / session.durationMs) * 100)) 
        : 0;
        
      const coverClass = isMain ? 'now-cover' : 'now-cover small';
      
      return `
        <div class="session">
          <div class="session-top">
            <div class="${coverClass}">
              ${session.artworkDataUrl ? `<img src="${escapeHtml(session.artworkDataUrl)}" alt="Album Art">` : '<span>♪</span>'}
            </div>
            <div class="now-meta">
              <h3>${escapeHtml(isMain ? session.title : session.appName)}</h3>
              <div class="artist">${escapeHtml(isMain ? (session.artist || session.album || '未知演出者') : session.title)}</div>
              <div class="package">${escapeHtml(isMain ? `${session.appName} · ${session.packageName}` : (session.artist || session.album || '未知演出者'))}</div>
            </div>
            <div class="pill ${session.isPlaying ? 'success' : 'info'}">
              ${session.isPlaying ? '播放中' : (isMain ? '已暫停' : session.playbackState || '已暫停')}
            </div>
          </div>
          <div class="progress" title="點一下跳轉播放位置" data-package="${escapeHtml(session.packageName)}" data-duration="${session.durationMs}"><div style="width:${progress}%"></div></div>
          <div class="timing">${formatTime(session.positionMs)} / ${formatTime(session.durationMs)}</div>
          <div class="controls">
            <button class="secondary" onclick="sendControl('previous', { packageName: '${escapeHtml(session.packageName)}' })">上一首</button>
            <button class="primary" onclick="sendControl('${session.isPlaying ? 'pause' : 'play'}', { packageName: '${escapeHtml(session.packageName)}' })">${session.isPlaying ? '暫停' : '播放'}</button>
            <button class="secondary" onclick="sendControl('next', { packageName: '${escapeHtml(session.packageName)}' })">下一首</button>
          </div>
        </div>
      `;
    }

    /**
     * 渲染主播放區塊
     * @param {Object|null} session - 主要的媒體進程資料
     */
    function renderNowPlaying(session) {
      if (!session) {
        domNodes.nowPlaying.innerHTML = '<p class="hint">目前沒有進行中的媒體進程，請在裝置上開始播放內容。</p>';
        return;
      }
      domNodes.nowPlaying.innerHTML = createSessionHTML(session, true);
    }

    /**
     * 渲染所有活躍的進程列表
     * @param {Array} sessions - 所有的媒體進程陣列
     */
    function renderSessions(sessions) {
      if (!sessions || !sessions.length) {
        domNodes.sessionsContainer.innerHTML = '<p class="hint">查無其他進程。</p>';
        return;
      }
      domNodes.sessionsContainer.innerHTML = sessions.map(session => createSessionHTML(session, false)).join('');
    }

    /**
     * 狀態同步函式，向後端要求最新狀態並更新畫面
     */
    async function refresh() {
      try {
        const response = await fetch('api/state', { cache: 'no-store' });
        if (response.status === 401) {
          showAuthPrompt();
          return;
        }
        if (!response.ok) throw new Error('伺服器回應異常：' + response.status);
        
        const snapshot = await response.json();
        domNodes.errorBox.style.display = 'none';
        
        renderMetrics(snapshot);
        renderNowPlaying(snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null);
        renderSessions(snapshot.sessions);
      } catch (error) {
        domNodes.errorBox.textContent = '系統發生錯誤：' + String(error);
        domNodes.errorBox.style.display = 'block';
      }
    }

    /* 綁定事件監聽器 */
    domNodes.refreshBtn.addEventListener('click', refresh);
    
    domNodes.copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(window.location.href);
        domNodes.copyBtn.textContent = '已複製網址';
        setTimeout(() => domNodes.copyBtn.textContent = '複製控制網址', 2000);
      } catch (err) {
        console.error('複製失敗', err);
      }
    });

    /* 即時更新：優先用 SSE（/api/events）推送，失敗時改為每秒輪詢。
       注意：這裡用相對路徑 'api/...' 而不用 '/api/...'，是為了讓
       密碼前綴（/<密碼>/）的網址也能正常呼叫 API。 */
    let pollingTimer = null;
    function startPollingFallback() {
      if (pollingTimer === null) {
        pollingTimer = setInterval(refresh, 1000);
      }
    }
    function startLiveUpdates() {
      refresh();
      if (UPDATE_MODE === 'polling') {
        startPollingFallback();
        return;
      }
      if (typeof EventSource === 'undefined') {
        startPollingFallback();
        return;
      }
      try {
        const source = new EventSource('api/events');
        source.onmessage = (event) => {
          try {
            const snapshot = JSON.parse(event.data);
            domNodes.errorBox.style.display = 'none';
            renderMetrics(snapshot);
            renderNowPlaying(snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null);
            renderSessions(snapshot.sessions);
          } catch (error) {
            console.error('SSE 訊息解析失敗', error);
          }
        };
        source.onerror = () => {
          source.close();
          startPollingFallback();
        };
      } catch (error) {
        console.error('SSE 連線失敗，改用輪詢', error);
        startPollingFallback();
      }
    }
    startLiveUpdates();
  </script>
</body>
</html>
'''
      .replaceAll(
        '__UPDATE_MODE__',
        updateMode == 'polling' ? 'polling' : 'sse',
      );
}
