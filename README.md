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
  across, three chunks deep, dug at 1 m voxels), and every match's seed carves a new underworld into them
  (CaveCarver): worm tunnels from a few metres down, caverns from twenty, a few sinkholes
  open to the sky, on half the seeds ravines cut into the surface with leaning walls, and
  bedrock at the bottom; over the noise, regions of riddled and solid rock, depth bands
  parted by seams, bedding floors, shafts and, far down, halls. The terrarium is a 5 m tank on a coffee
  table in a room scaled to match. In the garden the soil in the raised beds is terrain
  too, dug and built on like the lawn. Whatever stands on the dirt (the crawlspace's piers
  and furnace, the garden's beds) has a footing of solid ground from bedrock up, so it
  stands firm whether the underside is solid with caves or, with the terrain's **Solid
  Underside** off, a sponge of 3D noise.
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
| `test_cave_carver.gd` | The seeded underworld: a seed always carves the same caves and every number lands in range; under a solid open terrain the surface is still the surface, the ground is metres below it wherever no cave is near, there is air in the tunnels but the ground is mostly ground, and bedrock is solid; lean regions stay solid, seams part the bands, floors cut the caverns but not the tunnels, shafts run vertical and halls open only in the deep band |
| `test_terraces.gd` | The seeded terraces: a seed always rolls the same ones and every number lands in range, never means the plain surface, always means the heights sit on the treads, and the sponge underside is scaled to metres |
| `test_surface_character.gd` | The seeded surface character: a seed always rolls the same one and every number lands in its range, neutral values are the plain noise exactly, a power above 1 lowers the ground and keeps it within the amplitude, a warp moves the hills within the amplitude, and a ridged mix lifts the crests |
| `test_sky_chunks.gd` | The chunk builder's short cut: a chunk wholly above the ground is filled from its column heights without a voxel pass, a chunk the surface crosses is not, and a placed solid or a built edit in the sky brings the voxel pass back; after a brush stroke a chunk's field is resampled only inside the stroke's box and matches one built whole |
| `test_mesh_blocks.gd` | A chunk meshed in blocks of eight cells merges into the surface the whole mesher makes, and after a brush stroke only the blocks the stroke's samples touched are meshed again, the rest kept, with the same surface as a fresh build |
| `test_footings.gd` | The footings under structures: solid from bedrock to the dirt where a 3D-noise underside is a sponge, kept clear of the caves under a solid one, dug as the map's own ground where a bed's soil digs as dirt, and sized by the terrain from its own bedrock to cover a footprint's corners |
| `test_cave_systems.gd` | The carved cave systems: a seed always rolls the same ones and as many as the map's area says, every mouth sits on the surface inside the bounds and opens the ground, the passages go down and are air along their centre lines, a prepared region sees only the segments in reach, and far from every passage there is nothing |
| `test_cave_water.gd` | The aquifers: a column's level is steady and in range or dry, about the rolled share of the map is wet, a wall of rock stands on the border between two cells of different levels and nowhere with the water off, and a chunk's water sheet lies at its columns' levels in cave air only |
| `test_loose_rock.gd` | The loose rock pass on a chunk's field: a lone solid sample with air all round it is cleared and a lump over the limit kept, a lump on a chunk seam is judged the same from both sides, rock built with the brush stays while rock a dig thinned goes, a row of cave chunks loses only rock and agrees on every shared face, and the limit travels in the settings |

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

`tools/cave_slice.gd` paints a seed's underworld as a vertical slice, one pixel a metre,
white where the cave carver puts air, without building a chunk: the fast way to see what
a seed's caves are made of. Headless, a second a seed:

```powershell
godot --headless --path . --script res://tools/cave_slice.gd -- seed=7 out=C:/temp/slice.png
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

### Terrain lab

`scenes/terrain_lab.tscn` is a map-sized open terrain (16 by 16 chunks of 32 m, three
deep, at 4 m voxels so a seed builds in a few seconds, with the noise rolled from the
seed) for seeing how procedural the ground and its caves are without loading a map. Open
it in the editor, select `TerrainWorld` and press **Build
Terrain** at the top of the inspector (the Terrain Editor plugin), then change anything:
with **Auto Rebuild In Editor** on, every toggle (caves, solid underside, noise, seed,
grid size, terraces) rebuilds the chunks on the spot, and **New Seed** beside the build
button rolls a new seed and builds it, on any terrain node (Ctrl+Z brings the old seed
back). **Randomize** goes further on an open terrain: it rolls a seed and draws the
Noise sliders from the Noise Roll ranges, writing the values into the inspector with
Noise Roll set to Fixed, so the sliders show exactly what built and can be nudged from
there; the grid, chunk and voxel sizes stay. The caves' numbers come the same way:
**Biomes** on the node is two lists of `Biome` resources, **Land Biomes** and **Cave
Biomes**, the kinds in `biomes/` (meadow, dryland, marsh and barrens on top; plain, mossy,
dripstone, fungal and crystal below). The land is cut into patches of a jittered grid,
**Land Patch Size** metres across with borders bent by a slow noise, and each patch draws
its kind from the list by the kinds' weights: a weight is how likely a patch is that kind
against the others (3 against 1 is three patches in four), 0 is never, one kind alone is
everywhere. A resource holds the kind's name, weight, tint (white at alpha 1 is the ground
as the shader draws it; a colour at alpha 0.5 is blended half over it), and for the caves
the depths it holds between (mossy 0 to 40 m, the deep kinds 40 m down, the first kind in
the list that holds standing in elsewhere), whether its rooms stand on pillars, and how
much of the seed's ceiling jag and floor rubble they get. A new kind is a new resource,
no code; add it to a list, or remove and reorder the kinds, in the inspector. The rebuild
line gives both lists as shares.
**Cave Roll** on the node is Seeded (rolled from the seed, as the maps do, with the
near-surface numbers drawn from the **Cave Range** pairs beside it: the tunnels' start
depth, their ramp and the shallow cutoff, each a least and most, one value forcing it on
every seed) or Fixed (the
Cave Roll sliders as set: tunnel and cavern band, frequency and depth, regions, bands,
seams, floors, halls, shafts, ravines, warp), and Randomize writes the roll into the
sliders either way, leaving the switch as it is: on Seeded the sliders show what the
seed built, and switching to Fixed carves that roll and lets it be nudged. The rebuild
line in the Output panel says what the seed rolled:
its terraces, if any, and its caves and ravines.

Every seed also rolls a **Character** for the surface, so seeds differ in kind and not only
in where the hills are (plain noise draws every world from one distribution, which is why
generated ground comes to feel predictable): a redistribution power between 0.7 and 1.6
(above 1 the valleys flatten into plains and the hills grow fewer and taller, below 1
plateaus), on half the seeds a domain warp of 10 to 40 m that stretches the round blobs of
noise into curved ridges and bays, and on a third a ridged mix that puts sharp crests along
lines. The ranges and chances are under **Character** on the `TerrainWorld` node; **Plain**
turns it all off, and a chance of 1 with a narrow range forces one trait to study it. The
rebuild line names what the seed rolled. These come from the techniques in Red Blob Games'
terrain-from-noise notes.

Over that, a seed layers more, each layer a group on the `TerrainWorld` node with a
switch, a chance and ranges, and each named in the rebuild line:

- **Noise Roll** (off by default; the lab turns it on): **Seeded** ignores the Noise
  sliders and draws the frequency, amplitude, octaves, lacunarity and gain from ranges,
  so one seed's hills are 250 m across and smooth and another's 100 m and craggy. The
  garden and the crawlspace keep **Fixed**: their lawn and dirt are tuned by hand.
- **Regions**: a very slow noise (one swell 500 to 900 m across, so a map holds one or
  two) says where the lowlands and the highlands are. The lowlands keep a tenth to a
  third of the amplitude, the highlands turn ridged and carry finer detail, and the warp
  grows with the mask, so one seed is a plain with a range in the corner and the next a
  ridge through the middle. With it comes a height curve: on six seeds in ten a hard
  floor fills the valleys flat like sediment (GPU Gems 3's hard floor), and on half a
  cliff band puts the climb into a steep span with flat spans below and above, plains
  and a plateau, the way Minecraft's terrain splines do. Both keep the height rising
  with the noise, so a hill is still a hill, reshaped.
- **Relief**: on six seeds in ten, 3D noise added to the density within a few metres of
  the surface on faces steeper than about 30 degrees, so cliffs get lips, undercuts and
  overhangs that a height alone can never make (GPU Gems 3's density terrains). It fades
  out with distance from the surface and on gentle ground, so nothing is hollowed and
  nothing floats. With it, two to four **flat spots**: landings 8 to 14 m across where
  the ground is blended level, fading into the land over 10 m; colony nests go on them.
- The caves' noises are read through a slow **warp** of 4 to 10 m on every seed, so the
  tunnels bend and the ravines wander instead of following the noise's own lines.
- Noise alone carves the same sponge everywhere, so the seed lays structure over the
  caves too. **Regions**: a 3D noise 150 to 400 m across says where the rock is riddled
  and where it is lean, solid on half the seeds and sparse on the rest, so a map has
  cave country and dead rock. **Depth bands**, Terraria's layers: burrow ground, then
  tunnels, coming in by count rather than width (at their start depth, 6 to 12 m down,
  they run only in a few patches of a slow map, and the patches spread over the next 20
  to 40 m until the tunnels run everywhere, so the top of the ground is mostly ground),
  then caverns, then from 120 to 260 m down a deep band where the tunnels thin
  and the rooms grow, with **seams** of near-solid rock a few metres thick between the
  bands, bent by a slow wave so they undulate like beds. The tunnels themselves are few
  and wide on purpose, 40 to 70 m apart and several metres across from a single octave
  of noise: with two octaves and 20 to 45 m apart a vertical slice crossed over two
  hundred of them, seven in ten crawls under 2 m wide, and the ground read as a sponge;
  the retune cut that to a quarter at the same share of air. A **thickness** noise
  swells the tunnels into chambers and pinches them to crawls along their length
  (Minecraft's spaghetti thickness). The caverns are wider than they are tall and, on six seeds in
  ten, cut by **bedding floors** every 24 to 48 m, so the rooms have floors to stand on;
  the tunnels run through them. **Halls**: a very slow noise opens a chamber or two a
  world in the deep band, far bigger than any cavern. **Shafts**: in spots a map picks,
  vertical pits run from the tunnels to bedrock through the seams, tying the bands
  together. **Carved systems**, Minecraft's old carver beside its noise caves: a seed's
  handful of passages (ten to twenty-four a square kilometre) each start at a mouth on
  the steepest ground of a few candidates, a hillside or cliff face, and worm down as a
  random walk of capsules that curves with a persistent lean, swells and pinches,
  branches now and then and ends in a chamber, cutting through bands, seams and regions
  alike. Noise cannot give an entrance that leads somewhere, a passage with a direction
  or a dead end; these do. **Ceilings and floors** differ, as in a real cave: fine noise
  hangs from a room's ceiling in points and folds, 0.8 to 2 m deep by the seed, and scree
  bumps its floor, which side being read from the cavern noise's own slope. **Biomes**,
  Minecraft's lush and dripstone caves: patches 250 m across say what kind of cave
  the rock is in, mossy or plain within 40 m of the surface and plain, dripstone, fungal
  or crystal below, and the walls take the biome's tint half-blended over the shader's
  rock; dripstone rooms stand on pillars a metre thick. Which biome a patch is comes
  from the weights on the node (BiomePatches), so a map can be mostly plain with the odd
  crystal cave, or all fungal. **Aquifers**, Minecraft's: the
  map is cut into cells 120 to 220 m across, four to eight in ten holding water to a level
  of their own between bedrock and 15 m under the surface, and any cave air below the
  level is a pool, drawn as a flat sheet with the terrarium's water; between two cells of
  different levels a wall of rock 3 m thick keeps the pools apart, as Minecraft's aquifer
  barriers do. The pools are a sight for now, not a swim. On faces steeper than about 30
  degrees the tunnels run right up to the surface and open on it, so cliffs and steep
  hillsides have **cave mouths** where you expect them, while flat ground keeps its burrow
  depth. Where two features meet, their air blends over 2 m, so a tunnel joins a room
  or crosses a floor in a rounded mouth instead of leaving a sliver of wall thinner than
  a voxel (the floating pieces those made: at 1 m voxels the blend takes five in six of
  them away). What still floats is mostly the grid's own, a wall thinner than two voxels
  sampled into a lone solid cell, and the chunk builder clears it before meshing: **Loose
  Rock Voxels** under Meshing on the node (8 by default, 0 for none) is the biggest lump
  of rock with air all round it that goes, unless the brush built it. A lump on a chunk
  seam is judged the same from both sides, so the meshes never part, which means a lump
  reaching more than a voxel past a seam stays. On the lab's slab at 4 m it takes 71 of
  79 floating pieces, at 2 m 74 of 77, for a twentieth of the sampling time; what a dig
  cuts loose and leaves under the limit vanishes too, uncredited to the stock. The
  rebuild line names every number, and `tools/cave_slice.gd` paints a seed's slice in a
  second to see them.
- The ground shader draws **strata** on the rock faces: a dark band every 2.5 m of
  altitude, bent by a slow noise so the beds tilt and fold.

For a deep world, **Surface Layer** on the `TerrainWorld` node moves the surface from the
box's centre (the maps, half sky and half ground) to the middle of a chosen chunk layer
counted from the top, so every layer added below is ground. The caves' widening with
depth stops at 50 m (1.3 times their size, the maps' own bottom), so the deep layers are no
emptier than that. To
see the underground in cross-section, set the grid to 16 by 16 by 3, Surface Layer 2 and
Boxed Edges off: the slab's sides are open cuts, and the editor camera off to one side
sees the caves sliced through.

The layers cost little per column, but a tall seed spreads the surface through every
chunk layer, so none are sky and the cave pass runs everywhere: a 512 m seed with
everything on builds in about 2.5 s at 4 m voxels, 16 s at 2 m and 80 s at 1 m,
headless on four threads.

The inspector sliders under **Noise** stop at the ranges a map may be randomised over,
the values that still make good ground: frequency 0.004 to 0.01 (hills 250 m to 100 m
across), amplitude 0 to 40 m, one to five octaves, gain 0.3 to 0.65 (smooth swells to
craggy detail), lacunarity 1.8 to 2.6, and the surface offset 8 m either way. Frequency
and amplitude set the slope together: 12 m on 200 m hills is a 20 degree roll, 36 m a 45
degree mountainside, and past that at 2 m voxels the shape goes blocky, so raise one and
lower the other. The surface sits at the box's centre and nothing is built above the top
chunk, so amplitude plus offset must stay under half the box height (48 m on the maps) or
the peaks come out flat-topped. Code may still set any value; the ranges bind the
sliders, not the setters.

Terraces are a seeded feature of every open terrain, under **Terraces** on the
`TerrainWorld` node: by default two seeds in five step their hills into shelves, with a
tread height, a strength (soft benches to flat treads with steep risers) and a phase of
their own, over about half the ground, a slow noise choosing which half. **Always** forces a
seed's terraces on to see them, **Never** turns them off. They are drawn in the height
function, so structures, footings and spawns stand on the shelves. The ground is a true
distance field on both sides of the surface, so these are the only terraces: the voxel
stair-steps that steep slopes used to show were the mesher interpolating between a capped
value inside the ground and metres outside it. Fly the editor camera below the surface to see the tunnels and caverns: terrain
faces only draw from the air side, so rock is see-through from inside. At 4 m voxels the
tunnels (4 to 8 m across) resolve coarsely and their thin ends drop out; 2 m is
the honest cross-section, or `tools/cave_slice.gd` for the raw field in a second. The built chunks
are dropped before the scene is saved and rebuilt after, so the file stays small.

### Mode tuning

Each mode is a one-node scene in `modes/` (`burrow.tscn`, `hold_out.tscn`, `slayer.tscn`)
carrying the mode script, and the loading screen instantiates that scene onto the map. Every
number a mode runs on is an exported property of that node: open the scene, select the root,
and the inspector shows them in groups (Burrow: Match, Hornets, Husks, Raiders, Spiders,
Colony, Founding, Food, Eggs; Hold Out: squad size, build timers, approaches; Slayer and the
competitive base: team names and colours, the clock, respawn and kill limits), each with its
doc comment as the tooltip. The script holds the default; the scene saves only the values
that differ, and the inspector's reset arrow goes back to the script's number. Identifiers
stay constants in the code: team numbers, group names, the found-colony action, scene paths.

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
