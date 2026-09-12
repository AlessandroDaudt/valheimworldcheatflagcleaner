# Architecture

## Character application

src/valheim_cheat_flag_cleaner/save_format.py implements reading and writing of the Valheim .fch character format, including integrity verification. valheim_cheat_cleaner.py uses the parser to:

- locate marked items;
- produce human-readable, CSV, or JSON reports;
- create a cleaned copy without overwriting the source;
- inspect a world archive for available inventory and metadata without modifying it.

## World repair

The BepInEx plugin runs inside the server process after ZNet and ZDOMan are ready. Its sequence is:

1. enumerate all loaded ZDOs;
2. remove s_cheated and queued flags from the object;
3. parse persistent inventory payloads and item-bearing structures;
4. remove the item marker without deleting the item or changing its stack/quantity;
5. mark sectors and portals dirty;
6. save the world;
7. run a verification pass and write counts to AUTO-WORLD-VERIFY.

The save/verify sequence detects cases where an in-memory cleanup appears successful but was not persisted to the world files.

## Reproducibility

The patcher uses Mono.Cecil to bind calls to the signatures in the local assembly_valheim.dll. The official game assembly must therefore match the server version. It is not distributed in this repository; it is a local input under vendor/.
