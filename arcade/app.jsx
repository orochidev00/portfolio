// APP — composes everything + tweaks panel for background variations

const { useState, useEffect } = React;

// Three picked variations between #2a1245 and #3a1f5c
const BG_VARIATIONS = [
  { id: "mid",   label: "Mid · #321a51", value: "#321a51" },
  { id: "deep",  label: "Deep · #2d1648", value: "#2d1648" },
  { id: "light", label: "Light · #371d57", value: "#371d57" },
];

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "bgVariation": "mid",
  "scanlineIntensity": 0.035,
  "neonSaturation": 1.0,
  "ambientGlow": true
}/*EDITMODE-END*/;

const App = () => {
  const [toast, setToast] = useState({ msg: "", show: false });
  const [musicOn, setMusicOn] = useState(false);
  const tweaks = (typeof useTweaks !== "undefined") ? useTweaks(TWEAK_DEFAULTS) : [TWEAK_DEFAULTS, () => {}];
  const [t, setTweak] = tweaks;

  // Apply tweaks
  useEffect(() => {
    const root = document.documentElement;
    const v = BG_VARIATIONS.find(x => x.id === t.bgVariation) || BG_VARIATIONS[0];
    root.style.setProperty("--bg-base", v.value);
    root.style.setProperty("--scanline-h", `${Math.max(2, Math.round(3 / Math.max(0.5, t.scanlineIntensity * 30)))}px`);
    // neon saturation: tweak between full and slightly desaturated
    const sat = t.neonSaturation ?? 1.0;
    if (sat < 1.0) {
      const k = 1 - sat;
      // desaturate magenta toward purplish
      const r = Math.round(255 - 80 * k);
      const g = Math.round(43 + 80 * k);
      const b = Math.round(214 - 30 * k);
      root.style.setProperty("--neon", `rgb(${r},${g},${b})`);
    } else {
      root.style.setProperty("--neon", "#ff2bd6");
    }
  }, [t.bgVariation, t.scanlineIntensity, t.neonSaturation]);

  const showToast = (msg) => {
    setToast({ msg, show: true });
    setTimeout(() => setToast((s) => ({ ...s, show: false })), 1800);
  };

  return (
    <>
      <div className="crt-noise-overlay" />
      <HudTop />
      <main>
        <Hero />
        <div className="divider" />
        <Movelist onToast={showToast} />
        <div className="divider" />
        <Pricing />
        <div className="divider" />
        <ReplayLog />
        <Contact onToast={showToast} />
      </main>
      <Ticker musicOn={musicOn} />
      <MusicPlayer onPlayingChange={setMusicOn} />
      <div className={`toast ${toast.show ? "show" : ""}`}>{toast.msg}</div>

      {typeof TweaksPanel !== "undefined" && (
        <TweaksPanel title="Tweaks">
          <TweakSection label="Background">
            <TweakRadio
              label="Purple shade"
              value={t.bgVariation}
              options={BG_VARIATIONS.map(v => ({ value: v.id, label: v.label.split(" · ")[0] }))}
              onChange={(v) => setTweak({ bgVariation: v })}
            />
          </TweakSection>
          <TweakSection label="CRT">
            <TweakSlider
              label="Scanline intensity"
              value={t.scanlineIntensity}
              min={0.01} max={0.08} step={0.005}
              onChange={(v) => setTweak({ scanlineIntensity: v })}
            />
            <TweakToggle
              label="Ambient noise overlay"
              value={t.ambientGlow}
              onChange={(v) => setTweak({ ambientGlow: v })}
            />
          </TweakSection>
          <TweakSection label="Neon">
            <TweakSlider
              label="Magenta saturation"
              value={t.neonSaturation}
              min={0.7} max={1.0} step={0.05}
              onChange={(v) => setTweak({ neonSaturation: v })}
            />
          </TweakSection>
        </TweaksPanel>
      )}
    </>
  );
};

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
