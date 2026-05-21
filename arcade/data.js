// SHOWCASES — six "moves" in the movelist
// Source snippets are placeholders for the user to replace with real code.

window.SHOWCASES = [
  // ============================================================
  {
    id: "combat-v2",
    num: "01",
    title: "Combat System V2",
    category: "SYSTEMS / GAMEPLAY",
    year: "2026",
    youtube: "TVF9c6on6dM",
    tags: [
      { t: "LUAU" },
      { t: "COMBAT", k: "cyan" },
      { t: "VFX", k: "cyan" },
      { t: "ANIM", k: "yellow" },
    ],
    tagline:
      "Built from scratch with raw game feel as priority. Every hit lands with weight, every animation flows into the next, the environment reacts to the fight.",
    features: [
      "Five-hit M1 combo with unique animations per hit + contextual blending — reads as one motion, not five clips",
      "Final hit launches with stronger knockback and heavier camera reaction",
      "Directional knockback (force vectors relative to attacker position): server-side ApplyImpulse for NPCs, client-side LinearVelocity for players, ownership handled cleanly to eliminate rubber-banding",
      "Wall interactions: knocked-back targets raycast the impact — bounce off with reduced velocity, or destroy the wall if it's breakable (physics debris + impact SFX, lifetime cleanup)",
      "Jump attack with airborne hitbox, downward slam, and ground-impact shockwave (camera shake + radial VFX on landing)",
      "Layered VFX per hit: impact flash, hit pause on heavies, screen ripple — smoothness end-to-end was the goal",
      "Animations reworked in Blender with the Rbx Animations plugin — keyframe spacing tuned for anticipation and follow-through",
    ],
    frameData: {
      "STARTUP":  { v: "6F", k: "" },
      "ACTIVE":   { v: "8F", k: "warn" },
      "RECOVERY": { v: "14F", k: "" },
      "DAMAGE":   { v: "HEAVY", k: "heavy" },
      "TYPE":     { v: "COMBO", k: "" },
      "ON HIT":   { v: "LAUNCH", k: "heavy" },
    },
    file: "combat_v2.luau",
    locked: true,
    code: "",
  },

  // ============================================================
  {
    id: "npc-ai",
    num: "02",
    title: "NPC AI + Combat",
    category: "SYSTEMS / AI",
    year: "2025",
    youtube: "8g1v6xCz8_I",
    tags: [
      { t: "LUAU" },
      { t: "NPC AI", k: "cyan" },
      { t: "PHYSICS", k: "cyan" },
      { t: "STATE", k: "yellow" },
    ],
    tagline:
      "Client commissioned a polished melee combat system with responsive enemy AI. Goal: replace stiff, default-feeling combat with weight, feedback, and tactical depth.",
    features: [
      "Server-authoritative combat: full melee combo chain (jab, straight, hooks, finisher)",
      "Hitbox detection via GetPartBoundsInBox for performance",
      "Knockback split by ownership: client-side LinearVelocity for players, server-side ApplyImpulse for NPCs",
      "Ragdoll replication: server joint replacement + client HumanoidState for clean visual replication with no jitter",
      "Parry / guard logic + stun state management",
      "NPC AI built on dispatch table pattern: CollectionService tagging, TweenService + AlignOrientation for smooth movement, LinearVelocity for physics-based reactions, GoodSignal for clean event handling",
      "Strict separation of concerns: server owns rig state, client owns its own movement and visual physics — clean replication, extensible without rewriting",
    ],
    frameData: {
      "STARTUP":  { v: "4F", k: "" },
      "REACT":    { v: "12F", k: "warn" },
      "TYPE":     { v: "AI",  k: "heavy" },
      "DAMAGE":   { v: "MED", k: "" },
      "PARRY":    { v: "Y",   k: "warn" },
      "STATES":   { v: "5",   k: "" },
    },
    file: "npc_ai.luau",
    locked: true,
    code: "",
  },

  // ============================================================
  {
    id: "hollow-purple",
    num: "03",
    title: "Brainrot Hollow Purple",
    category: "VFX SHOWCASE",
    year: "2026",
    youtube: "2szRCTIzJjk",
    tags: [
      { t: "LUAU" },
      { t: "VFX", k: "cyan" },
      { t: "PARTICLES", k: "cyan" },
      { t: "SPECIAL", k: "yellow" },
    ],
    tagline:
      "Brainrot-meme reskin of Gojo's Hollow Purple — built around the \"6+7\" joke. Two orbs form, charge together, then release as a massive purple sphere that swallows everything.",
    features: [
      "\"Six\" (blue) and \"Seven\" (red) orbs spawn instantly between player's hands — pure particle VFX, no meshes",
      "\"Six\": inward spiral motion, soft glow, low-frequency hum. \"Seven\": mirrored inverse — inverse particle direction, higher-pitched layered SFX. Both hover in contact, vibrating, energy bleeding between them",
      "Charge phase ramps emission rate, glow, SFX pitch — screen edges pulse with light, player locks into heavy anticipation pose. The longer it charges, the heavier the release reads",
      "On release: orbs collapse into each other and the Purple launches — a massive sphere, not a beam",
      "Travels slow relative to its size — devours with trailing particle ribbons, distortion shell, scorch decals dragged across the ground, debris ejected from impact zone",
      "Hit detection sweeps the sphere's volume with GetPartBoundsInBox — everything caught gets max knockback and a vaporize VFX",
      "Camera scales with the move: subtle hum on charge, hard impact-frame freeze on release, sustained shake while the sphere travels",
    ],
    frameData: {
      "STARTUP":  { v: "120F", k: "heavy" },
      "CHARGE":   { v: "VAR",  k: "warn" },
      "TYPE":     { v: "ULT",  k: "heavy" },
      "DAMAGE":   { v: "OBLITERATE", k: "heavy" },
      "RANGE":    { v: "FULL", k: "" },
      "INPUT":    { v: "↓ ↘ → + P", k: "warn" },
    },
    file: "hollow_purple.luau",
    locked: true,
    code: "",
  },

  // ============================================================
  {
    id: "monster-ai",
    num: "04",
    title: "Monster AI (Horror)",
    category: "AI / BEHAVIOR",
    year: "2025",
    youtube: "B2ewyqXSjTo",
    tags: [
      { t: "LUAU" },
      { t: "AI", k: "cyan" },
      { t: "PATHFIND", k: "cyan" },
      { t: "HORROR", k: "yellow" },
    ],
    tagline:
      "Client needed a horror monster AI that felt like a real threat, not a brainless chaser. Five-state machine built to feel intentional.",
    features: [
      "Five states: idle · wandering · stalk · chase · toying",
      "Wandering: pathfinding with randomized pauses",
      "Stalking: keeps the entity just outside line of sight, breaks visibility when the player turns — the kind of behavior you catch out of the corner of your eye and aren't sure was real",
      "Chase: aggressive, with stamina tracking",
      "Toying: slows the monster on low-HP players and lets them almost escape before closing in",
      "Idle: cooldowns + ambient listening",
      "Built as dispatch table state machine: CollectionService, GoodSignal, TweenService, AlignOrientation, LinearVelocity — each state is its own module, easy to extend",
      "Transitions designed with explicit entry conditions, cooldowns, and last-known-player-position memory — behavior reads as motivated, not random",
    ],
    frameData: {
      "STATES":   { v: "5",   k: "heavy" },
      "VISION":   { v: "LoS", k: "" },
      "MEMORY":   { v: "Y",   k: "warn" },
      "TYPE":     { v: "AI",  k: "heavy" },
      "PATH":     { v: "DYN", k: "" },
      "AGGRO":    { v: "ADAPTIVE", k: "warn" },
    },
    file: "monster_ai.luau",
    code: (typeof window !== "undefined" && window.CODE_MONSTER_AI) || "",
  },

  // ============================================================
  {
    id: "egg-tycoon",
    num: "05",
    title: "Egg Tycoon (Brainrot)",
    category: "FULL GAME",
    year: "2025",
    youtube: "Lqq1iFL1rCI",
    tags: [
      { t: "LUAU" },
      { t: "SYSTEMS", k: "cyan" },
      { t: "DATASTORE", k: "cyan" },
      { t: "ECONOMY", k: "yellow" },
    ],
    tagline:
      "Steal-a-Brainrot-style game built from scratch with eggs as collectible units. Full systems stack: shop, plots, raids, economy, persistence.",
    features: [
      "Egg shop with weighted rarity tiers — per-egg income rate, rarity, visual model, scaled pricing. Higher tiers unlock with progression so the shop feels like a real curve, not a flat list",
      "Plot system: each player owns a base with placement slots for active eggs",
      "Income generates on server-authoritative tick loop, batched across all eggs to keep server cost flat regardless of player count",
      "Offline earnings calculated on rejoin with capped multiplier — AFK doesn't break the economy",
      "Stealing mechanic: raidable plots, escape timers, server-side ownership checks, anti-exploit validation on every grab, carry animation while holding, instant alert to owner the moment a raid starts",
      "DataStore architecture: egg inventory, currency, plot state, stolen-egg history — session locking prevents data loss on rejoin or server hop",
    ],
    frameData: {
      "SCOPE":   { v: "GAME", k: "heavy" },
      "TIERS":   { v: "WEIGHTED", k: "" },
      "ECON":    { v: "TICKED", k: "warn" },
      "STEAL":   { v: "Y",     k: "warn" },
      "SAVES":   { v: "LOCKED", k: "" },
      "OFFLINE": { v: "CAP'D", k: "" },
    },
    file: "plot_system.luau",
    locked: true,
    code: "",
  },

  // ============================================================
  {
    id: "el-thor",
    num: "06",
    title: "El Thor",
    category: "VFX SHOWCASE",
    year: "2026",
    twitter: "https://x.com/OrochiDev007/status/2056681677468926415",
    tags: [
      { t: "LUAU" },
      { t: "VFX", k: "cyan" },
      { t: "LIGHTNING", k: "yellow" },
      { t: "CINEMATIC", k: "yellow" },
    ],
    tagline:
      "Enel's signature lightning strike, built as a layered VFX system. Full anticipation → impact → dissipation arc.",
    features: [
      "Cast pose: continuous hand-channel VFX (glow + lightning emanating, pure flow, no emits)",
      "Cloud spawns above target, position raycast-locked at cast moment (snapshot, not tracking)",
      "Floor part drops from cloud to ground (0.1s linear tween) — emitters pre-parented, emitted only on impact, prevents race conditions",
      "Three lightning beams connecting cloud and floor — width tweens 60 → 120 in 0.06s for impact swell",
      "Six concentric debris rings spawn outward, scaled to beam width — materials read dynamically from raycastResult.Instance.Material and .Color so debris matches whatever terrain was hit",
      "Impact burst: bloom, shockwave, ground-hugging dust in terrain color, residual lightning arcs",
      "Cleanup: single pass at the end — debris recede smallest-to-largest, all instances destroyed in one cycle",
      "Full client-side, no remotes, single-script orchestration",
    ],
    frameData: {
      "STARTUP":  { v: "30F", k: "warn" },
      "IMPACT":   { v: "6F",  k: "heavy" },
      "TYPE":     { v: "SPECIAL", k: "heavy" },
      "DAMAGE":   { v: "HEAVY", k: "heavy" },
      "BEAMS":    { v: "×3",  k: "" },
      "RINGS":    { v: "×6",  k: "" },
    },
    file: "el_thor.luau",
    code: (typeof window !== "undefined" && window.CODE_EL_THOR) || "",
  },
];

window.SKILLS = [
  { label: "COMBAT",    value: 98, color: "var(--neon)" },
  { label: "NPC AI",    value: 92, color: "var(--cyan)" },
  { label: "VFX",       value: 95, color: "var(--yellow)" },
  { label: "SYSTEMS",   value: 96, color: "var(--orange)" },
  { label: "ANIMATION", value: 82, color: "var(--green)" },
  { label: "LIVE-OPS",  value: 88, color: "var(--cyan)" },
];

window.PRICING_SYSTEMS = [
  { tier: "Simple",  price: "$20 – $100",   rbx: "5k – 25k R$",   desc: "Small mechanics, utilities, single-purpose scripts.", ex: "Currency, leaderboard, basic shop" },
  { tier: "Medium",  price: "$100 – $250",  rbx: "25k – 65k R$",  desc: "Multi-part systems with state, UI and networking.", ex: "Quest system, mid-size combat", hot: true },
  { tier: "Complex", price: "$250 – $750",  rbx: "65k – 190k R$", desc: "Full-feature systems with deep polish and tooling.",  ex: "Pet system, advanced combat, AI" },
];

window.PRICING_GAMES = [
  { tier: "Simple game",  price: "$750+",   rbx: "190k+ R$",  desc: "Small, focused game with one core loop.",          ex: "Obby, tycoon, simulator MVP" },
  { tier: "Medium game",  price: "$1,250+", rbx: "315k+ R$",  desc: "Multiple systems, progression and monetization.",   ex: "Sim w/ pets & rebirths, PvP arena", hot: true },
  { tier: "Complex game", price: "$1,800+", rbx: "450k+ R$",  desc: "AAA-style scope, live-ops ready, long-term support.", ex: "Action RPG, anime fighter, horror" },
];

window.PAYMENT_METHODS = [
  { num: "01", name: "Wise",   tag: "PREFERRED", desc: "Best rates for me — use this if you can.",                              k: "neon" },
  { num: "02", name: "PayPal", tag: "MOST USED", desc: "Default option — fast and works everywhere.",                           k: "cyan" },
  { num: "03", name: "Robux",  tag: "CASE-BY-CASE", desc: "Minimum 5,000 R$. Not every project qualifies — ask first.",         k: "yellow" },
];

window.TESTIS = [
  { name: "zerokazi", quote: "Very straight forward and got the work done.", avatar: "#ff2bd6" },
  { name: "jacks96",  quote: "Great work got everything done quickly :)",   avatar: "#00f0ff" },
  { name: "ufogames_",quote: "Valor bom e justo, Henry muito gente boa.",   avatar: "#ffe600" },
  { name: "client_pv",quote: "Delivered above the brief. Will hire again.", avatar: "#7cff5a" },
];
