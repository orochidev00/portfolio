(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  const toastEl = $(".toast");
  let toastTimer;
  const toast = (msg) => {
    toastEl.textContent = msg;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove("show"), 1600);
  };

  $$(".video[data-yt]").forEach((box) => {
    const id = box.dataset.yt;
    const img = box.querySelector("img");
    if (img) {
      img.src = (window.__resources && window.__resources["yt_" + id]) || `https://img.youtube.com/vi/${id}/maxresdefault.jpg`;
      img.onerror = () => { img.onerror = null; img.src = `https://img.youtube.com/vi/${id}/hqdefault.jpg`; };
    }
    box.querySelector(".play").addEventListener("click", () => {
      box.innerHTML = `<iframe src="https://www.youtube.com/embed/${id}?autoplay=1&rel=0" title="${box.dataset.title || "Video"}" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>`;
    });
  });

  const KW = new Set("local function return if then else elseif end for while do in and or not repeat until break".split(" "));
  const LIT = new Set(["true", "false", "nil", "self"]);
  const BUILTIN = new Set("game workspace script Vector3 Vector2 CFrame Color3 Enum Instance TweenInfo RaycastParams math table task string os setmetatable require pcall warn print tostring typeof".split(" "));
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const TOKEN = /("(?:[^"\\]|\\.)*"|--.*$|\b\d+(?:\.\d+)?\b|[A-Za-z_][A-Za-z0-9_]*|\s+|.)/g;
  const highlightLine = (line) => {
    let out = "", prev = "";
    for (const m of line.matchAll(TOKEN)) {
      const t = m[0], rest = line.slice(m.index + t.length);
      let cls = "";
      if (t[0] === '"') cls = "s";
      else if (/^\d/.test(t)) cls = "n";
      else if (KW.has(t)) cls = "k";
      else if (LIT.has(t)) cls = "b";
      else if (BUILTIN.has(t)) cls = "t";
      else if (/^[A-Za-z_]/.test(t) && /^\s*\(/.test(rest)) cls = "f";
      out += cls ? `<span class="tk-${cls}">${esc(t)}</span>` : esc(t);
      if (t.trim()) prev = t;
    }
    return out;
  };
  const render = (src) => src.split("\n").map((l) => `<span class="l">${highlightLine(l) || " "}</span>`).join("");

  const sources = window.LUAU_SOURCES || {};
  const pre = $(".code pre");
  const fileEl = $(".code .file");
  const metaEl = $(".code .meta");
  let current = "monster_ai";
  const show = (key) => {
    const src = sources[key] || "";
    current = key;
    pre.innerHTML = render(src);
    pre.scrollTop = 0;
    fileEl.textContent = key + ".lua";
    metaEl.textContent = src.split("\n").length + " lines";
    $$(".tab").forEach((t) => t.setAttribute("aria-selected", String(t.dataset.file === key)));
  };
  $$(".tab").forEach((t) => {
    const n = (sources[t.dataset.file] || "").split("\n").length;
    const small = t.querySelector("[data-lines]");
    if (small) small.textContent = small.textContent.replace("{n}", n);
    t.addEventListener("click", () => show(t.dataset.file));
  });
  $$("[data-open-file]").forEach((a) => a.addEventListener("click", () => show(a.dataset.openFile)));
  $(".code-head button").addEventListener("click", () => {
    navigator.clipboard?.writeText(sources[current] || "");
    toast(current + ".lua copied");
  });
  const lazy = () => show(current);
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) { io.disconnect(); lazy(); } }, { rootMargin: "600px" });
    io.observe($("#source"));
  } else lazy();

  $$("[data-copy]").forEach((b) => b.addEventListener("click", () => {
    navigator.clipboard?.writeText(b.dataset.copy);
    toast(b.dataset.copy + " copied");
  }));

  const clock = $("[data-clock]");
  const tick = () => {
    clock.textContent = new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
  };
  tick();
  setInterval(tick, 30000);

  const audio = $("#lofi");
  const musicBtn = $(".music-btn");
  audio.volume = 0.35;
  musicBtn.addEventListener("click", async () => {
    if (audio.paused) {
      try { await audio.play(); } catch { return; }
    } else audio.pause();
    const on = !audio.paused;
    musicBtn.setAttribute("aria-pressed", String(on));
    musicBtn.textContent = on ? "♪ Ambient on" : "♪ Ambient off";
  });
})();
