# Valheim World Cheat Flag Cleaner

Ferramentas para localizar e remover marcações de item cheatado em saves de personagem e para reparar as marcações persistidas nos objetos (ZDOs) de um mundo Valheim dedicado.

O projeto tem dois componentes complementares:

1. valheim_cheat_flag_cleaner: aplicativo Python com interface gráfica e CLI para arquivos .fch de personagem. Ele cria cópias limpas e preserva o arquivo original.
2. artifacts/server-repair/CheatCleanup/CheatCleanup.dll: plugin BepInEx para servidor dedicado. Após o carregamento do mundo, percorre os ZDOs, limpa s_cheated e flags pendentes, limpa payloads de inventários persistentes e verifica o resultado após o save.

O aplicativo de personagem não regrava chunks do mundo. Para baús, suportes, carrinhos, estruturas e demais objetos persistidos no mundo, use o plugin do servidor.

## Segurança e escopo

- Faça um backup antes de cada execução.
- Pare o servidor antes de substituir DLLs ou manipular arquivos do mundo.
- Nunca coloque senha, token, IP privado, cópia do mundo ou arquivos .fch no Git.
- Os binários oficiais do jogo e as dependências locais de build ficam em vendor/, que é ignorado pelo Git.
- O plugin foi projetado para limpar apenas flags de cheat; ele não deve remover itens nem alterar quantidades.
- Mantenha o backup até confirmar que o mundo abre corretamente e que o relatório de verificação mostra zero flags.

## Uso local

Requer Python 3.11 ou mais recente. Não há dependências de runtime além da biblioteca padrão.

Uso no PowerShell:

    py -3 -m venv .venv
    .\.venv\Scripts\Activate.ps1
    $env:PYTHONPATH = "$PWD\src"
    python -m unittest discover -s tests -v

Para abrir a interface gráfica no Windows:

    scripts\run_cheat_cleaner.cmd

Exemplos de CLI:

    $env:PYTHONPATH = "$PWD\src"
    python -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner scan "C:\caminho\characters_local"
    python -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner clean "C:\caminho\characters_local" --clear-profile-flag
    python -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner world-info "C:\backup\PowerGuido.tar.gz"

O comando clean grava cópias com sufixo de segurança; confira a saída antes de substituir qualquer save original.

## Operação em servidor Docker

Os caminhos abaixo são exemplos. Ajuste o nome do container, o caminho do volume e o nome do mundo para a instalação de cada servidor. O runbook completo está em docs/OPERATIONS.md.

### 1. Confirmar o container e fazer backup

    docker inspect --format '{{.State.Status}} {{.State.Running}}' valheim-server
    docker exec valheim-server sh -c 'mkdir -p /config/backups && tar -czf /config/backups/PowerGuido-before-clean-YYYYMMDD-HHMMSSUTC.tar.gz -C /config/worlds_local PowerGuido'
    docker exec valheim-server sha256sum /config/backups/PowerGuido-before-clean-YYYYMMDD-HHMMSSUTC.tar.gz

Copie o arquivo para um local seguro fora do repositório e registre o SHA-256.

### 2. Instalar o plugin

Com o container parado, copie estes artefatos para o diretório de plugins BepInEx:

    artifacts/server-repair/CheatCleanup/CheatCleanup.dll
    artifacts/server-repair/Jotunn/Jotunn.dll

Em Docker, uma forma de copiar é:

    docker cp artifacts/server-repair/CheatCleanup/CheatCleanup.dll valheim-server:/config/bepinex/plugins/CheatCleanup/CheatCleanup.dll
    docker cp artifacts/server-repair/Jotunn/Jotunn.dll valheim-server:/config/bepinex/plugins/Jotunn/Jotunn.dll

Não substitua DLLs com o mundo em uso. Se o servidor não usa Docker, copie os mesmos arquivos para o diretório BepInEx/plugins da instalação dedicada.

### 3. Parar, iniciar e validar

    docker stop --timeout 120 valheim-server
    docker start valheim-server
    docker inspect --format '{{.State.Status}} {{.State.Running}}' valheim-server
    docker exec valheim-server tail -n 300 /opt/valheim/bepinex/BepInEx/LogOutput.log

Aguarde o carregamento completo do mundo. Procure os relatórios AUTO-WORLD e AUTO-WORLD-VERIFY. O resultado esperado é:

    flags cheated=0, queued=0
    ... items ... 0 marked

O segundo relatório é importante: ele confirma o estado depois que o mundo foi salvo e recarregado em memória. Se houver flags novamente, faça outro backup antes de qualquer nova tentativa e investigue a linha de diagnóstico do objeto.

## Recompilar o plugin de servidor

O DLL pronto é mantido no repositório para operação reproduzível. Para recompilar, obtenha de fontes legítimas:

- o CheatCleanup.dll original compatível com a versão do servidor;
- Mono.Cecil.dll do BepInEx usado pelo servidor;
- assembly_valheim.dll da mesma versão do jogo/servidor.

Coloque esses arquivos localmente em:

    vendor/CheatCleanup/CheatCleanup.dll
    vendor/BepInEx/Mono.Cecil.dll
    vendor/assembly_valheim.dll

Depois execute:

    pwsh -File .\scripts\patch_cheatcleanup_server.ps1

Ou passe caminhos explícitos com -InputDll, -CecilDll e -ValheimDll. O resultado é gravado em artifacts/server-repair/CheatCleanup/CheatCleanup.dll. Os arquivos em vendor/ nunca devem ser commitados.

## Estrutura

    src/valheim_cheat_flag_cleaner/  parser e limpador de arquivos .fch
    tests/                            testes de round-trip e limpeza
    scripts/                          launcher Windows e patcher do plugin
    artifacts/server-repair/          DLLs prontas para o servidor
    docs/                             runbook operacional e arquitetura

## Licença

MIT. Consulte LICENSE.
