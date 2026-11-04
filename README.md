BugRoyale
=========

Battle of the bugs: a third-person shooter where you are an inch tall. Every map is a slice
of the human world at bug scale, built procedurally in GDScript on a voxel terrain you can dig
and climb. Made with Godot 4.7.

- [Play](#play)
- [Run](#run)
- [Build](#build)
- [Tests](#tests)
- [Release](#release)
- [Tools](#tools)
- [Credits](#credits)

Play
----

- **Bugs:** Ant Warrior, Termite Soldier, Wasp (flies), Trapdoor Spider.
- **Maps:** Backyard Garden, Crawlspace, Terrarium. All three are the same size (512 m
  across, three chunks deep), and every match's seed carves a new underworld into them
  (CaveCarver): worm tunnels from a few metres down, caverns from twenty, a few sinkholes
  open to the sky, and bedrock at the bottom. The terrarium is a 5 m tank on a coffee
  table in a room scaled to match. In the garden the soil in the raised beds is terrain
  too, dug and built on like the lawn.
- **Three modes on the menu.** Burrow (survival as the colony's soldier: four workers carry
  the queen and follow you, you pick the ground and give the word, they dig her chamber;
  then dig by day and build with what you carve while the workers forage crumbs, seeds and
  sugar to the entrance, every six food is an egg that hatches a worker at dawn, the room
  you dig below ground caps how many the colony can be, a fallen worker is gone for good,
  hornets hunt by day and by night, trapdoor spiders lurk among the food, hold the burrow
  after dark against husks and raiding ants, and keep the queen alive, because the colony
  dies with her; the deeper you dig the darker it gets, so carry the torch;
  the map is saved as you go), Hold Out (you and 3 AI
  squadmates against waves of hornets, husks and enemy ants) and Slayer (deathmatch, Solo,
  Skirmish 4v4, Colony 12v12 or Big Colony 24v24, bots filling every empty slot).
- **Burrow saves as you go**, under `user://worlds`, and the world is there next time, with a
  Start over button on the map page to wipe it.
- **What the ground is made of.** Under the topsoil the ground is stone with veins of sand,
  clay and gravel, and pockets of ore: 42 chemical elements, every one that is dug out of the
  Earth's crust as an ore or found native in it (no gases, nothing made only in a reactor).
  Each lies from a depth of its own, carbon, sulfur, calcium and the like from two metres down,
  iron, copper, lead and tin from seven, silver and tungsten from fourteen, gold, platinum and
  uranium from twenty, and the pickaxe pays out whatever it cuts through. Every dug material,
  element or ground, is then something to build with: the inventory lists an element the first
  time you hold some, and the Dug panel shows what is in hand.

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
- [x] In-game bug reports: F9 freezes the game and saves a screenshot, the match's seed and
  state, and the log to a folder the player can attach anywhere.
- [x] Host-ready plumbing: the human's aim and yaw travel in the input snapshot with a tick
  number; one authority gate (`Authority`) on all damage; terrain edits go through one logged
  entry point with export/import for late joiners and clearance checked against every fighter;
  fighters have stable ids and the mode places every spawn; modes split deciding (host only)
  from showing (a state snapshot plus announcements).
- [ ] Listen server with Godot's high-level multiplayer (ENet): one player hosts, others join.
  A lobby screen with the mode, map, class and a join code or address.
- [ ] Replicate fighters: spawn remote bodies with a network pilot, send each peer's
  `FighterInput` to the host, and synchronise transforms and animation state back.
- [ ] Terrain edits as an ordered log from the host: clients request a brush or block stamp,
  the host validates it (player clearance against every fighter), broadcasts it, and late
  joiners receive the full override set.
- [ ] Host-authoritative combat and mode state: damage, deaths, scores, hornet waves
  and husk conversions all decided once and replicated. Clients show
  shot visuals immediately and accept the verdict.
- [ ] Bots run only on the host and are replicated like any other fighter; lobbies fill with
  bots when short of players.
- [ ] Interest management: a client only receives the bodies inside its bubble, so big
  colony counts stay affordable over the wire.
- [ ] Per-mode stats that survive a restart (best hornet wave per map, nights survived,
  colony records) shown on the mode picker.
- [ ] A pass through every mode on every map and format before any release.
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
   `scenes/garden.tscn`.

Build
-----

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_desktop.ps1
```

Exports `builds/windows/BugRoyale.exe` and `builds/macos/BugRoyale.zip` (the .app),
downloading the Godot export templates on first run. Pass `-WindowsOnly` or `-MacOSOnly` for
one platform. Windows and macOS are the only supported platforms; the builds folder is not
committed.

Tests
-----

Three layers: a style check against the GDScript style guide, unit tests for the rules and
arithmetic, and a headless smoke test that plays a whole bot match per mode. All three run
without a window and exit non-zero on failure, so they can gate a release.

### Reporting a bug

Press F9 at any time, in a match or in the menus. The game freezes over the frame you were
looking at and asks what happened. "Save report" writes a folder under the user data
directory (`%APPDATA%\Godot\app_userdata\BugRoyale\bug_reports\` on Windows) with that frame
as `screenshot.png`, a `report.json` holding the game version, map, mode, seed, your position,
the mode's status line, frame times and the last terrain edits, and the tail of the engine log
as `log.txt`. "Open folder" shows it so the whole folder can be attached to an issue or a
message. Esc or F9 closes the form. The autoload is `gui/bug_reporter.tscn`.

### Style

Every script follows the official
[GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html),
checked with `gdlint` and `gdformat` from
[gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) (a Python package):

```powershell
python -m pip install "gdtoolkit==4.*"
powershell -ExecutionPolicy Bypass -File tools/lint.ps1        # check
powershell -ExecutionPolicy Bypass -File tools/lint.ps1 -Fix   # reformat, then check
```

`gdlintrc` holds the settings: the guide's rules, with gdlint's own limits on returns per
function, public methods per class and lines per file switched off. The formatter fixes
indentation, spacing and line wrapping on its own. Two things it cannot fix are done by hand:
member order (`class_name`, `extends`, docstring, signals, enums, constants, static vars,
`@export`s, public then private vars, `@onready` vars, functions, inner classes last) and
lines over 100 columns inside comments or strings. Scripts under `addons/` are not ours and
are not checked.

### Unit tests

Written with [GUT](https://github.com/bitwes/Gut) 9.6.1, vendored in `addons/gut` and enabled
as an editor plugin. Suites live in `test/unit`:

| Suite | Covers |
|---|---|
| `test_terrain_edits.gd` | The voxel edit layer: sphere and box stamps, the one-voxel shell, placed materials, carving, no-change detection, the lattice origin, export/import, bounds |
| `test_block_snapping.gd` | Where the block tool lands a block for a hit: ground, stacked faces, side faces, odd and one-voxel sizes, 2 m voxels with an offset origin |
| `test_mode_state.gd` | Every mode's state snapshot survives a round trip onto a fresh mode (what a client will show the match from) |
| `test_damageable.gd` | Health rules: team immunity, the no-team case, dying once, kill credit, the host-only authority gate, revive |
| `test_horde_director.gd` | The noise meter: what fills it, how it fades, bot shots at a fraction, hordes on a full meter, after a lull and during a finale, growth up to the cap |
| `test_material_stock.gd` | The pickaxe stock: a carve pays out by material, a build spends it (the map's ground is dirt), never negative, and a build needs half its voxels in hand |
| `test_day_cycle.gd` | The day cycle's clock: daylight by the hour, twilight, dusk and dawn crossings, the time to the next change, where the sun stands |
| `test_world_save.gd` | Worlds on disk: a save round-trips with its voxel keys, seed and summary; delete removes it; nothing is written while saving is off |
| `test_queen_ant.gd` | The queen's nest plan: a shaft of carves stepping down and away from the entrance, the chamber below it, every carve the pickaxe's; the way she goes down ends on the chamber floor |
| `test_elements.gd` | The elements in the ground: the table lists each once with its symbol, number, depth and colour; under the topsoil the stone has ore pockets, each element only from its own depth down and the pockets a share of the stone; a seed always draws the same ore; a dug element lands in the stock and builds |
| `test_cave_carver.gd` | The seeded underworld: a seed always carves the same caves and every number lands in range; under a solid open terrain the surface is still the surface, there is air in the tunnels but the ground is mostly ground, and bedrock is solid |

GUT and `test/` are excluded from both export presets, so nothing test-related ships.

**From the command line** (the usual way, and what CI or the release script would run):

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

The script runs the style check first (skip it with `-SkipLint` on a machine without Python),
then the unit tests. It looks for a Godot console executable in `-Godot <path>`, then the
`GODOT` environment variable, then the 4.7.2 editor installed beside the project, then `godot`
on the PATH. Underneath it runs GUT's own runner, which you can also call directly, for example
to run one suite:

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit -gselect=test_block_snapping
```

`.gutconfig.json` holds the defaults (test folder, `test_` prefix, exit when done).

**From the editor** (Godot 4.6 or newer): the GUT panel sits in the bottom dock once the
project is open. Run All runs every suite; the script and inner-class pickers run one. The
panel needs Godot 4.6+ for its dock API; on an older editor the command line still works.

**Writing a test:** add `test_<thing>.gd` under `test/unit`, `extends GutTest`, and give it
functions named `test_...` using `assert_eq`, `assert_true`, `assert_almost_eq` and friends.
`before_each` runs before every test. Nodes created in a test go through `autofree` or
`add_child_autofree` so they are cleaned up. Do not give test scripts a `class_name`: that
would put them in the exported class cache. Keep tests to logic that needs no running match;
anything that needs a map belongs in the smoke test.

### Smoke test

`tools/smoke_test.tscn` loads a map with a mode exactly as the main menu would, lets it run for
a number of physics frames, and reports how far each fighter moved, how many shots it fired,
who died, whether the mode's state survives a snapshot round trip, and whether the terrain edit
log refuses an edit that would bury a fighter. Pass `-Smoke` to `tools/run_tests.ps1` to run
one match per mode, or run a single combination yourself:

```powershell
godot --headless --path . res://tools/smoke_test.tscn -- map=crawlspace mode=burrow frames=1800 clock=20
```

`tools/screenshot.tscn` is the same launcher with a window: it waits for the match to start,
then saves what the camera sees to a PNG and quits, for checking a look without playing to it.
`cam=x,h,z look=x,h,z` places a free camera (h metres above the ground there) and `hud=0`
hides the HUD:

```powershell
godot --path . res://tools/screenshot.tscn --resolution 1152x648 -- map=crawlspace mode=burrow frames=120 hud=0 cam=-60,20,-60 look=-30,0,-20 out=C:/temp/floor.png
```

Map ids: `battlefield`, `terrarium`, `crawlspace`.
Mode ids: `burrow`, `hold_out`, `slayer`. Slayer takes
`format=solo|skirmish|colony|big_colony` (skirmish otherwise). Add `drive=1` to
work the local player's controls as well. The result line starts with `SMOKE RESULT`. Headless
Godot cannot capture the mouse, so the local player's trigger is the one thing it never fires.

**Scaling runs.** The same harness measures how the game copes with crowds. `fighters=<n>`
overrides how many fighters the colony and solo formats spawn, and `brains=0`
switches the bots' AI off once the match starts. The result line carries `physics_ms` and
`process_ms` as average/worst frame times in milliseconds after a warm-up:

```powershell
godot --headless --path . res://tools/smoke_test.tscn -- map=battlefield mode=slayer format=colony frames=600 seed=7 fighters=96
```

Bots cost less the farther they are from every human: beyond 40 m their physics steps every
third frame, beyond 60 m they stop animating and casting shadows, and beyond 160 m they are
not drawn.

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
