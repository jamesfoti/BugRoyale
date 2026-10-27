BugRoyale
=========

Battle of the bugs: a third-person shooter where you are an inch tall. Every map is a slice
of the human world at bug scale, built procedurally in GDScript on a voxel terrain you can dig
and climb. Made with Godot 4.7.

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

Open the project in Godot 4.7 and press Play. The main scene is `scenes/main_menu.tscn`.

Build
-----

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_desktop.ps1
```

Exports `builds/windows/BugRoyale.exe` (plus a zip) and `builds/macos/BugRoyale.zip`,
downloading the Godot export templates on first run. Pass `-WindowsOnly` or `-MacOSOnly` for
one platform. Windows and macOS are the only supported platforms; the builds folder is not
committed.

Tools
-----

Bug models are generated in Blender by `tools/blender/create_bugs.py`.

Credits
-------

Textures from https://ambientcg.com/  
Sound effects partly from https://sonniss.com/gameaudiogdc
