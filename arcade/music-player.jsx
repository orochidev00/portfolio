// MUSIC PLAYER — CRT lo-fi player, opt-in, localStorage, fade in/out

const { useState, useEffect, useRef, useCallback } = React;

const STORAGE_KEY_ON  = "orochi_music_on";
const STORAGE_KEY_VOL = "orochi_music_vol";
const TRACK_SRC = "arcade/orochi_arcade_lofi.mp3";
const TRACK_NAME = "orochi_arcade.loop";

const MusicPlayer = ({ onPlayingChange }) => {
  // initial state from localStorage but DO NOT autoplay
  const [expanded, setExpanded] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [volume, setVolume]   = useState(() => {
    const stored = parseFloat(localStorage.getItem(STORAGE_KEY_VOL));
    return Number.isFinite(stored) ? stored : 0.4;
  });
  const audioRef = useRef(null);
  const fadeRef = useRef(null);

  // notify parent so it can drive ticker / body class
  useEffect(() => {
    onPlayingChange?.(playing);
    if (playing) document.body.classList.add("music-on");
    else document.body.classList.remove("music-on");
  }, [playing]);

  // persist volume
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY_VOL, String(volume));
    if (audioRef.current && !fadeRef.current) {
      audioRef.current.volume = playing ? volume : 0;
    }
  }, [volume]);

  // fade helper
  const fadeTo = useCallback((target, ms, onDone) => {
    const audio = audioRef.current;
    if (!audio) return;
    if (fadeRef.current) { cancelAnimationFrame(fadeRef.current); fadeRef.current = null; }
    const start = audio.volume;
    const t0 = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - t0) / ms);
      audio.volume = start + (target - start) * k;
      if (k < 1) fadeRef.current = requestAnimationFrame(step);
      else { fadeRef.current = null; onDone?.(); }
    };
    fadeRef.current = requestAnimationFrame(step);
  }, []);

  const start = useCallback(async () => {
    const audio = audioRef.current;
    if (!audio) return;
    try {
      audio.volume = 0;
      await audio.play();
      setPlaying(true);
      localStorage.setItem(STORAGE_KEY_ON, "1");
      fadeTo(volume, 1500);
    } catch (e) {
      // autoplay blocked or load fail
      setPlaying(false);
    }
  }, [volume, fadeTo]);

  const stop = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;
    fadeTo(0, 1000, () => { audio.pause(); });
    setPlaying(false);
    localStorage.setItem(STORAGE_KEY_ON, "0");
  }, [fadeTo]);

  const toggle = () => playing ? stop() : start();

  // pause on tab hidden, resume on visible (only if was playing & user-enabled)
  useEffect(() => {
    const onVis = () => {
      const audio = audioRef.current;
      if (!audio) return;
      const wasOn = localStorage.getItem(STORAGE_KEY_ON) === "1";
      if (document.hidden) {
        if (!audio.paused) audio.pause();
      } else if (wasOn && playing) {
        audio.play().catch(() => {});
      }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, [playing]);

  // global keyboard shortcut M for mute toggle
  useEffect(() => {
    const onKey = (e) => {
      // ignore when typing
      const tag = (e.target?.tagName || "").toLowerCase();
      if (tag === "input" || tag === "textarea") return;
      if (e.key === "m" || e.key === "M") {
        e.preventDefault();
        toggle();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [playing]);

  // arrow nav on volume blocks when focused
  const onBlocksKey = (e) => {
    if (e.key === "ArrowRight") { e.preventDefault(); setVolume(v => Math.min(1, v + 0.1)); }
    if (e.key === "ArrowLeft")  { e.preventDefault(); setVolume(v => Math.max(0, v - 0.1)); }
  };

  const blocks = Array.from({ length: 10 }, (_, i) => i < Math.round(volume * 10));

  const onBlocksClick = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const ratio = (e.clientX - rect.left) / rect.width;
    setVolume(Math.max(0, Math.min(1, ratio)));
  };

  if (!expanded) {
    return (
      <>
        <audio ref={audioRef} src={TRACK_SRC} loop preload="metadata" />
        <div className="music">
          <button
            className={`music-collapsed ${playing ? "playing" : "idle"}`}
            onClick={() => setExpanded(true)}
            aria-label="Open ambient music player"
            type="button"
          >♪</button>
        </div>
      </>
    );
  }

  return (
    <>
      <audio ref={audioRef} src={TRACK_SRC} loop preload="metadata" />
      <div className="music">
        <div className="music-panel" role="region" aria-label="Ambient music player">
          <div className="music-panel-head">
            <span>[♪] {playing ? "NOW PLAYING" : "STANDBY"}</span>
            <button onClick={() => setExpanded(false)} aria-label="Collapse player" type="button">─</button>
          </div>
          <div className="music-panel-body">
            <div className="music-track">
              <span className="cursor">&gt;</span>
              <span className="name">{TRACK_NAME}</span>
              {playing && <span style={{ marginLeft: "auto", color: "var(--green)" }}>●</span>}
            </div>
            <div className="music-controls">
              <button
                className="music-btn"
                onClick={toggle}
                aria-label={playing ? "Pause ambient music" : "Play ambient music"}
                aria-pressed={playing}
                type="button"
              >{playing ? "■" : "▶"}</button>
              <div className="music-vol">
                <span className="lbl">VOL</span>
                <div
                  className="music-blocks"
                  onClick={onBlocksClick}
                  onKeyDown={onBlocksKey}
                  role="slider"
                  tabIndex={0}
                  aria-label="Volume"
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={Math.round(volume * 100)}
                >
                  {blocks.map((on, i) => (
                    <div key={i} className={`blk ${on ? "on" : ""}`} />
                  ))}
                </div>
              </div>
            </div>
            <div style={{
              marginTop: 8, fontSize: 9, color: "var(--ink-mute)",
              letterSpacing: "0.15em", display: "flex", justifyContent: "space-between",
            }}>
              <span>[ M ] MUTE</span>
              <span>{Math.round(volume * 100)}%</span>
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

window.MusicPlayer = MusicPlayer;
