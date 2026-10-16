# Orochi — Luau Programmer & CS Grad

Roblox scripter with 6+ years of Luau. I build combat that lands, enemies that think, and full games from an empty baseplate. Everything that matters runs on the server, so exploiters get nothing.

**[Portfolio](https://orochidev00.github.io/portfolio/)** · **Discord:** `@oroch1n` · **[X](https://x.com/OrochiDev007)**

## Skills

- **Languages:** Luau (advanced), C, C++, C#, HTML/CSS/JavaScript
- **Workflow:** Rojo, Wally, VS Code, Git/GitHub
- **Focus:** OOP, state machines, NPC AI, server-side hit validation, DataStores, replication and network optimization

## Featured work

### Deepwoken Combat & Ulquiorra AI
A melee prototype with a boss that fights back.
- 4-hit M1 chain, parries and directional blocking
- Boss AI runs on a state machine, using `PathfindingService` for positioning, parry trades and adaptive aggression
- Hits are validated on the server, while feedback plays on the client, so it feels instant

### El Thor
Enel's El Thor from One Piece. **[Full source on my portfolio](https://orochidev00.github.io/portfolio/#src-elthor)**
- The client renders every effect. The server only checks range, line of sight and cooldown, then applies damage
- Custom ragdoll, with NPC knockback simulated on the attacker's client so it never rubber-bands
- Modular, so it drops straight into a bigger combat framework

### Steal an Egg
A brainrot-style collection game built around a live conveyor.
- Trait and mutation rolls, with rarity-based value scaling
- Backend built to stay fast with lots of players and entities on screen
- Live conveyor spawning, clean multiplayer sync and lightweight UI state

### Brainrot Clash Arena
A battlegrounds-style game with character movesets. I handled the whole production pipeline.
- Combo interactions, hit feedback, character movesets and ultimates
- Modular codebase that holds 60 TPS in big fights with heavy VFX on screen

### Horror Monster AI
A survival-horror enemy that feels alive.
- Finite state machine: Idle, Wandering, Stalking, Toying and Chasing
- `PathfindingService` plus custom raycasts for line of sight, so its pathing is hard to predict
- Toying reads player proximity to build pressure before the chase

### Six Seven Hollow Purple
A meme take on Gojo's Hollow Purple, built as a stress test.
- Massive VFX and destruction replicated to every client without dropping the server tick rate
- Client-side visual prediction with strict server-side validation for a huge AoE
- Particles and sound stay in sync, with punchy timing

## Contact

- **Portfolio:** [orochidev00.github.io/portfolio](https://orochidev00.github.io/portfolio/)
- **Discord:** `@oroch1n`
- **Roblox Talent Hub:** [orochixz00](https://create.roblox.com/talent/creators/291349970)
- **X:** [@OrochiDev007](https://x.com/OrochiDev007)
- **Payment:** USD via Wise or PayPal
