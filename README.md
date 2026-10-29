BugRoyale
=========

Battle of the bugs: a third-person shooter where you are an inch tall. Every map is a slice
of the human world at bug scale, built procedurally in GDScript on a voxel terrain you can dig
and climb. Made with Godot 4.7.

- [Play](#play)
- [Run](#run)
- [Build](#build)
- [Release](#release)
- [Tools](#tools)
- [Credits](#credits)

Play
----

- **Bugs:** Ant Warrior, Termite Soldier, Wasp (flies), Trapdoor Spider.
- **Maps:** Celestial Body, Terrarium, Fish Bowl, Crawlspace, Backyard Garden.
- **Modes:** Attack of the Hornets (co-op waves), Ants vs Ants (team deathmatch),
  Battle Royale (rising flood), Cordyceps Royale (a spore storm turns the fallen into husks
  that hunt you), Explore.

Controls are listed under Settings in the main and pause menus.

Every mode is played against bots today. The plan is to take them online; see the wishlist.

Wishlist
--------

The road to online multiplayer, roughly in order. Each step is also an improvement to the
single-player game, and the bots stay as backfill for lobbies that do not fill.

- [x] One body for every fighter: a human, a bot and (later) a remote player pilot the same
  player scene through a `FighterInput` snapshot. Bots no longer have their own movement or
  shooting code; they walk, climb and fire exactly as a player does.
- [x] Modes work on a list of fighters, not one human plus bots, so a mode never assumes who is
  at the keyboard except to decide what this screen shows.
- [x] Seeded map generation: the whole map builds from one match seed
  (`LoadingScreen.pending_terrain_seed`), so every peer gets identical ground and props.
- [x] Headless smoke test (`tools/smoke_test.tscn`) that runs any map and mode without a window
  and reports whether the bots move, shoot and die.
- [ ] Listen server with Godot's high-level multiplayer (ENet): one player hosts, others join.
  A lobby screen with the mode, map, class and a join code or address.
- [ ] Replicate fighters: spawn remote bodies with a network pilot, send each peer's
  `FighterInput` to the host, and synchronise transforms and animation state back.
- [ ] Terrain edits as an ordered log from the host: clients request a brush or block stamp,
  the host validates it (player clearance against every fighter), broadcasts it, and late
  joiners receive the full override set.
- [ ] Host-authoritative combat and mode state: damage, deaths, scores, hornet waves, the flood
  height, the spore circle and husk conversions all decided once and replicated. Clients show
  shot visuals immediately and accept the verdict.
- [ ] Bots run only on the host and are replicated like any other fighter; lobbies fill with
  bots when short of players.
- [ ] Per-mode stats that survive a restart (best hornet wave per map, royale wins, colony
  records) shown on the mode picker.
- [ ] A pass through every mode on every map (twenty-five combinations) before any release.
- [ ] Store text that says plainly which modes are online and which are versus AI.
- [ ] NAT traversal (a relay, or Steam networking via GodotSteam) once the game logic is
  replicated over plain ENet on a LAN.

Run
---

To play without Godot, grab the Windows exe or the macOS zip from the
[Releases page](https://github.com/jamesfoti/BugRoyale/releases).

To run from source:

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET).
2. Clone this repository.
3. Open Godot, click **Import**, choose the `project.godot` file in the clone, then
   **Import & Edit**. The first open takes a minute while Godot imports the models and
   textures.
4. Press **F5** (or the Play button, top right) to start at the main menu. **F6** runs
   whatever scene is open instead, which is handy for jumping straight into a map such as
   `scenes/garden_test.tscn`.

Build
-----

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_desktop.ps1
```

Exports `builds/windows/BugRoyale.exe` and `builds/macos/BugRoyale.zip` (the .app),
downloading the Godot export templates on first run. Pass `-WindowsOnly` or `-MacOSOnly` for
one platform. Windows and macOS are the only supported platforms; the builds folder is not
committed.

Release
-------

Downloads live on the [Releases page](https://github.com/jamesfoti/BugRoyale/releases).
To publish one, bump `config/version` in `project.godot`, commit, then:

```powershell
powershell -ExecutionPolicy Bypass -File tools/release.ps1
```

This builds both platforms, tags the commit `v<version>` and creates a GitHub release
(via the `gh` CLI) with the Windows exe and the macOS zip attached.

Tools
-----

Bug models are generated in Blender by `tools/blender/create_bugs.py`.

Credits
-------

Textures from https://ambientcg.com/  
Sound effects partly from https://sonniss.com/gameaudiogdc
