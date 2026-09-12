# Operations runbook

This procedure is intentionally conservative: backup, stop, change, start, and validate. It is written so another operator can use it without access to any private server history.

## Prerequisites

- administrative access to the server host;
- access to the container or BepInEx installation;
- enough free space for at least two compressed world copies;
- a local checkout of this repository;
- a maintenance window for a server restart;
- no password or token stored in scripts, issues, or project files.

Replace <container-name>, <world-name>, <volume>, and <timestamp> with values from the target installation. Do not run write commands against a world until the paths have been confirmed.

Windows path examples should use generic placeholders such as C:\path\world name. Do not publish a real user profile, server name, world name, map name, IP address, or backup path.

## 1. Identify the current state

For Docker:

    docker inspect --format '{{.State.Status}} {{.State.Running}}' <container-name>
    docker exec <container-name> sha256sum /config/bepinex/plugins/CheatCleanup/CheatCleanup.dll

Record the plugin hash and service state. If the container is already stopped, do not stop it again.

## 2. Create and verify the backup

For an installation using the standard container paths, the world is under /config/worlds_local/<world-name>:

    docker exec <container-name> sh -c 'mkdir -p /config/backups && tar -czf /config/backups/<world-name>-before-clean-<timestamp>.tar.gz -C /config/worlds_local <world-name>'
    docker exec <container-name> sha256sum /config/backups/<world-name>-before-clean-<timestamp>.tar.gz

Copy the archive outside the repository or to retention storage. Verify that it opens as a tar archive and contains the expected world directory. Record the SHA-256 in the operations ticket, never a password.

The backup is the rollback point. Keep it until final validation and an in-game login test are complete.

## 3. Stop and install

    docker stop --timeout 120 <container-name>
    docker cp artifacts/server-repair/CheatCleanup/CheatCleanup.dll <container-name>:/config/bepinex/plugins/CheatCleanup/CheatCleanup.dll
    docker cp artifacts/server-repair/Jotunn/Jotunn.dll <container-name>:/config/bepinex/plugins/Jotunn/Jotunn.dll

If the installation uses a bind mount, copy to the corresponding host directory while the container is stopped. Do not use docker cp and host-side copying simultaneously without confirming which path is persistent.

## 4. Start and wait for loading

    docker start <container-name>
    docker inspect --format '{{.State.Status}} {{.State.Running}}' <container-name>

Wait for the log to show that chunks and ZDOs have finished loading. Large worlds may take several minutes. Do not terminate the process during an automatic save.

## 5. Validate the cleanup

    docker exec <container-name> tail -n 400 /opt/valheim/bepinex/BepInEx/LogOutput.log

Check the two most recent reports:

- AUTO-WORLD: how many objects were scanned and how many were queued or cleaned;
- AUTO-WORLD-VERIFY: the result after saving, which is the primary validation.

An approved result should show flags cheated=0, queued=0, and 0 marked in the item counters. The server should remain running true.

If any counter is non-zero:

1. keep the backup;
2. save the log section containing the object identifier and prefab name;
3. keep the server stopped only when there is evidence of a loading failure or corruption;
4. create another copy of the current state before a second attempt;
5. investigate the game, BepInEx, and plugin versions.

Do not declare success based only on the first report. The second report must confirm the persisted state.

## 6. Rollback

If the server does not start or the world does not open correctly, stop the container and restore the world directory from the backup using the installation's restore procedure. For a simple Docker installation, the usual pattern is to extract the archive into a temporary directory and replace the world directory while the container is stopped, then start and validate again. Confirm absolute target paths before any removal or replacement.

## 7. Common diagnostics

- FileNotFoundException for System.Private.CoreLib: the plugin was built with references from the wrong runtime. Rebuild using only compatible assembly_valheim.dll and BepInEx references; do not import host .NET types into the patcher.
- The report shows zero but the game still shows marked items: confirm that the session opened the same world, that the plugin is on the persistent volume, and that the server restarted after the copy.
- The report shows flags again after every restart: preserve the logs, create another backup, and check whether another plugin is recreating the marker or the server is loading a different world copy.
