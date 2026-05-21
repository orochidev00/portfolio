// MOVELIST — grid of move cards + modal with keyboard nav + VHS glitch

const { useState, useEffect, useRef, useMemo } = React;

// Lightweight Luau syntax highlighter for the placeholder snippets
const highlightLua = (code) => {
  const lines = code.split("\n");
  return lines.map((line, i) => {
    // Comments
    if (/^\s*--/.test(line)) {
      return <div key={i}><span className="cmt">{line}</span></div>;
    }
    // Process tokens
    const tokens = [];
    let rest = line;
    const push = (cls, text) => tokens.push(<span key={tokens.length} className={cls}>{text}</span>);
    while (rest.length) {
      // strings
      let m = rest.match(/^"[^"]*"/);
      if (m) { push("str", m[0]); rest = rest.slice(m[0].length); continue; }
      // keywords
      m = rest.match(/^\b(local|function|return|if|then|end|else|elseif|for|while|do|in|and|or|not|true|false|nil)\b/);
      if (m) { push("kw", m[0]); rest = rest.slice(m[0].length); continue; }
      // numbers
      m = rest.match(/^\b\d+\.?\d*\b/);
      if (m) { push("num", m[0]); rest = rest.slice(m[0].length); continue; }
      // function call name pattern :name( or .name(
      m = rest.match(/^[A-Za-z_][A-Za-z0-9_]*(?=\s*\()/);
      if (m) { push("fn", m[0]); rest = rest.slice(m[0].length); continue; }
      // word
      m = rest.match(/^[A-Za-z_][A-Za-z0-9_]*/);
      if (m) { push("", m[0]); rest = rest.slice(m[0].length); continue; }
      // single char
      push("", rest[0]); rest = rest.slice(1);
    }
    return <div key={i}>{tokens}</div>;
  });
};

const MoveCard = ({ move, onOpen }) => {
  const thumb = move.youtube ? `https://img.youtube.com/vi/${move.youtube}/maxresdefault.jpg` : null;
  const startup = move.frameData?.STARTUP?.v ?? "—";
  const damage = move.frameData?.DAMAGE?.v ?? move.frameData?.TYPE?.v ?? "—";
  const type = move.frameData?.TYPE?.v ?? "SPECIAL";

  return (
    <button
      className="move"
      onClick={onOpen}
      aria-label={`Open ${move.title} showcase`}
      type="button"
    >
      <div className="move-num">◆ {move.num} / 06</div>
      <div className="move-frame-data" aria-hidden="true">
        <span>STARTUP: {startup}</span>
        <span className="heavy">DMG: {damage}</span>
        <span>TYPE: {type}</span>
      </div>
      <div className="move-thumb">
        {thumb && (
          <img
            src={thumb}
            alt=""
            style={{
              position: "absolute", inset: 0, width: "100%", height: "100%",
              objectFit: "cover", opacity: 0.55,
              filter: "hue-rotate(60deg) saturate(0.9) contrast(1.05)",
            }}
            onError={(e) => { e.currentTarget.style.display = "none"; }}
          />
        )}
        <div className="move-thumb-stripes" />
        <div className="move-thumb-scan" />
        <div className="move-play" aria-hidden="true">▶</div>
        <div className="move-glitch" />
        <div className="move-thumb-meta">
          <span>{move.category}</span>
          <span>{move.year}</span>
        </div>
      </div>
      <div className="move-body">
        <div className="move-cat">MOVE {move.num}</div>
        <div className="move-title">{move.title}</div>
        <div className="move-tag-row">
          {move.tags.map((t) => (
            <span key={t.t} className={`move-tag ${t.k || ""}`}>{t.t}</span>
          ))}
        </div>
        <div className="move-press">▸ <strong>PRESS</strong> · OPEN MOVELIST ENTRY</div>
      </div>
    </button>
  );
};

const LockedPanel = ({ file }) => (
  <div className="code-locked" role="region" aria-label="Source code locked">
    <div className="code-locked-head">
      <span className="file">◇ {file}</span>
      <span className="lock-tag">✕ ACCESS DENIED</span>
    </div>
    <div className="code-locked-body">
      <div className="lock-glyph" aria-hidden="true">
        <div className="lock-shackle"></div>
        <div className="lock-box">█</div>
      </div>
      <div className="lock-text">
        <div className="lock-title">SOURCE&nbsp;·&nbsp;LOCKED</div>
        <div className="lock-sub">CLIENT NDA · COMMISSIONED WORK</div>
        <div className="lock-desc">
          Available on request after a signed NDA.
          DM on Discord <strong>@oroch1n</strong> to discuss.
        </div>
      </div>
    </div>
  </div>
);

const CodeBlock = ({ file, code }) => {
  const [collapsed, setCollapsed] = useState(false);
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard?.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };
  return (
    <div className="code-block">
      <div className="code-block-head">
        <span className="file">◇ {file}</span>
        <div style={{ display: "flex", gap: 6 }}>
          <button onClick={copy} type="button">{copied ? "✓ COPIED" : "⧉ COPY"}</button>
          <button onClick={() => setCollapsed(!collapsed)} type="button">
            {collapsed ? "▼ VIEW SOURCE" : "▲ HIDE"}
          </button>
        </div>
      </div>
      {!collapsed && (
        <pre className="code-block-body" aria-label={`Source code for ${file}`}>
          {highlightLua(code)}
        </pre>
      )}
    </div>
  );
};

const MoveModal = ({ moves, index, setIndex, onClose, onToast }) => {
  const [glitching, setGlitching] = useState(false);
  const [playing, setPlaying] = useState(false);
  const move = moves[index];

  const go = (newIdx) => {
    if (newIdx < 0 || newIdx >= moves.length || newIdx === index) return;
    setGlitching(true);
    setPlaying(false);
    setIndex(newIdx);
    setTimeout(() => setGlitching(false), 240);
  };

  // Keyboard nav
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "Escape") { onClose(); }
      else if (e.key === "ArrowRight") { go(index + 1); }
      else if (e.key === "ArrowLeft")  { go(index - 1); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [index]);

  // Reset video state on showcase change
  useEffect(() => { setPlaying(false); }, [move.id]);

  const thumb = move.youtube ? `https://img.youtube.com/vi/${move.youtube}/maxresdefault.jpg` : null;

  return (
    <div
      className="modal-backdrop"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
      role="dialog"
      aria-modal="true"
      aria-label={`${move.title} movelist entry`}
    >
      <div className={`modal ${glitching ? "glitching" : ""}`}>
        <div className="modal-head">
          <div className="who">
            <span className="num">◆ {move.num} / 06</span>
            <span className="name">{move.title}</span>
          </div>
          <div className="right">
            <span style={{ color: "var(--cyan)" }}>{move.category} · {move.year}</span>
            <button
              className="modal-nav-btn"
              onClick={() => go(index - 1)}
              disabled={index === 0}
              aria-label="Previous showcase"
              type="button"
            >◀ PREV</button>
            <span style={{ color: "var(--yellow)" }}>{move.num} / 06</span>
            <button
              className="modal-nav-btn"
              onClick={() => go(index + 1)}
              disabled={index === moves.length - 1}
              aria-label="Next showcase"
              type="button"
            >NEXT ▶</button>
            <button
              className="modal-close"
              onClick={onClose}
              aria-label="Close"
              type="button"
            >✕ CLOSE</button>
          </div>
        </div>

        <div className="modal-body">
          <div className="modal-left">
            <div className="modal-video">
              {!move.youtube && (
                <div className="placeholder">
                  <a
                    href={move.twitter}
                    target="_blank" rel="noreferrer"
                    className="play"
                    aria-label={`Watch ${move.title} on X/Twitter`}
                    onClick={(e) => e.stopPropagation()}
                    style={{ textDecoration: "none" }}
                  >▶</a>
                </div>
              )}
              {move.youtube && !playing && (
                <button
                  type="button"
                  onClick={() => setPlaying(true)}
                  aria-label={`Play ${move.title} video`}
                  style={{
                    position: "absolute", inset: 0, border: 0, padding: 0, cursor: "pointer",
                    backgroundImage: thumb ? `url(${thumb})` : "none",
                    backgroundSize: "cover", backgroundPosition: "center",
                  }}
                >
                  <span style={{
                    position: "absolute", top: "50%", left: "50%", transform: "translate(-50%,-50%)",
                    width: 72, height: 72, borderRadius: "50%",
                    background: "var(--neon)", color: "var(--bg-deep)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 28, boxShadow: "0 0 32px var(--neon-glow)",
                  }}>▶</span>
                </button>
              )}
              {move.youtube && playing && (
                <iframe
                  src={`https://www.youtube.com/embed/${move.youtube}?autoplay=1&rel=0`}
                  title={move.title}
                  allow="autoplay; encrypted-media; picture-in-picture"
                  allowFullScreen
                />
              )}
            </div>

            <div className="modal-frame-data" aria-label="Frame data">
              {Object.entries(move.frameData).map(([k, val]) => (
                <div key={k} className={`fd ${val.k || ""}`}>
                  <span className="k">{k}</span>
                  <span className="v">{val.v}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="modal-right">
            <div className="modal-tagline">{move.tagline}</div>
            <ul className="modal-feats">
              {move.features.map((f, i) => (
                <li key={i}>{f}</li>
              ))}
            </ul>
            {move.locked
              ? <LockedPanel file={move.file} />
              : <CodeBlock file={move.file} code={move.code} />}
          </div>
        </div>

        <div className="modal-footer">
          <span>
            <kbd>←</kbd> <kbd>→</kbd> CYCLE  ·  <kbd>ESC</kbd> CLOSE  ·  <kbd>TAB</kbd> NAVIGATE
          </span>
          <span>
            EXIT TO MOVELIST
          </span>
        </div>
      </div>
    </div>
  );
};

const Movelist = ({ onToast }) => {
  const [openIdx, setOpenIdx] = useState(null);
  const moves = window.SHOWCASES;

  useEffect(() => {
    if (openIdx !== null) {
      const prev = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      return () => { document.body.style.overflow = prev; };
    }
  }, [openIdx]);

  return (
    <section className="section" id="movelist">
      <div className="section-head">
        <div>
          <div className="section-kicker">▸ MOVELIST · 06 ENTRIES</div>
          <h2 className="section-title">M<span className="o">O</span>VELIST</h2>
        </div>
        <div className="section-meta">
          SELECT MOVE WITH MOUSE OR TAB<br />
          PRESS Z / ENTER / CLICK TO OPEN
        </div>
      </div>

      <div className="movelist" role="list">
        {moves.map((m, i) => (
          <div role="listitem" key={m.id}>
            <MoveCard move={m} onOpen={() => setOpenIdx(i)} />
          </div>
        ))}
      </div>

      {openIdx !== null && (
        <MoveModal
          moves={moves}
          index={openIdx}
          setIndex={setOpenIdx}
          onClose={() => setOpenIdx(null)}
          onToast={onToast}
        />
      )}
    </section>
  );
};

window.Movelist = Movelist;
