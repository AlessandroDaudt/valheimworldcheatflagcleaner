# Ready-to-use artifacts

The DLLs in this directory are operational artifacts that can be copied to a BepInEx server:

- server-repair/CheatCleanup/CheatCleanup.dll: world cleanup plugin.
- server-repair/Jotunn/Jotunn.dll: dependency used by the plugin.

Before installation, compare the hashes with the release or with a local build. Do not copy DLLs while the world is in use. The patcher and rebuild instructions are in scripts/patch_cheatcleanup_server.ps1 and the repository README. Official game dependencies are not distributed here.
