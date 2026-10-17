(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  const root = document.documentElement;
  const loaderBar = $(".loader-bar i");
  const progress = (p) => { if (loaderBar) loaderBar.style.setProperty("--p", p); };
  requestAnimationFrame(() => progress(0.3));
  if (document.fonts) document.fonts.ready.then(() => progress(0.65));
  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    const min = matchMedia("(prefers-reduced-motion: reduce)").matches ? 200 : 1300;
    setTimeout(() => {
      progress(1);
      setTimeout(() => {
        root.classList.add("ready");
        setTimeout(() => { const l = $(".loader"); if (l) l.remove(); }, 900);
      }, 450);
    }, Math.max(0, min - performance.now()));
  };
  if (document.readyState === "complete") finish();
  else addEventListener("load", finish);
  setTimeout(finish, 4500);

  const toastEl = $(".toast");
  let toastTimer;
  const toast = (msg) => {
    toastEl.textContent = msg;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove("show"), 1600);
  };

  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const wake = (v) => {
    if (!v.src) v.src = v.dataset.src;
    if (!still) v.play().catch(() => {});
  };
  const tiles = $$(".media video");
  if ("IntersectionObserver" in window) {
    const seen = new IntersectionObserver((entries) => {
      entries.forEach((e) => (e.isIntersecting ? wake(e.target) : e.target.pause()));
    }, { rootMargin: "200px" });
    tiles.forEach((v) => seen.observe(v));
  } else tiles.forEach(wake);

  const box = $(".lightbox");
  const player = $("video", box);
  $$("[data-full]").forEach((b) => b.addEventListener("click", () => {
    player.src = b.dataset.full;
    box.showModal();
    player.play().catch(() => {});
  }));
  const shut = () => { if (box.open) box.close(); };
  $(".close", box).addEventListener("click", shut);
  box.addEventListener("click", (e) => { if (e.target === box) shut(); });
  box.addEventListener("close", () => {
    player.pause();
    player.removeAttribute("src");
    player.load();
  });
  $$(".media, .lightbox video").forEach((el) => el.addEventListener("contextmenu", (e) => e.preventDefault()));

  const strips = $$(".section-art");
  if (strips.length && !still) {
    let queued = false;
    const drift = () => {
      queued = false;
      strips.forEach((d) => {
        const r = d.getBoundingClientRect();
        if (r.bottom < 0 || r.top > innerHeight) return;
        const p = (r.top + r.height / 2 - innerHeight / 2) / (innerHeight / 2 + r.height / 2);
        d.style.setProperty("--shift", (-p * r.height * 0.12).toFixed(1) + "px");
      });
    };
    addEventListener("scroll", () => {
      if (!queued) { queued = true; requestAnimationFrame(drift); }
    }, { passive: true });
    addEventListener("resize", drift);
    drift();
  }

  const title = $(".hero h1");
  if (title && !still) {
    let n = 0;
    const words = (node, extra) => [...node.childNodes].map((c) => {
      if (c.nodeType === 3) {
        return c.textContent.split(/(\s+)/).map((t) => (t.trim() ? `<span class="w${extra}"><span style="--i:${n++}">${t}</span></span>` : t)).join("");
      }
      if (c.nodeName === "BR") return "<br>";
      return words(c, `${extra} ${c.className}`);
    }).join("");
    title.innerHTML = words(title, "");
    title.classList.add("split");
  }

  const leafBox = $(".leaves");
  if (leafBox && !still) {
    const shape = '<svg viewBox="0 0 24 24"><path d="M12 1 13.3 4.8 15.8 3.6 15.2 7.6 19.6 5.4 18.4 9.6 22.6 10.4 19 13 20.4 15.2 15.4 14.8 16 18.2 12.6 16.2 12.5 22.8 11.5 22.8 11.4 16.2 8 18.2 8.6 14.8 3.6 15.2 5 13 1.4 10.4 5.6 9.6 4.4 5.4 8.8 7.6 8.2 3.6 10.7 4.8Z"/></svg>';
    const r = (a, b) => a + Math.random() * (b - a);
    for (let i = 0; i < 9; i++) {
      const leaf = document.createElement("i");
      leaf.className = "leaf";
      leaf.style.cssText = `left:${r(0, 100)}%;--s:${r(15, 30)}px;--dur:${r(11, 19)}s;--delay:${-r(0, 19)}s;--sway:${r(18, 60)}px;--spin:${(Math.random() < 0.5 ? -1 : 1) * r(180, 520)}deg;--o:${r(0.35, 0.8)}`;
      leaf.innerHTML = `<b>${shape}</b>`;
      leafBox.appendChild(leaf);
    }
    const fit = () => leafBox.style.setProperty("--h", leafBox.offsetHeight + 80 + "px");
    fit();
    addEventListener("resize", fit);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([e]) => leafBox.classList.toggle("paused", !e.isIntersecting)).observe(leafBox);
    }
  }

  if (!still && "IntersectionObserver" in window) {
    const reveal = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return;
        e.target.classList.add("in");
        reveal.unobserve(e.target);
      });
    }, { rootMargin: "0px 0px -6% 0px" });
    $$(".section-head > *, .item, .proj, .score, .quotes li, .price-group > .label, .price-row, .price-notes p, .contact-grid > div > *, .about, .sign").forEach((el) => {
      const i = [...el.parentElement.children].indexOf(el);
      el.style.setProperty("--d", Math.min(i, 5) * 0.08 + "s");
      el.classList.add("rv");
      reveal.observe(el);
    });
  }

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
      if (t.startsWith("--")) cls = "c";
      else if (t[0] === '"') cls = "s";
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

  const files = window.LUAU_FILES || {};
  const ROOT = { client: ["StarterPlayer", "StarterPlayerScripts", "Client"], server: ["ServerScriptService", "Server"], shared: ["ReplicatedStorage", "Shared"] };
  const info = (p) => {
    const parts = p.split("/"), file = parts.pop(), top = parts.shift();
    const type = file.endsWith(".client.lua") ? "LocalScript" : file.endsWith(".server.lua") ? "Script" : "ModuleScript";
    const name = file.replace(/(\.client|\.server)?\.lua$/, "");
    return { file, name, type, side: top, studio: [...ROOT[top], ...parts, name] };
  };
  const lines = (p) => (files[p] || "").split("\n").length;
  const copy = (text, msg) => {
    const done = () => toast(msg);
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, () => fallbackCopy(text, done));
    else fallbackCopy(text, done);
  };
  const fallbackCopy = (text, done) => {
    const ta = document.createElement("textarea");
    ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); } catch {}
    ta.remove(); done();
  };

  $$(".proj").forEach((proj) => {
    const btns = $$(".file", proj);
    const pre = $(".code pre", proj), crumb = $(".crumb", proj), meta = $(".code .meta", proj);
    let current = btns[0].dataset.path, rendered = false;
    const paths = btns.map((b) => b.dataset.path);
    const total = paths.reduce((n, p) => n + lines(p), 0);
    $("[data-stats]", proj).textContent = `${paths.length} files · ${total.toLocaleString("en-US")} lines`;
    $("[data-act=all]", proj).textContent = `Copy all ${paths.length} files`;
    btns.forEach((b) => {
      const i = info(b.dataset.path);
      b.dataset.side = i.side;
      $(".ty", b).textContent = `${i.type} · ${lines(b.dataset.path)}`;
      b.addEventListener("click", () => show(b.dataset.path));
    });
    const show = (p) => {
      current = p; rendered = true;
      const i = info(p);
      pre.innerHTML = render(files[p] || "");
      pre.scrollTop = 0; pre.scrollLeft = 0;
      crumb.innerHTML = i.studio.map((s, k) => k === i.studio.length - 1 ? `<b>${s}</b>` : `<span>${s}</span>`).join("<i>›</i>");
      meta.textContent = `${i.type} · ${lines(p)} lines`;
      meta.dataset.side = i.side;
      btns.forEach((b) => b.setAttribute("aria-current", String(b.dataset.path === p)));
    };
    $("[data-act=copy]", proj).addEventListener("click", () => copy(files[current] || "", info(current).name + " copied"));
    $("[data-act=dl]", proj).addEventListener("click", () => {
      const a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([files[current] || ""], { type: "text/plain" }));
      a.download = info(current).file;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    });
    $("[data-act=all]", proj).addEventListener("click", () => {
      const all = paths.map((p) => { const i = info(p); return `-- ${i.studio.join("/")} (${i.type})\n\n${files[p]}`; }).join("\n\n");
      copy(all, `${paths.length} files copied`);
    });
    const lazy = () => { if (!rendered) show(current); };
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) { io.disconnect(); lazy(); } }, { rootMargin: "600px" });
      io.observe(proj);
    } else lazy();
  });

  $$("[data-copy]").forEach((b) => b.addEventListener("click", () => {
    copy(b.dataset.copy, b.dataset.copy + " copied");
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
    $(".txt", musicBtn).textContent = on ? "Ambient on" : "Ambient off";
  });
})();
