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
