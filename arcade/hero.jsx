// HERO — character select with portrait + 6 skill bars
const { useEffect, useState } = React;

const Hero = () => {
  const [time, setTime] = useState("");
  useEffect(() => {
    const tick = () => {
      const d = new Date();
      const t = d.toLocaleTimeString("en-GB", {
        hour: "2-digit", minute: "2-digit",
        timeZone: "America/Sao_Paulo",
      });
      setTime(`${t} BRT`);
    };
    tick();
    const id = setInterval(tick, 30000);
    return () => clearInterval(id);
  }, []);

  return (
    <section className="hero" id="top">
      <div>
        <div className="hero-kicker">▸ FIGHTER SELECT  /  STAGE 01  /  CONTINUE? ◀</div>
        <h1>
          OROCHI<br />
          <span className="magenta">THE</span> <span className="outline">SCRIPTER</span>
        </h1>
        <p className="hero-tagline">
          <span className="cursor">&gt;</span>{" "}
          <strong>Fullstack Roblox dev.</strong> Hitboxes that hit. AI that hunts.
          VFX that pops. Six years deep in the lab — combat-first, ships weekly,
          ships clean.
        </p>

        <div className="skills" role="list" aria-label="Skill stats">
          {window.SKILLS.map((s) => (
            <div key={s.label} className="bar" role="listitem"
                 style={{ "--bar-color": s.color, "--scale": s.value / 100 }}>
              <span className="label">{s.label}</span>
              <div className="track">
                <div className="fill" />
              </div>
              <span className="num">{s.value}</span>
            </div>
          ))}
        </div>

        <div className="hero-cta">
          <a href="#movelist" className="btn-crt">▶ PRESS START</a>
          <a href="#contact" className="btn-crt ghost">◇ CONTINUE? Y/N</a>
        </div>

        <div style={{
          marginTop: 22,
          display: "flex", gap: 24, flexWrap: "wrap",
          fontSize: 11, letterSpacing: "0.18em", color: "var(--ink-mute)",
        }}>
          <span>● ONLINE · {time}</span>
          <span>P1 · @OROCHIDEV007</span>
          <span style={{ color: "var(--green)" }}>READY FOR PLAYER 2</span>
        </div>
      </div>

      <div className="portrait-wrap" aria-label="Orochi portrait">
        <img className="portrait-img" src="arcade/orochi-portrait.png" alt="Orochi" />
        <div className="portrait-tint" />
        <div className="portrait-scan" />
        <div className="portrait-corner tl" />
        <div className="portrait-corner tr" />
        <div className="portrait-corner bl" />
        <div className="portrait-corner br" />
        <div className="portrait-top">◆ 01 / 01 · FIGHTER</div>
        <div className="portrait-name">
          <div className="who">OROCHI</div>
          <div className="rank">
            <span className="s">RANK · S+</span>
            <span className="stars">★★★★★ 5.0</span>
          </div>
        </div>
      </div>
    </section>
  );
};

window.Hero = Hero;
