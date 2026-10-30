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
- **Maps:** Celestial Body, Terrarium, Fish Bowl, Crawlspace, Backyard Garden.
- **Modes:** Attack of the Hornets (co-op waves), Ants vs Ants (team deathmatch),
  Battle Royale (rising flood), Cordyceps Royale (a spore storm turns the fallen into husks
  that hunt you), Forage (extraction: a dragonfly drops your squad on hostile ground; gather
  the quota quietly, because noise brings the horde, and ride the dragonfly out), Explore.

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
- [ ] Host-authoritative combat and mode state: damage, deaths, scores, hornet waves, the flood
  height, the spore circle and husk conversions all decided once and replicated. Clients show
  shot visuals immediately and accept the verdict.
- [ ] Bots run only on the host and are replicated like any other fighter; lobbies fill with
  bots when short of players.
- [ ] Per-mode stats that survive a restart (best hornet wave per map, royale wins, colony
  records) shown on the mode picker.
- [ ] A pass through every mode on every map (thirty combinations) before any release.
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

Tests
-----

Three layers: a style check against the GDScript style guide, unit tests for the rules and
arithmetic, and a headless smoke test that plays a whole bot match per mode. All three run
without a window and exit non-zero on failure, so they can gate a release.

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
godot --headless --path . res://tools/smoke_test.tscn -- map=crawlspace mode=cordyceps_royale frames=1800
```

Map ids: `battlefield`, `celestial_body`, `terrarium`, `fishbowl`, `crawlspace`. Mode ids:
`hornets`, `ants_vs_ants`, `battle_royale`, `cordyceps_royale`, `forage`, `explore`. Add `drive=1` to
work the local player's controls as well. The result line starts with `SMOKE RESULT`. Headless
Godot cannot capture the mouse, so the local player's trigger is the one thing it never fires.

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
