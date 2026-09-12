# Valheim World Cheat Flag Cleaner

Tools for locating and removing cheat-item markers from character saves and for repairing markers persisted in Valheim dedicated-server world objects (ZDOs).

The project has two complementary components:

1. valheim_cheat_flag_cleaner: a Python desktop application and CLI for character .fch files. It creates cleaned copies and preserves the original file.
2. artifacts/server-repair/CheatCleanup/CheatCleanup.dll: a BepInEx dedicated-server plugin. After the world has loaded, it scans ZDOs, clears s_cheated and queued flags, cleans persistent inventory payloads, and verifies the result after saving.

The character application does not rewrite world chunks. For chests, stands, carts, structures, and other objects persisted in the world, use the server plugin.

## Security and scope

- Make a backup before every run.
- Stop the server before replacing DLLs or manipulating world files.
- Never commit passwords, tokens, private IP addresses, world copies, or .fch files.
- Official game binaries and local build dependencies belong in vendor/, which is ignored by Git.
- The plugin is intended to clear cheat flags only; it should not remove items or change quantities.
- Keep the backup until the world opens correctly and the verification report shows zero flags.
- Replace every example placeholder with the values for your own installation. Do not publish those values in this repository.

## Local use

Requires Python 3.11 or newer. Runtime dependencies are limited to the Python standard library.

PowerShell setup:

    py -3 -m venv .venv
    .\.venv\Scripts\Activate.ps1
    $env:PYTHONPATH = "$PWD\src"
    python -m unittest discover -s tests -v

To open the Windows desktop application:

    scripts\run_cheat_cleaner.cmd

CLI examples:

    $env:PYTHONPATH = "$PWD\src"
    python -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner scan "C:\path\character saves"
    python -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner clean "C:\path\character saves" --clear-profile-flag
    python -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner world-info "C:\path\world name\world-backup.tar.gz"

The clean command writes copies with a safety suffix. Review the output before replacing any original save.

## Docker server operation

The paths and names below are placeholders. Replace them with values from your own installation. The complete runbook is in docs/OPERATIONS.md.

### 1. Check the container and create a backup

    docker inspect --format '{{.State.Status}} {{.State.Running}}' <container-name>
    docker exec <container-name> sh -c 'mkdir -p /config/backups && tar -czf /config/backups/<world-name>-before-clean-<timestamp>.tar.gz -C /config/worlds_local <world-name>'
    docker exec <container-name> sha256sum /config/backups/<world-name>-before-clean-<timestamp>.tar.gz

Copy the archive to safe storage outside the repository and record its SHA-256 checksum.

### 2. Install the plugin

With the container stopped, copy these artifacts to the BepInEx plugin directory:

    artifacts/server-repair/CheatCleanup/CheatCleanup.dll
    artifacts/server-repair/Jotunn/Jotunn.dll

For Docker, one way to copy them is:

    docker cp artifacts/server-repair/CheatCleanup/CheatCleanup.dll <container-name>:/config/bepinex/plugins/CheatCleanup/CheatCleanup.dll
    docker cp artifacts/server-repair/Jotunn/Jotunn.dll <container-name>:/config/bepinex/plugins/Jotunn/Jotunn.dll

Do not replace DLLs while the world is in use. For a non-Docker server, copy the same files to that installation's BepInEx/plugins directory.

### 3. Stop, start, and validate

    docker stop --timeout 120 <container-name>
    docker start <container-name>
    docker inspect --format '{{.State.Status}} {{.State.Running}}' <container-name>
    docker exec <container-name> tail -n 300 /opt/valheim/bepinex/BepInEx/LogOutput.log

Wait for the world to finish loading. Look for the AUTO-WORLD and AUTO-WORLD-VERIFY reports. The expected result is:

    flags cheated=0, queued=0
    ... items ... 0 marked

The second report confirms the state after the world has been saved and reloaded in memory. If flags appear again, make another backup before retrying and investigate the diagnostic object line.

## Rebuilding the server plugin

The ready-to-use DLL is kept in the repository for repeatable operations. To rebuild it, obtain from legitimate sources:

- the original CheatCleanup.dll compatible with the server version;
- Mono.Cecil.dll from the BepInEx installation used by the server;
- assembly_valheim.dll from the same game/server version.

Place these files locally at:

    vendor/CheatCleanup/CheatCleanup.dll
    vendor/BepInEx/Mono.Cecil.dll
    vendor/assembly_valheim.dll

Then run:

    pwsh -File .\scripts\patch_cheatcleanup_server.ps1

Or pass explicit paths with -InputDll, -CecilDll, and -ValheimDll. The output is written to artifacts/server-repair/CheatCleanup/CheatCleanup.dll. Files in vendor/ must never be committed.

## Repository layout

    src/valheim_cheat_flag_cleaner/  .fch parser and cleaner
    tests/                            round-trip and cleaning tests
    scripts/                          Windows launcher and plugin patcher
    artifacts/server-repair/          ready-to-install server DLLs
    docs/                             operations runbook and architecture notes

## License

MIT. See LICENSE.
