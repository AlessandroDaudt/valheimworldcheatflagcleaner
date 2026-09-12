# Runbook operacional

Este procedimento é deliberadamente conservador: backup, parada, alteração, inicialização e validação. Ele pode ser usado por outra pessoa sem conhecer o histórico deste projeto.

## Pré-requisitos

- acesso administrativo ao host do servidor;
- acesso ao container ou à instalação BepInEx;
- espaço livre para pelo menos duas cópias comprimidas do mundo;
- uma cópia local deste repositório;
- janela para reiniciar o servidor;
- nenhuma senha ou token gravado em scripts, issues ou arquivos do projeto.

Substitua <container>, <mundo>, <volume> e <timestamp> pelos valores da instalação. Não execute comandos de escrita no mundo sem confirmar os caminhos.

## 1. Identificar o estado atual

Docker:

    docker inspect --format '{{.State.Status}} {{.State.Running}}' <container>
    docker exec <container> sha256sum /config/bepinex/plugins/CheatCleanup/CheatCleanup.dll

Anote o hash do plugin e o estado. Se o container já estiver parado, não há necessidade de pará-lo novamente.

## 2. Fazer e verificar o backup

Para a imagem deste projeto, o mundo fica em /config/worlds_local/<mundo>:

    docker exec <container> sh -c 'mkdir -p /config/backups && tar -czf /config/backups/<mundo>-before-clean-<timestamp>.tar.gz -C /config/worlds_local <mundo>'
    docker exec <container> sha256sum /config/backups/<mundo>-before-clean-<timestamp>.tar.gz

Copie o backup para fora do host ou para armazenamento de retenção. Verifique se ele abre como tar e contém o diretório do mundo. Registre o SHA-256 no ticket de operação, nunca uma senha.

O backup é o ponto de rollback. Não o apague até a validação final e um teste de entrada no jogo.

## 3. Parar e instalar

    docker stop --timeout 120 <container>
    docker cp artifacts/server-repair/CheatCleanup/CheatCleanup.dll <container>:/config/bepinex/plugins/CheatCleanup/CheatCleanup.dll
    docker cp artifacts/server-repair/Jotunn/Jotunn.dll <container>:/config/bepinex/plugins/Jotunn/Jotunn.dll

Se a instalação usa bind mount, copie para o diretório correspondente no host com o container parado. Não use docker cp e cópia no host ao mesmo tempo sem conferir qual caminho é realmente persistente.

## 4. Iniciar e aguardar o carregamento

    docker start <container>
    docker inspect --format '{{.State.Status}} {{.State.Running}}' <container>

Aguarde o log indicar que os chunks e ZDOs terminaram de carregar. Em mundos grandes isso pode levar alguns minutos. Não mate o processo durante o save automático.

## 5. Validar a limpeza

    docker exec <container> tail -n 400 /opt/valheim/bepinex/BepInEx/LogOutput.log

Confira os dois relatórios mais recentes:

- AUTO-WORLD: quantos objetos foram encontrados e quantos foram enfileirados/limpos;
- AUTO-WORLD-VERIFY: o resultado depois do save, que é a validação principal.

O estado aprovado deve mostrar flags cheated=0, queued=0 e 0 marked nos contadores de itens. O servidor deve permanecer running true.

Se houver contador diferente de zero:

1. não remova o backup;
2. salve o trecho do log com o identificador do objeto e o nome do prefab;
3. mantenha o servidor parado somente se houver evidência de falha de carregamento ou corrupção;
4. faça uma nova cópia do estado atual antes de uma segunda tentativa;
5. investigue a versão do jogo, do BepInEx e do plugin.

Não declare sucesso baseado apenas no primeiro relatório: o segundo relatório precisa confirmar o estado persistido.

## 6. Rollback

Se o servidor não iniciar ou o mundo não abrir corretamente, pare o container e restaure o diretório do mundo a partir do backup usando a ferramenta de restauração da instalação. Em uma instalação Docker simples, o padrão é extrair o tar em uma pasta temporária e substituir o diretório do mundo com o container parado, depois iniciar e validar novamente. Confirme o caminho absoluto antes de qualquer remoção ou substituição.

## 7. Diagnóstico comum

- FileNotFoundException para System.Private.CoreLib: o plugin foi compilado com referências do runtime errado. Recompile usando apenas as referências de assembly_valheim.dll e BepInEx compatíveis; não use tipos .NET do host como referência importada no patcher.
- O relatório mostra zero, mas o jogo mostra itens marcados: confirme que a sessão abriu o mesmo mundo, que o plugin está no volume persistente e que o servidor foi reiniciado depois da cópia.
- O relatório volta a mostrar flags após cada reinício: preserve os logs, faça outro backup e verifique se outro plugin está recriando a marcação ou se o jogo está carregando uma cópia diferente do mundo.
