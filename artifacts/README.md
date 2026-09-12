# Artefatos prontos

Os DLLs desta pasta são os artefatos operacionais que podem ser copiados para um servidor BepInEx:

- `server-repair/CheatCleanup/CheatCleanup.dll`: plugin de limpeza do mundo.
- `server-repair/Jotunn/Jotunn.dll`: dependência usada pelo plugin.

Antes de instalar, compare os hashes com os valores publicados no release ou com o build local. Não copie DLLs enquanto o mundo estiver em uso. O código de patch e as instruções de recompilação estão em `scripts/patch_cheatcleanup_server.ps1` e no README. As dependências oficiais do jogo não são distribuídas aqui.
