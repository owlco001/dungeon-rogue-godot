# Dungeon Rogue

A top-down randomized dungeon roguelike: auto-attack survival action — survive the monster tide with positioning and build crafting.

**[中文版](README.md)** | English

![Godot](https://img.shields.io/badge/Godot-4.7.2-478CBF?logo=godotengine&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Web%20%2F%20Mobile-2ea44f)

## 🎮 Play Online

**https://pub-6d672ee312244873adb8f72bb964be94.r2.dev/dungeon-rogue-v07.html**

(Works in any modern mobile/desktop browser — hard-refresh to get the latest build.)

## 📖 Gameplay

- **Core loop**: Survivors-style horde survival. Your character attacks automatically — you handle movement, builds, and fusions.
- **Characters differ by weapon**: Three heroes, three signature weapons — Ella (bow), Barton (axe), Murphy (orb), each starting with their own.
- **Super-weapon evolution**: Max out a weapon + its designated passive to fuse a super weapon via the level-up draft. 19 weapons, 19 fusion routes.
- **Four schools**: Guns / Summoning / Necromancy / Melee, each with its own weapons and super weapons. Characters only grant a 15% affinity bonus — no hard binding.
- **Enemy pacing**: Four trash mobs (slime / bat / spitter / brute), a boss every 5 minutes, clear floor 30 to win, then Endless Mode unlocks.
- **Relics**: A separate 3-slot inventory, dropped only by elites / bosses / chests — 12 relics across blue / purple / gold tiers.
- **Skills**: 2 slots (1 signature + 1 from the shared pool), auto-cast by default with manual override, max level 3.
- **Meta progression**: Run gold funds permanent stat upgrades, a three-branch talent tree (Combat / Survival / Greed), and unlocking new characters and weapons.
- **Mid-run saving**: Save mid-battle from the HUD, return to the lobby, and pick up right where you left off with "Continue".

## 🛠 Built With

- **Engine**: Godot 4.7.2 (GDScript), Web export with a custom HTML shell (`web/shell.html`: loading screen, BGM, native WebAudio SFX channel, floating virtual joystick).
- **🤖 Driven by Muse**: This project's design, code, tuning, debugging, deployment, and iteration were all carried out by **Muse**, Meta's personal AI agent, in conversation with the developer — from the gameplay spec to every line of GDScript, every export, and every release verification.
- **🎨 Art by Agnes**: Character portraits and sprites, monsters, dungeon tiles, the torch flame, the lobby background, and other art assets were generated with **Agnes AI** (text-to-image / image-to-image), then processed — background removal, frame slicing, procedural post-processing — before entering the game. A few environment details (torch brackets, cracked floors) are generated procedurally in code.
- **Audio**: BGM is a CC0 ambient track (OpenGameArt); sound effects are procedurally synthesized in code (on Web they run through native WebAudio, bypassing the engine audio pipeline).

## 📁 Project Structure

```
scripts/    Game logic (main loop / lobby / HUD / characters / enemies / saving)
scenes/     Godot scenes
assets/     Art and audio assets (Agnes-generated + post-processed)
web/        Custom Web export shell (shell.html)
tools/      Asset post-processing and single-file packaging scripts
test/       In-engine screenshot / save-verification scripts
```

## 🚀 Run Locally

1. Install Godot 4.7.2 and import this project — open `project.godot` and run.
2. For Web export, use the Web preset in `export_presets.cfg` with `web/shell.html` as the custom shell.

## 📜 License

Code and original assets are shared for learning purposes; the BGM track follows its CC0 license.
