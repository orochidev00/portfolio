// SECTIONS — Pricing, Replay Log (testimonials), Contact, Ticker

const { useState, useEffect } = React;

const DISCORD_URL = "https://discord.com/users/oroch1n";

const PricingBlock = ({ kicker, title, items }) => (
  <div style={{ marginTop: 20 }}>
    <div style={{
      display: "flex", alignItems: "baseline", gap: 14, marginBottom: 14,
      borderBottom: "1px dashed rgba(255,255,255,0.1)", paddingBottom: 8,
    }}>
      <span style={{
        color: "var(--cyan)", fontSize: 10, letterSpacing: "0.25em",
      }}>▸ {kicker}</span>
      <h3 style={{
        fontFamily: "var(--font-display)", fontWeight: 400,
        fontSize: 32, letterSpacing: "0.04em", color: "var(--ink)",
        textShadow: "2px 2px 0 var(--neon)",
      }}>{title}</h3>
    </div>
    <div className="pricing-grid">
      {items.map((p) => (
        <div key={p.tier} className={`pricing-card ${p.hot ? "hot" : ""}`}>
          {p.hot && <div className="flag">MOST REQUESTED</div>}
          <div className="tier">{p.tier}</div>
          <div className="price">{p.price}</div>
          <div style={{ color: "var(--ink-mute)", fontSize: 11, letterSpacing: "0.15em" }}>{p.rbx}</div>
          <div className="desc">{p.desc}</div>
          <div className="ex"><em>e.g.</em> {p.ex}</div>
        </div>
      ))}
    </div>
  </div>
);

const Pricing = () => (
  <section className="section" id="pricing">
    <div className="section-head">
      <div>
        <div className="section-kicker">▸ COIN-OP · SHOP</div>
        <h2 className="section-title">PRI<span className="o">C</span>ING</h2>
      </div>
      <div className="section-meta">
        SCRIPTING ONLY · ANIM &amp; VFX QUOTED SEPARATELY<br />
        INSERT COIN TO CONTINUE
      </div>
    </div>

    <PricingBlock kicker="SCRIPTING ONLY · STAGE 01" title="Systems"    items={window.PRICING_SYSTEMS} />
    <PricingBlock kicker="SCRIPTING ONLY · STAGE 02" title="Full games" items={window.PRICING_GAMES} />

    {/* Payment methods */}
    <div style={{ marginTop: 32 }}>
      <div style={{
        color: "var(--cyan)", fontSize: 10, letterSpacing: "0.25em",
        marginBottom: 12,
      }}>▸ ACCEPTED CURRENCIES · INSERT COIN</div>
      <div className="payment-grid">
        {window.PAYMENT_METHODS.map((m) => (
          <div key={m.num} className={`payment ${m.k}`}>
            <div className="payment-num">{m.num}</div>
            <div className="payment-body">
              <div className="payment-title">
                <span className="name">{m.name}</span>
                <span className="payment-tag">{m.tag}</span>
              </div>
              <div className="payment-desc">{m.desc}</div>
            </div>
          </div>
        ))}
      </div>
    </div>

    {/* Heads-up */}
    <div className="pricing-note">
      <div className="pn-icon">!</div>
      <div className="pn-body">
        <strong>HEADS UP ·</strong> prices above are for <span className="hl">scripting only</span>.
        Animation and VFX assets are quoted per asset based on complexity.
        Want the full package? Message me and I'll send a combined quote.
      </div>
    </div>
  </section>
);

const ReplayLog = () => (
  <section className="section" id="replay">
    <div className="section-head">
      <div>
        <div className="section-kicker">▸ REPLAY LOG · WIN STREAK</div>
        <h2 className="section-title">RE<span className="o">P</span>LAYS</h2>
      </div>
      <div className="section-meta">
        ★★★★★ × 14<br/>
        5.0 AVG · NO CONTINUES
      </div>
    </div>
    <div className="replay-grid">
      {window.TESTIS.map((t) => (
        <div key={t.name} className="replay" style={{ "--avatar": t.avatar }}>
          <div className="head">
            <div className="avatar">{t.name[0].toUpperCase()}</div>
            <div>
              <div className="who-name">@{t.name}</div>
              <div className="stars">★★★★★</div>
            </div>
          </div>
          <div className="quote">"{t.quote}"</div>
          <div style={{
            display: "flex", justifyContent: "space-between",
            fontSize: 10, letterSpacing: "0.18em", color: "var(--ink-mute)",
            borderTop: "1px dashed rgba(255,255,255,0.08)", paddingTop: 8, marginTop: 8,
          }}>
            <span>SERVICE  ★★★★★</span>
            <span>COMMS  ★★★★★</span>
            <span>RECOMMEND  ★★★★★</span>
          </div>
        </div>
      ))}
    </div>
  </section>
);

const Contact = ({ onToast }) => {
  const copy = (text, label) => {
    navigator.clipboard?.writeText(text);
    onToast(`◆ ${label} COPIED TO CLIPBOARD`);
  };
  return (
    <section className="contact" id="contact">
      <div className="section-kicker" style={{ marginBottom: 12 }}>▸ INSERT COIN · CONNECT PLAYER 2</div>
      <h2>
        READY<br />
        <span className="stroke">PLAYER</span> ONE.
      </h2>
      <div style={{ color: "var(--ink-dim)", maxWidth: 580, margin: "10px auto 0", fontSize: 14, lineHeight: 1.6 }}>
        Reply &lt; 24h · BRT (UTC−3) · open for commissions and part-time retainers.
      </div>
      <div className="ports">
        <a className="port" href="https://x.com/OrochiDev007" target="_blank" rel="noreferrer">
          <span className="lbl">PORT 01 · X / TWITTER</span>
          <span className="val">@OrochiDev007</span>
          <span className="copy">↗ OPEN</span>
        </a>
        <button
          className="port"
          type="button"
          onClick={() => copy("oroch1n", "DISCORD")}
          style={{ background: "var(--bg-panel)", textAlign: "left", fontFamily: "inherit", cursor: "pointer" }}
        >
          <span className="lbl">PORT 02 · DISCORD</span>
          <span className="val">@oroch1n</span>
          <span className="copy">⧉ COPY</span>
        </button>
        <a className="port" href={DISCORD_URL} target="_blank" rel="noreferrer">
          <span className="lbl">PORT 03 · DM</span>
          <span className="val">MESSAGE ME</span>
          <span className="copy">↗ DISCORD</span>
        </a>
      </div>
      <div style={{
        marginTop: 36, fontSize: 11, color: "var(--ink-mute)",
        letterSpacing: "0.22em",
      }}>
        © 2026 OROCHI · ALL SYSTEMS OPERATIONAL · BUILT WITH LUAU + LOVE
      </div>
    </section>
  );
};

const Ticker = ({ musicOn }) => {
  const base = [
    "◆ NOW HIRING · YOU",
    "◆ HI-SCORE · 2,000,000 VISITS",
    "◆ COMBAT V4 · IN DEVELOPMENT",
    "◆ ★★★★★ 5.0 · WIN STREAK 14",
    "◆ AVAILABLE NOW · BRT",
    "◆ INSERT COIN TO CONTINUE",
    "◆ SHIPS WEEKLY · NO CONTINUES",
  ];
  const items = musicOn
    ? ["◆ NOW PLAYING · orochi_arcade.loop", ...base]
    : base;
  // double for seamless scroll
  const doubled = [...items, ...items];
  return (
    <div className="ticker" aria-hidden="true">
      <div className="ticker-track">
        {doubled.map((s, i) => <span key={i}>{s}</span>)}
      </div>
    </div>
  );
};

const HudTop = () => {
  const [credit, setCredit] = useState(99);
  const [clock, setClock] = useState({ time: "", date: "" });

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      const time = now.toLocaleTimeString("en-GB", {
        hour: "2-digit", minute: "2-digit", second: "2-digit",
        timeZone: "America/Sao_Paulo", hour12: false,
      });
      const date = now.toLocaleDateString("en-GB", {
        weekday: "short", day: "2-digit", month: "short",
        timeZone: "America/Sao_Paulo",
      }).toUpperCase();
      setClock({ time, date });
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <>
      <div className="hud-top">
        <div className="hud-left">
          <span className="brand">◆ OROCHI.EXE</span>
          <span className="v">v2.6.1</span>
        </div>
        <div className="right">
          <a className="nav-link" href="#movelist">▸ MOVELIST</a>
          <a className="nav-link" href="#pricing">▸ SHOP</a>
          <a className="nav-link" href="#replay">▸ REPLAYS</a>
          <a className="nav-link" href="#contact">▸ PLAYER 2</a>
          <span>P1 CREDIT {String(credit).padStart(2, "0")}</span>
          <span className="insert">● INSERT COIN</span>
          <span>HI-SCORE 2,000,000</span>
        </div>
      </div>
      <div className="hud-clock-strip" title="Brasília local time · UTC-3">
        <div className="hud-clock" aria-label="Brasília local time">
          <div className="clock-row">
            <span className="clock-dot">●</span>
            <span className="clock-label">BRT</span>
            <span className="clock-time">{clock.time || "--:--:--"}</span>
          </div>
          <div className="clock-meta">
            <span>SÃO PAULO · UTC−3</span>
            <span>{clock.date}</span>
          </div>
        </div>
      </div>
    </>
  );
};

window.Pricing = Pricing;
window.ReplayLog = ReplayLog;
window.Contact = Contact;
window.Ticker = Ticker;
window.HudTop = HudTop;
