# Arquitetura

## Aplicativo de personagem

src/valheim_cheat_flag_cleaner/save_format.py implementa a leitura e escrita do formato binário de personagem .fch, incluindo a verificação de integridade. valheim_cheat_cleaner.py usa esse parser para:

- localizar itens marcados;
- produzir um relatório legível ou CSV/JSON;
- criar uma cópia limpa sem sobrescrever a origem;
- inspecionar um arquivo tar do mundo apenas para inventário e metadados disponíveis.

## Reparação do mundo

O plugin BepInEx opera no processo do servidor depois de ZNet e ZDOMan estarem prontos. A sequência é:

1. enumerar todos os ZDOs carregados;
2. remover s_cheated e flags pendentes do objeto;
3. interpretar payloads de inventário persistente e estruturas que armazenam itens;
4. remover a marcação do item sem excluir o item nem alterar stack/quantidade;
5. marcar setores e portais como alterados;
6. salvar o mundo;
7. executar uma verificação e registrar contagens em AUTO-WORLD-VERIFY.

O save/verify serve para detectar o caso em que uma limpeza apenas em memória parece funcionar, mas não foi persistida no arquivo do mundo.

## Reprodutibilidade

O patcher usa Mono.Cecil para ligar as chamadas às assinaturas da versão local de assembly_valheim.dll. Por isso, o DLL original do jogo deve ser da mesma versão do servidor. O arquivo oficial não é distribuído neste repositório; é uma entrada local em vendor/.
