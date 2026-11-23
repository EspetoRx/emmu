> Manual operacional para qualquer agente de IA que vá ler, manter ou corrigir o Emmu.
> Para contexto humano, comece pelo [`README.md`](README.md). Para contexto de código, este arquivo é a fonte mais rápida.

---

## 0. Regra de ouro

Antes de alterar código, responda mentalmente a três perguntas:

1. **O problema é no web, no desktop ou nos dois?** Os backends são diferentes — e N64, NDS e PSP são diferentes dos dois.
2. **Qual core está envolvido?** Cada console tem um crate, um WASM e um caminho Mesen próprios.
3. **A mudança precisa de rebuild de WASM, bridge JS, runtime Mesen/SDL ou gitlink de submódulo?**

Se não souber a resposta, pergunte ao usuário **qual ROM, qual plataforma e qual tela**. Não tente “corrigir” os dois backends às cegas.

**Atenção PSP:** o PPSSPP roda na **main thread** do WebView (web e desktop), não no `snes.worker.js` e não no Mesen. Se o bug é de PSP, abra `crates/emmu-psp/js/adapter.js` e `snes.js::createEmulator` antes de tocar no worker.

---

## 1. Resumo em 60 segundos

| Item | Fato |
| --- | --- |
| UI | Vue 3 + Vite 6 em `platforms/web/ui`, compartilhada por web, Tauri desktop e scripts mobile |
| Web | Web Worker (`snes.worker.js`) + onze pacotes WASM gerados por `wasm-pack`; PSP roda na **main thread** com WebGL2/pthreads |
| Desktop | Tauri 2 + Rust; emulação via MesenCE (`emmu-mesen-sys`), **exceto N64, NDS e PSP**, que rodam o mesmo runtime no WebView |
| Consoles | NES, SNES, GBA, GB, GBC, GG, SMS, WS/WSC, PCE, NDS, N64 e PSP |
| Persistência | IndexedDB `emmu-library` v2; `localStorage` para filtros e controles |
| Save states | `EMMUGMB1`, `EMMUGBC1`, `EMMUGG01`, `EMMUSMS1`, `EMMUWS01`, `EMMUPCE1`, `EMMUSAVE1`, `EMMUNDS1`, `EMMUPSP1`, bincode/TetaNES no web; `.mss` no desktop; gzip `/savestate.gz` no N64 |
| Frames web | RGBA8888 via `putImageData` (NDS empilha 256×192 + 256×192 em 256×384; PSP usa canvas WebGL próprio 480×272 na main thread) |
| Frames desktop | BMP 24-bit via protocolo `emmu-frame://`; miniatura via PNG gerado no Rust; N64/NDS/PSP fora desse protocolo |
| Cores GPL | GB, GBC, GG, SMS, PCE e NDS (dust) no web; Mesen no desktop; N64 (Emmu); PSP (PPSSPP, GPL-2.0-or-later) |
| Cores MIT/permisivos | NES, SNES, GBA e WS (Swanium) no web; N64Wasm (vendor, MIT) |
| Submódulos | Todos os crates e plataformas antigos são submódulos; `crates/emmu-ws` é diretório local até receber remote; `crates/emmu-n64`, `crates/emmu-nds` e `crates/emmu-psp` são submódulos de `EspetoRx` |
| Versão UI | `0.2.0` — inclui NDS, N64, PSP, toasts e analógico |

---

## 2. Ordem de leitura recomendada

Para entender o projeto rapidamente, nesta ordem:

1. `README.md` — visão geral, builds e licenças.
2. `AGENTS.md` — este arquivo.
3. `platforms/web/ui/src/composables/snes.js` — decide web vs desktop e cria o cliente de emulação.
4. `platforms/web/ui/src/composables/useEmulator.js` — facade usada pelo player.
5. `platforms/web/ui/src/workers/snes.worker.js` — protocolo do worker.
6. `platforms/desktop/src/lib.rs` — comandos Tauri, frames, save states e menu.
7. `crates/emmu-mesen-sys/src/lib.rs` — ABI e wrappers do Mesen.
8. O `README.md` do core específico envolvido no bug (para N64, `crates/emmu-n64/README.md` e `UPSTREAM.txt`; para NDS, `crates/emmu-nds/README.md` e `UPSTREAM.txt`; para PSP, `crates/emmu-psp/README.md`, `UPSTREAM.txt` e `js/adapter.js`).

---

## 3. Mapa de decisão: “onde eu mexo?”

| Sintoma / tarefa | Primeiro arquivo a abrir | Segundo arquivo |
| --- | --- | --- |
| Extensão de ROM não abre | `platforms/web/ui/src/App.vue` | `platforms/web/ui/src/composables/useLibrary.js` |
| Console errado é detectado | `platforms/web/ui/src/composables/snes.js` (`createEmulator`) | `platforms/desktop/src/lib.rs` (`mesen_init_rom`) |
| Teclado não responde / botão gruda | `platforms/web/ui/src/composables/useShortcuts.js` | `useEmulator.js::setButton` |
| Controle touch errado | `platforms/web/ui/src/components/Player.vue` | `useEmulator.js::setButton` |
| GG sem áudio/vídeo no web | `crates/emmu-gg/src/lib.rs` (`default_config`) | `smsgg-core` em `vendor/jgenesis` |
| GG com frame 256x240 no desktop | `crates/emmu-mesen-sys/src/lib.rs` (`SMS_GAME_GEAR_OVERSCAN`) | `platforms/desktop/src/lib.rs` (`mesen_init_rom`) |
| SMS sem áudio/vídeo no web | `crates/emmu-sms/src/lib.rs` (`default_config`) | `smsgg-core` em `vendor/jgenesis` |
| WS lento/áudio desafinado no web | `crates/emmu-ws/src/lib.rs` (`cycle_carry`) | `swanium-core::system::CYCLES_PER_FRAME` |
| Segundo direcional WS não responde | `useEmulator.js::coreButtonForFormat` | `Player.vue` / `ControlsDialog.vue` |
| WS desktop com frame 224x157 ou sem áudio | `crates/emmu-mesen-sys/src/lib.rs` (`connect_ws_controllers`) | `platforms/desktop/src/lib.rs` (`mesen_init_rom`) |
| Setas PCE travadas | `crates/emmu-pce/src/lib.rs` (`default_config`) | `input.rs` do vendor JGenesis |
| PCE com tela preta no desktop | `crates/emmu-mesen-sys/src/pce_palette.rs` | `connect_pce_controllers` |
| Sem imagem no desktop | `platforms/desktop/src/lib.rs` (`frame_as_bmp`, `emmu-frame`) | notificações do Mesen |
| Miniatura desktop ausente | `MesenTauriClient.capturePreview()` em `snes.js` | `mesen_capture_preview` em `platforms/desktop/src/lib.rs` |
| Sem áudio no web | `platforms/web/ui/src/workers/audio-worklet.js` | `useAudio.js` |
| Sem áudio no desktop | SDL2 runtime e `configure_audio` | `mesen_set_volume` |
| Save state não carrega | magic/version do core | `useEmulator.js` / `libraryStore.js` |
| Biblioteca não mostra progresso real | `useLibrary.js` | `LibraryLoadingOverlay.vue` |
| GBA web quebrado após atualizar vendor | `crates/emmu-gba/tools/build-bridge.mjs` | `src/bridge.template.js` |
| Build WASM desatualizado | `platforms/web/ui/package.json` (`build:wasm`) | diretório `src/wasm/` |
| Erro de link Mesen | `crates/emmu-mesen-sys/build.rs` | `scripts/build-sdl2.sh` |
| Gitlink sujo | submódulo específico | repositório principal |
| Instalador sem SDL2/Mesen/N64Wasm/licença dust | `resources` ou runtime não preparado | `platforms/desktop/scripts/prepare-bundle.sh` + `tauri.conf.json` (`bundle.resources`) |
| Instalador com core faltando | `dist/` incompleto | `platforms/web/ui/scripts/check-bundle-assets.mjs` (`postbuild`) |
| **N64 não inicia / tela preta / loop não arranca** | `crates/emmu-n64/js/bridge.js` (`cfgLines[39]`, `cfgLines[43]`) | `crates/emmu-n64/README.md` |
| **N64 reinicia em 1/4 da tela** | `crates/emmu-n64/js/bridge.js` (`_neil_reset`) | `snes.worker.js` (`case "restart"` N64) |
| **N64 com altura/tamanho errado no desktop** | `platforms/web/ui/src/style.css` (`.n64-canvas`, `aspect-ratio: 4/3`) | `crates/emmu-n64/src/wasm.rs` (`width`/`height`) |
| **Analógico N64 não responde** | `crates/emmu-n64/js/bridge.js` (`__n64PushControls`) | `useControls.js` (`Analog*`) / `useEmulator.js::coreButtonForFormat` |
| **Save state N64 falha** | `crates/emmu-n64/js/bridge.js` (`/savestate.gz`) | `snes.worker.js` (`case "saveState"/"loadState"`) |
| **Console N64 no desktop** | `platforms/desktop/src/lib.rs` (`mesen_init_rom` rejeita) | `snes.js` (`createEmulator` nunca usa Mesen para N64) |
| **NDS tela achatada / toque fora de lugar** | `platforms/web/ui/src/style.css` (`.nds-canvas`, `2 / 3` + limite de largura) | `Player.vue::ndsTouchPoint` |
| **Painel sensível NDS não responde** | `Player.vue` (`set-touch`/`end-touch` no canvas) | `snes.worker.js` (`setTouch`/`endTouch`) |
| **Save state NDS falha** | `crates/emmu-nds/src/wasm.rs` (`EMMUNDS1` + u32) | `snes.worker.js` (`saveState`/`loadState`) |
| **NDS não inicia no desktop** | `snes.js` (`createEmulator` deve usar Worker) | `platforms/desktop/src/lib.rs` (`mesen_init_rom` rejeita NDS) |
| **PSP tela preta / não inicia** | `crates/emmu-psp/js/adapter.js` (init Emscripten, MEMFS, COI) | `snes.js` (`createEmulator` deve usar `PspClient`, não worker nem Mesen) |
| **PSP sem áudio / volume errado** | `crates/emmu-psp/js/adapter.js` (`setVolume` em `Module.AL.currentCtx.sources`) | aba precisa estar em foco (PPSSPP só gera frames visível) |
| **PSP botão/analógico morto** | `crates/emmu-psp/js/adapter.js` (`simulate_input`, mapa RetroArch) | `useEmulator.js::coreButtonForFormat` / `useControls.js` (`Analog*`) |
| **PSP save state falha** | `crates/emmu-psp/js/adapter.js` (envelope `EMMUPSP1`, gzip em `/game.state`) | `snes.worker.js` não participa — o save é main thread |
| **PSP com proporção/tamanho errado** | `platforms/web/ui/src/style.css` (`.psp-canvas`, `aspect-ratio: 480 / 272`) | `crates/emmu-psp/src/lib.rs` (`FRAME_WIDTH/HEIGHT`) |
| **PSP no desktop cai no Mesen** | `platforms/desktop/src/lib.rs` (`mesen_init_rom` rejeita PSP) | `snes.js` (`createEmulator` nunca usa Mesen para PSP) |

---

## 4. Contratos e invariantes

Não quebre estes contratos sem uma razão explícita e testes.

### 4.1 Backend

- `createEmulator(romBytes, format)` em `snes.js`:
  - com Tauri → `MesenTauriClient`;
  - sem Tauri → `EmulationWorkerClient`;
  - **`N64` → sempre `EmulationWorkerClient`, inclusive no desktop** (Mesen não implementa N64).
  - **`NDS` → sempre `EmulationWorkerClient`, inclusive no desktop** (Mesen não implementa NDS).
  - **`PSP` → sempre `PspClient` (adapter main thread), inclusive no desktop** (Mesen não implementa PSP e o PPSSPP exige WebGL2/pthreads, indisponíveis no worker).
- No desktop, **todos os consoles exceto N64, NDS e PSP** usam Mesen. Nenhum WASM é usado no desktop fora do WebView desses três consoles.
- No web, NES/SNES/GBA/GB/GBC/GG/SMS/WS/PCE/NDS/N64 usam cores separados, todos via Worker. O PSP usa o PPSSPP na **main thread**, com canvas WebGL próprio.

### 4.2 Extensões e formatos

```text
.gb   → GB
.gbc  → GBC
.gg   → GG
.sms  → SMS
.ws   → WS
.wsc  → WS (WonderSwan Color; mesmo core/magic)
.pce  → PCE
.gba  → GBA
.nes  → NES
.sfc/.smc/.fig → SNES
.nds  → NDS
.z64/.n64/.v64 → N64
.psp/.iso/.cso/.chd/.pbp/.elf/.prx → PSP
```

ZIPs são expandidos antes da importação; somente entradas `.gg`, `.sms`, `.ws`, `.wsc`, `.nds`, `.z64`, `.n64`, `.v64` e as extensões PSP são extraídas. `.wsc` é normalizado para o formato lógico `WS`. ROMs NDSi Enhanced podem passar de 256 MiB, então o limite dentro de ZIP é 512 MiB (`MAX_NDS_ROM_BYTES`). Imagens PSP (ISO/CSO) também podem passar de 1 GiB; o limite lógico é 2 GiB (`MAX_PSP_ROM_BYTES`).

Qualquer valor diferente cai em `SNES` no `createEmulator`. Isso é intencional como fallback, mas pode mascarar bugs de extensão.

### 4.3 Save states

| Caminho | Prefixo/formato |
| --- | --- |
| GB web | `EMMUGMB1` + JSON do oxGBC |
| GBC web | `EMMUGBC1` + JSON do oxGBC |
| GG web | `EMMUGG01` + bincode do `smsgg-core` |
| SMS web | `EMMUSMS1` + bincode do `smsgg-core` |
| WS web | `EMMUWS01` + versão u32 + estado bincode do `swanian-core` |
| PCE web | `EMMUPCE1` + bincode |
| GBA web | `EMMUSAVE1` |
| SNES web | bincode do Super Sabicom |
| NES web | serialização do TetaNES |
| **NDS web/desktop** | `EMMUNDS1` + `u32` LE version `2` + tamanho/estado do `PersistentWriteSavestate` do dust + tamanho/ save RAM do cartucho |
| **N64 web/desktop** | gzip criado pelo core em `/savestate.gz` (`_neil_serialize` / `_neil_unserialize`) |
| **PSP web/desktop** | `EMMUPSP1` + `u32` LE version `1` + tamanho/estado gzipado do PPSSPP (`/game.state` no MEMFS) + tamanho/ZIP da save data |
| Desktop | arquivos `.mss` do Mesen |

Ao mudar um formato, **troque o magic/version** e ofereça caminho de recuperação. Nunca faça load silencioso de estado incompatível. No N64 não há magic: o bridge valida o retorno booleano e o tamanho do arquivo. No NDS, o load rejeita magic/versão desconhecidos e comprimentos inconsistentes; a versão atual é `2` (estados v1 ainda são aceitos, mas sem save RAM). O dust marca a save RAM do cartucho com `#[savestate(skip)]`; por isso o save state NDS precisa carregar a save RAM dentro do próprio blob — sem isso, um save in-game some ao reabrir o jogo ou ao restaurar um estado do histórico. Cartuchos com código de jogo começando por `I` (Pokémon Black/White) exigem `has_ir = true` no FLASH do dust (já implementado). Ainda assim, o dust pinned no commit `76d79f2` apresenta “The save data could not be accessed” com `Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds` (256 MiB) também no frontend web upstream; trate como limitação do core, não como bug do envelope de save state do Emmu.

No PSP, o estado bruto vem de `save_state_info` (`"<size>|<ptr>|1"`): o adaptador copia `Module.HEAPU8.subarray(ptr, ptr + size)`, gzipa e monta `EMMUPSP1` + versão `u32` + tamanho/estado + tamanho/ZIP da save data. O `load_state` do RetroArch retorna `0` tanto para caminho inexistente quanto para estado válido — **não confie no retorno**: o adaptador valida a existência e o tamanho de `/game.state` no MEMFS antes de carregar, e rejeita magic/versão/comprimentos inconsistentes. `cmd_save_state` pode retornar vazio no autosave do primeiro frame (RetroArch ainda não registrou o caminho); o adaptador repete a chamada por até 1,5 s.

### 4.4 Frames

- Web: RGBA8888, `putImageData`.
- Desktop: `emmu-frame://localhost/frame?n=<nonce>` devolve BMP 24-bit, `Content-Type: image/bmp`, `Cache-Control: no-store`.
- Não tente passar `Vec<u8>`/array JSON de pixels por `invoke`: já foi tentado e é lento/fragil.
- O canvas que consome `emmu-frame://` fica **tainted**. Para miniatura, use `capturePreview()` → `mesen_capture_preview()` → PNG gerado no Rust.
- **N64 desktop**: o frame vem do WebGL do worker, não do protocolo `emmu-frame`. O canvas usa `aspect-ratio: 4 / 3`.
- **PSP (web e desktop)**: o frame vem do WebGL2 do PPSSPP na main thread, não do protocolo `emmu-frame` e não do worker. O adaptador faz `readPixels` RGBA8888 **480×272** para o canvas `.psp-canvas` (`aspect-ratio: 480 / 272`) e gera a miniatura com `canvas.toDataURL()` (sem taint, já que não há `emmu-frame://`).

### 4.5 Resoluções

| Console | Web WASM | Desktop/Mesen |
| --- | --- | --- |
| NES | 256×240 | 256×240 |
| SNES | 256×224 | 256×224 |
| GBA | 240×160 | 240×160 |
| GB/GBC | 160×144 | 160×144 |
| GG | 160×144 | 160×144 (overscan 48 px no Mesen) |
| SMS | 256×224 NTSC / 256×240 PAL | 256×224 (o callback publica a dimensão real) |
| WS/WSC | 224×144 | 224×144 (`AutoRotate`/ícones desligados no Mesen) |
| PCE | 282×242 | 256×242 |
| **N64** | **320×240 (4:3)** | **320×240 (4:3, WASM no WebView)** |
| **PSP** | **480×272** | **480×272 (PPSSPP na main thread do WebView)** |

Não “corrija” essa diferença PCE sem verificar overscan e o consumidor do frame. O PPSSPP reporta internamente 480×270, mas o frame entregue é 480×272 — não tente “alinhar” para 270. O `runFrame` do `emmu-ws` acumula `MASTER_CLOCK_HZ / 60` ciclos e executa um ou dois frames internos do Swanium por chamada; não remova esse acumulador para “simplificar”: o hardware roda a ~75,47 Hz e a UI chama a 60 Hz.

### 4.6 Controle PCE

- `default_config()` em `crates/emmu-pce/src/lib.rs` **deve** usar `PceInputDevice::TwoButtonGamepad`.
- O modo 6 botões alterna o estado extra em transições de `CLR`; em vários jogos, as setas deixam de ser lidas.
- Existe o teste `default_pad_is_two_button` para proteger isso.
- A UI esconde X/Y e shoulder no PCE. Não os reexiba como se fossem funcionais.

### 4.7 Controle Game Gear

- `set_button` em `crates/emmu-gg/src/lib.rs` mapeia A/B para `SmsGgButton::Button1/Button2` e Start para `Pause`.
- Select, X, Y, L e R são intencionalmente ignorados: o hardware não os possui.
- A UI esconde P2, X/Y, shoulder e Select no GG; não os reexiba como funcionais.
- No desktop, o Mesen lê `A`, `B`, `Start` e as setas do `DebugControllerState`; os demais botões são inofensivos.

### 4.8 Controle Master System

- `set_button` em `crates/emmu-sms/src/lib.rs` mapeia A/B para `SmsGgButton::Button1/Button2` e Start para `Pause`.
- Select, X, Y, L e R são ignorados: o hardware não os possui.
- A UI esconde X/Y, shoulder e Select no SMS, mantém P2 (o console tem dois controles).
- No desktop, o Mesen usa `connect_sms_controllers()` para ambos GG e SMS; o overscan de 48 px só afeta o GG.

### 4.9 Controle WonderSwan

- O hardware tem dois direcionais de 4 vias (X e Y), A, B e Start; não há Select nem P2.
- `Up/Down/Left/Right` → primeiro pad (`KeyState::X1..X4` no Swanium; `up/down/left/right` no `DebugControllerState` do Mesen).
- `U/D/L/R` → segundo pad (`KeyState::Y1..Y4`; `u/d/l/r` no Mesen). A UI usa os nomes dos bindings `X/Y/L/R` e `coreButtonForFormat()` em `useEmulator.js` os converte para `U/D/L/R`.
- A UI esconde P2 e Select no WS, mostra um pad compacto para o segundo direcional no touch e rotula os bindings como “Segundo pad”.
- Swanium não expõe o botão de som do hardware; `Select` é ignorado.

### 4.10 Controle Nintendo 64

- Ações: `Up/Down/Left/Right`, `A/B/Start/Z/L/R`, `CUp/CDown/CLeft/CRight` e `AnalogUp/AnalogDown/AnalogLeft/AnalogRight`.
- `player` 1–4 é preservado até o worker; `_neil_send_mobile_controls` do N64Wasm **sempre escreve em `neilbuttons[0]`**. Na prática, todos os botões e o analógico chegam ao core como Jogador 1.
- `mobileMode` (`cfgLines[43] = '1'`) é obrigatório: é ele que dispara o hook `__n64PushControls()` logo após `resetNeilButtons()` no main loop.
- `disableAudioSync` (`cfgLines[39] = '1'`) é obrigatório: sem ele o main loop não inicia.
- X, Y e Select não existem no controle do N64 e não têm efeito. O analógico tem quatro ações independentes e um pad compacto na interface touch.

### 4.11 Teclado

- `useShortcuts.js` usa `event.code`, com fallback para `event.key`.
- Alguns browsers embutidos emitem `code: ""`.
- `blur` da janela deve liberar todos os botões.
- `pressButton` no `Player.vue` chama `preventDefault()` e `blur()` no elemento para evitar scroll/foco preso.

### 4.12 Persistência

- IndexedDB: `emmu-library`, versão 2, stores `games` e `settings`.
- ROMs, save states, miniaturas e histórico **devem** permanecer como `Blob` no registro. O IndexedDB serializa `ArrayBuffer` inline (limite de ~127 MiB no Chromium), mas guarda `Blob` por referência; converter ROM em `ArrayBuffer` no `saveLibraryGame`/`saveGameProgress` faz ROMs grandes (NDSi Enhanced de 256 MiB) falharem na importação e no autosave. Registros antigos com `ArrayBuffer` são curados no próximo checkpoint.
- `MAX_SAVE_HISTORY = 10`.
- `CHECKPOINT_INTERVAL = 5000` ms.
- `MIN_LIBRARY_LOADING_MS = 450`.
- Filtros em `localStorage: emmu.library.filters`.
- Bindings de controle também em `localStorage`. A migração preenche ações N64 ausentes/inválidas para P1–P4.
- Toasts: fila com 10 s de duração, pausa no hover, barra de progresso, botão de fechar e dedupe em `useToast.js`.

### 4.13 Controle PlayStation Portable

- Ações: `Up/Down/Left/Right`, `A/B/X/Y`, `L/R`, `Start/Select` e `AnalogUp/AnalogDown/AnalogLeft/AnalogRight`.
- Mapeamento RetroArch confirmado no core real: `A` (×) = 0, `B` (○) = 8, `X` (□) = 1, `Y` (△) = 9, `Select` = 2, `Start` = 3, D-pad = 4/5/6/7, `L/R` = 10/11, analógico direita/esquerda/baixo/cima = 16/17/18/19, valor central `0x7fff`.
- O analógico é **digital** (quatro botões independentes, sem eixo analógico contínuo). Na UI, `A/B/X/Y` são rotulados ×/○/□/△ no diálogo de controles.
- PSP tem **um único jogador**; `ControlsDialog.vue` esconde a aba P2 e N64 (`Z`/C-buttons) não aparece.
- O áudio é do próprio core: `setVolume()` atua em `Module.AL.currentCtx.sources[].gain.gain.value`, não no `AudioWorklet` do Emmu.
- O PPSSPP só gera frames quando a aba está visível/focada: com a aba em segundo plano, `frameCount` fica em 0 e o canvas fica preto. Não interprete isso como falha do core.

---

## 5. Arquitetura em fluxo

### Web

```text
App.vue
 → useEmulator.js
   → EmulationWorkerClient
     → snes.worker.js
       → initialize | restart | runFrame | setButton | saveState | loadState
       → emmu_snes / emmu_nes / emmu_gba / emmu_gbc / emmu_gb / emmu_gg / emmu_sms / emmu_ws / emmu_pce / emmu_n64 / emmu_nds
   → PspClient (main thread; nunca no worker)
     → crates/emmu-psp/js/adapter.js (PspAdapter)
       → ppsspp_libretro.js + ppsspp_libretro.wasm + ppsspp-assets.zip (WebGL2/pthreads)
 → useAudio.js
   → audio-worklet.js   (PSP não usa: áudio interno do Emscripten)
 → libraryStore.js
   → IndexedDB
```

Worker mensagens importantes: `initialize`, `restart`, `runFrame`, `setButton`, `setTouch`, `endTouch`, `setVolume`, `saveState`, `loadState`. Buffers de frame/áudio/estado são transferidos de volta. O PSP **não** passa por mensagens: o adapter roda na main thread com o mesmo contrato assíncrono (`runFrame`/`setButton`/`saveState`/`loadState`/`restart`/`setVolume`/`capturePreview`). O Vite e o Tauri enviam COOP/COEP para habilitar `SharedArrayBuffer`.

No N64, o worker carrega `public/wasm/n64/n64wasm.js` + `.wasm` + `assets.zip` e instancia o módulo Emscripten via `new Function('Module', jsText)`, isolando as variáveis internas entre inicializações. O bridge aplica patches em tempo de execução; `vendor/` nunca é editado.

No NDS, o worker importa `src/wasm/nds/adapter.js`, que usa o módulo `wasm-pack` de `src/wasm/nds/emmu_nds.js`. O áudio nativo do `dust` é **32768 Hz**: `AUDIO_SAMPLE_RATE` no crate e `AUDIO_RATE` no adapter precisam permanecer iguais. Anunciar 44100 Hz faz o worklet drenar a fila 35% mais rápido, com tom agudo e underruns.

### Desktop

```text
Vue UI
 → (consoles comuns) MesenTauriClient (snes.js)
   → invoke("mesen_*") → platforms/desktop/src/lib.rs
     → emmu-mesen-sys → MesenCore.dylib/.so
       → dlopen(SDL2) para áudio
   → emmu-frame:// → frames BMP
   → mesen_capture_preview() → PNG para miniatura
 → (N64, NDS) EmulationWorkerClient → mesmo worker WASM do web, dentro do WebView
 → (PSP) PspClient → mesmo adapter main-thread do web, dentro do WebView (WebGL2/pthreads)
```

Comandos Tauri: `mesen_init_rom`, `mesen_run_frame`, `mesen_set_button`, `mesen_reset`, `mesen_stop`, `mesen_release`, `mesen_save_state`, `mesen_load_state`, `mesen_capture_preview`, `mesen_set_volume`, `mesen_set_p2_enabled`. `mesen_init_rom` rejeita `N64`, `NDS` e `PSP` explicitamente.

Notificações Mesen:

- `NOTIFICATION_PPU_FRAME_DONE = 7` — NES;
- `NOTIFICATION_REFRESH_SOFTWARE_RENDERER = 22` — SNES/GBA/GB/GBC/GG/WS/PCE.

---

## 6. Comandos que sempre funcionam

### Antes de qualquer coisa

```sh
git submodule update --init --recursive
```

Se `crates/emmu-gb` aparecer com `-` no `git submodule status`:

```sh
git submodule init crates/emmu-gb
```

### Web

```sh
cd platforms/web/ui
npm install
npm run dev
npm run build
npm run build:wasm
```

`predev` e `prebuild` já chamam `build:wasm`. O script compila também o N64 e copia os assets para `src/wasm/n64/` e `public/wasm/n64/`. Para o PSP ele copia `js/adapter.js` para `src/wasm/psp/` e `ppsspp_libretro.js`/`.wasm`/`ppsspp-assets.zip`/`license.txt` para `public/wasm/psp/` (o runtime PPSSPP já vem pré-compilado, sem `wasm-pack`). O `postbuild` valida todos os assets em `dist/`.

### Rust

```sh
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace
```

Testes com ROM real:

```sh
EMMU_NES_TEST_ROM="/caminho/jogo.nes" cargo test -p emmu-nes
EMMU_GBC_TEST_ROM="/caminho/jogo.gbc" cargo test -p emmu-gbc
EMMU_GB_TEST_ROM="/caminho/jogo.gb" cargo test -p emmu-gb
EMMU_PCE_TEST_ROM="/caminho/jogo.pce" cargo test -p emmu-pce
EMMU_GG_TEST_ROM="/caminho/jogo.gg" cargo test -p emmu-gg
EMMU_SMS_TEST_ROM="/caminho/jogo.sms" cargo test -p emmu-sms
EMMU_WS_TEST_ROM="/caminho/jogo.ws" cargo test -p emmu-ws
MESEN_TEST_ROM="/caminho/jogo.nes" cargo test -p emmu-mesen-sys
MESEN_PCE_TEST_ROM="/caminho/jogo.pce" cargo test -p emmu-mesen-sys
MESEN_GG_TEST_ROM="/caminho/jogo.gg" cargo test -p emmu-mesen-sys
MESEN_WS_TEST_ROM="/caminho/jogo.ws" cargo test -p emmu-mesen-sys
```

Use ROMs de jogo, não BIOS, para validação de UI/input. Para N64, o smoke test é pela UI: abrir `.z64`/`.n64`/`.v64` e validar vídeo, áudio, P1–P4, analógico, save/load e restart. Para PSP, abrir `.iso`/`.cso`/`.pbp`/`.elf` e validar vídeo WebGL2, áudio/volume, D-pad/analógico/botões (A/B/X/Y = ×/○/□/△), restart, save/load e histórico — com a aba **em foco**, senão o PPSSPP não gera frames. `cargo test -p emmu-psp` cobre as constantes de frame 4:3 e o envelope `EMMUPSP1`.

### Desktop

```sh
./crates/emmu-mesen-sys/scripts/build-sdl2.sh
cd platforms/desktop
cargo tauri dev
cargo tauri build
```

Ou:

```sh
cd platforms/web/ui
npm run desktop:dev
npm run desktop:build
```

---

## 7. Playbooks de correção

### 7.1 Bug de input no web

1. Descubra se é teclado ou touch.
2. Se teclado, verifique `useShortcuts.js`:
   - `code` vazio → fallback `key`;
   - `keyup` sempre solta;
   - `blur` libera tudo;
   - guard de foco não pode ignorar botões.
3. Instrumente temporariamente `Worker.prototype.postMessage` e confirme pares `pressed:true` / `pressed:false`.
4. Se o botão chega ao worker mas o jogo não reage, o problema é no core, não na UI.
5. Para PCE, confirme `TwoButtonGamepad`. Para N64, confirme `cfgLines[43]` e o hook `__n64PushControls`.
6. **Remova toda instrumentação antes de entregar.**

Padrão útil de instrumentação temporária:

```js
const orig = Worker.prototype.postMessage;
Worker.prototype.postMessage = function (msg, ...rest) {
  if (msg?.type === "setButton") {
    (window.__setButtonLog ||= []).push({
      button: msg.button,
      pressed: msg.pressed,
      player: msg.player,
    });
  }
  return orig.call(this, msg, ...rest);
};
```

### 7.2 PCE com setas travadas

1. Abra `crates/emmu-pce/src/lib.rs`.
2. Confirme `input_device: PceInputDevice::TwoButtonGamepad`.
3. Rode `cargo test -p emmu-pce default_pad_is_two_button`.
4. Rebuild do WASM PCE:
   ```sh
   cd crates/emmu-pce
   wasm-pack build --target web --out-dir ../../platforms/web/ui/src/wasm/pce --out-name emmu_pce
   ```
5. Recarregue a aba web: WASM em cache pode manter o bug antigo.

### 7.3 Miniatura desktop ausente

1. Não use `canvas.toBlob()` em frame vindo de `emmu-frame://`.
2. Confirme `MesenTauriClient.capturePreview()` em `snes.js`.
3. Confirme `useEmulator.capturePreview()` e os pontos de autosave em `App.vue`.
4. No Rust, use `mesen_capture_preview()` e `frame_as_png()`.
5. Rode `cargo test -p desktop`.

### 7.4 Desktop sem vídeo

1. Confirme que o protocolo `emmu-frame` está registrado.
2. Confirme `frame_as_bmp()` e o `Content-Type`.
3. Confirme que o lock do frame usa `lock()`, não `try_lock()`.
4. Verifique as notificações do Mesen.
5. Se for PCE e a tela for preta, verifique `PCE_DEFAULT_PALETTE`.

### 7.5 Desktop sem áudio

1. O Mesen carrega SDL2 via `dlopen()` com nome curto.
2. Confirme `runtime/` com `MesenCore.*`, `libSDL2...` e licença.
3. Confirme rpath: `@loader_path` no macOS, `$ORIGIN` no Linux.
4. Confirme `configure_audio` e `mesen_set_volume`.
5. Não instale `sdl2-compat` do Homebrew como solução: ele é shim sobre SDL3.

### 7.6 GBA web

1. `js/bridge.js` é gerado; nunca edite diretamente.
2. Edite `src/bridge.template.js` ou `tools/build-bridge.mjs`.
3. Rode `node tools/build-bridge.mjs`.
4. Depois, `npm run build:wasm`.
5. O save state é `EMMUSAVE1`; Mesen usa `.mss` e não é compatível.

### 7.7 Save state corrompido

1. Identifique o magic do core.
2. Verifique se o load rejeita magic diferente (no N64: retorno booleano + tamanho de `/savestate.gz`).
3. Verifique `libraryStore.js` e o histórico (10 estados).
4. A UI deve oferecer reinício limpo ou voltar à biblioteca.
5. Não apague automaticamente o estado corrompido sem confirmação.

### 7.8 WS lento, áudio desafinado ou segundo pad morto

1. Confirme que `crates/emmu-ws/src/lib.rs` ainda acumula `CYCLES_PER_UI_FRAME` e executa `System::run_frame` enquanto o carry ≥ `CYCLES_PER_FRAME`.
2. Não troque `audio_sample_rate()` para “compensar” 60 Hz: o APU do Swanium gera 24 kHz reais; o acumulador resolve o tempo.
3. Confirme `coreButtonForFormat()` em `useEmulator.js`: X/Y/L/R viram U/D/L/R apenas quando `format === "WS"`.
4. No desktop, `apply_button_to_state()` em `platforms/desktop/src/lib.rs` deve continuar mapeando U/D/L/R para os campos `u/d/l/r` do `DebugControllerState`.
5. Se o frame vier 224×157, `WS_LCD_SHOW_ICONS_OFFSET` em `connect_ws_controllers()` foi ligado por engano.

### 7.9 N64: loop não inicia, frame errado ou input morto

1. `cfgLines[39] = '1'` (`disableAudioSync`) e `cfgLines[43] = '1'` (`mobileMode`) em `js/bridge.js` — obrigatórios.
2. Confirme que `updateMobileControls()` foi reescrito para `__n64PushControls()` e que o hook foi injetado após `resetNeilButtons()`.
3. Se o jogo aparece em 1/4 da tela após reiniciar, o restart está recriando o módulo: use `_neil_reset()` na instância existente.
4. Se a altura da área de desenho está diferente no desktop, confirme `.game-canvas.n64-canvas { aspect-ratio: 4 / 3 }` em `style.css` e `FRAME_WIDTH/HEIGHT = 320/240`.
5. Save state usa `/savestate.gz`, não `/savestate.sav`. `case "loadState"` no worker deve usar `await emulator.loadState(...)`.
6. Para ver o ruído de debug, reative os logs marcados com `[debug-*]` ou defina `globalThis.__n64VerboseLogs = true`. Erros reais (`onAbort`, `callMain`, save/load) permanecem ativos.

### 7.10 PSP: tela preta, input morto ou save state falha

1. Confirme `crossOriginIsolated === true`, `typeof SharedArrayBuffer === "function"` e WebGL2 disponível. Sem COOP/COEP o Emscripten/pthreads não inicializa. Vite e Tauri já enviam os headers.
2. Confirme que `createEmulator()` em `snes.js` retorna `PspClient` para `PSP` (nunca `EmulationWorkerClient`, nunca `MesenTauriClient`), e que `mesen_init_rom` rejeita `PSP`.
3. O PPSSPP só gera frames com a aba visível/focada: se `get_current_frame_count` está em 0 e o canvas está preto, verifique o foco antes de suspeitar do core.
4. `runFrame()` faz `readPixels` do WebGL2 para RGBA8888 480×272. Se o frame estiver preto mas `frameCount` subir, confira o `preserveDrawingBuffer: true` no patch de `canvas.getContext` do adaptador **e o CSS do canvas interno**: ele precisa estar fixado em `480 / devicePixelRatio × 272 / devicePixelRatio`. Sem CSS, o `ResizeObserver` do core dobra o backing store a cada frame (960→1920→…→62 mil px) e o `readPixels` lê preto; com `100%` do host o texto fica degradado pela dupla reamostragem.
5. Se o jogo “engasgar” com `frameCount` subindo, verifique se `capturePixels()` está reaproveitando `rawBuffer`/`flippedPixels`. Alocar ~0,5 MB por frame gera GC constante. Também confirme que a inicialização não ficou com a instrumentação de 5 s de `pulse`.
6. Para input, instrumente `simulate_input` e confirme o par `(botão, pressionado)` com o mapa da seção 4.13. Analógico são quatro botões (16..19), valor central `0x7fff`.
7. Para save, inspecione `/game.state` no MEMFS: `save_state_info` devolve `"<size>|<ptr>|1"`. Se o autosave do primeiro frame falhar, confirme o retry de `cmd_save_state` (1,5 s). No load, valide magic/versão/tamanhos antes de chamar `load_state("game.state", 0)` — o retorno `0` não indica sucesso.
8. Para áudio, confirme `Module.AL.currentCtx.sources[].gain.gain.value` após `setVolume()`. Se não houver fontes, a aba pode estar sem foco ou o core ainda não iniciou o áudio.
9. **Remova toda instrumentação antes de entregar.** Use `globalThis.__emmuPspVerboseLogs = true` para logs do core, nunca `console.log` fixo no adaptador.

---

## 8. Armadilhas históricas — não repita

| Problema passado | Causa | Correção atual |
| --- | --- | --- |
| Setas PCE não funcionavam | `SixButtonGamepad` alternava estado extra a cada `CLR` | `TwoButtonGamepad` por padrão + teste |
| Menu PCE “corria sozinho” | botão ficava pressionado quando evento não trazia `code` | fallback para `event.key` + `blur` |
| Miniatura desktop não aparecia | canvas tainted por `emmu-frame://` | PNG gerado no Rust |
| Desktop sem imagem | tentativa de `try_lock()` no frame | usar `lock()` |
| PCE desktop preto | falta da paleta padrão do Mesen | `pce_palette.rs` |
| Frame PCE inconsistente | web 282×242, desktop 256×242 | diferença intencional; não “uniformizar” |
| GG desktop com bordas 256×240 | `SmsConfig` zerado sem `GameGearOverscan` | 48 px nos 4 lados em `connect_sms_controllers` |
| GBA web parou após update do vendor | bridge JS não regenerado | `node tools/build-bridge.mjs` |
| Mesen travava ao sair | FFI após `Release()` | guard atômico de shutdown |
| Build workspace quebrava | dev-deps de `super-sabicom`/`tetanes-core` e vendor PCE | crates fora do workspace / excluídos |
| Botão grudava em browser embutido | `event.code === ""` | fallback para `event.key` |
| WS rodava em câmera lenta | Swanium gera frames de ~75 Hz, UI chama a 60 Hz | acumulador de ciclos em `emmu-ws::run_frame` |
| N64 reiniciava em um quadrante | restart recriava canvas/contexto WebGL | `_neil_reset()` na instância existente |
| N64 com altura errada no desktop | canvas herdava `aspect-ratio: 8/7` do SNES | `.n64-canvas { aspect-ratio: 4 / 3 }` |
| Save state N64 falhava | worker usava `/savestate.sav` | `/savestate.gz` + validação de retorno/tamanho |
| Main loop N64 não arrancava | `config.txt` sem `disableAudioSync`/`mobileMode` | índices 39 e 43 = `1` |
| Log N64 poluía o console | dezenas de `WebGL: INVALID_OPERATION` e logs de input | filtro `WebGL:` + logs `[debug-*]` comentados |
| PSP com tela preta em aba em segundo plano | PPSSPP não gera frames sem foco/visibilidade | smoke test com aba focada; não “corrigir” o core |
| PSP enviado ao Mesen | `createEmulator()` caiu no `MesenTauriClient` | `{ format: "PSP" } → PspClient` (main thread) |
| Autosave PSP falhava no primeiro frame | RetroArch ainda não registrou o caminho do save | retry de `cmd_save_state` por até 1,5 s no adaptador |
| Load PSP aceitava estado inexistente | `load_state` retorna `0` também para caminho ausente | validar `/game.state` no MEMFS antes de carregar |
| PSP com altura 270 | confusão com a resolução interna reportada | frame entregue é 480×272; não alinhar para 270 |
| PSP tela preta com `frameCount` subindo | `ResizeObserver` do core dobrava o canvas (DPR 2) até 62 mil px | CSS do canvas interno fixo em `480/dpr × 272/dpr` + `readPixels` |
| PSP com solavancos apesar de 60 fps | ~0,5 MB alocados por frame na captura | buffers raw/invertido reaproveitados no adaptador |

---

## 9. Estrutura crítica de arquivos

```text
platforms/web/ui/src/
├── App.vue                    # orquestração, autosave, diálogos
├── components/Player.vue      # controles touch e ações do player (pads analógicos N64/PSP)
├── composables/
│   ├── snes.js                # createEmulator + EmulationWorkerClient + MesenTauriClient + PspClient
│   ├── useEmulator.js         # facade do core; setButton; capturePreview
│   ├── useShortcuts.js        # teclado
│   ├── useLibrary.js          # import/filtros/progresso/saves
│   ├── useAudio.js            # Web Audio
│   ├── useControls.js         # bindings (Analog* para N64)
│   └── useToast.js            # fila de toasts
├── stores/libraryStore.js     # IndexedDB
├── workers/
│   ├── snes.worker.js         # protocolo dos cores WASM
│   └── audio-worklet.js       # PCM
├── style.css                  # .n64-canvas → 4/3; .psp-canvas → 480/272
└── wasm/                      # gerado; NUNCA editar diretamente (inclui psp/adapter.js copiado)

platforms/web/ui/public/wasm/n64/  # assets N64Wasm servidos em runtime (gerados/copiados)
platforms/web/ui/public/wasm/psp/  # ppsspp_libretro.js/.wasm + ppsspp-assets.zip (copiados do vendor)

platforms/desktop/src/lib.rs   # Tauri + Mesen + frames + saves (rejeita N64/NDS/PSP)
crates/emmu-mesen-sys/
├── src/lib.rs                 # ABI e wrappers
├── src/pce_palette.rs         # paleta PCE
├── build.rs                   # -lMesenCore
└── scripts/build-sdl2.sh      # runtime SDL2

crates/emmu-n64/
├── README.md                  # API, config, controls, save state, restart, logs
├── UPSTREAM.txt               # origem dos blobs vendorizados e hashes
├── LICENSE                    # GPL-3.0-only do crate
├── js/bridge.js               # patches Emscripten, input, save/load, filtro de logs
├── src/lib.rs                 # constantes de frame/audio + teste 4:3
├── src/wasm.rs                # bindings wasm-bindgen da ponte JS
├── vendor/n64wasm/            # N64Wasm MIT (não editar)
└── (native.rs é stub; desktop usa o WASM no WebView)

crates/emmu-psp/
├── README.md                  # API, init Emscripten, MEMFS, controles, save state, COI
├── UPSTREAM.txt               # origem/hashes do runtime PPSSPP + obrigações GPL-2
├── LICENSE                    # GPL-3.0-or-later do crate/wrapper
├── js/adapter.js              # PspAdapter: EJS_Runtime, input, save/load, volume, preview
├── src/lib.rs                 # constantes 480×272 + envelope EMMUPSP1 + testes
└── vendor/ppsspp-ejs/         # pré-compilado (NÃO editar): .js, .wasm, assets.zip, license.txt

crates/emmu-sms/
├── src/lib.rs                 # fachada WASM, config SMS, input, save state
└── vendor/jgenesis/           # subset SMS/GG vendorizado (GPL-3.0); NÃO editar

crates/emmu-ws/
├── src/lib.rs                 # fachada WASM, timing, input, save state
└── vendor/swanian-core/       # core WS vendorizado (MIT); NÃO editar

crates/emmu-pce/src/lib.rs     # config PCE, input, save state
crates/emmu-gb/src/lib.rs      # GB DMG / oxGBC
crates/emmu-gbc/src/lib.rs     # GBC / oxGBC
crates/emmu-gba/
├── src/bridge.template.js     # ponte JS do GBA
├── tools/build-bridge.mjs     # gera js/bridge.js
└── js/bridge.js               # gerado; NUNCA editar

crates/emmu-nes/src/lib.rs     # TetaNES wrapper
crates/emmu-snes/src/lib.rs    # Super Sabicom wrapper
```

---

## 10. Como adicionar um novo console

Se pedirem para adicionar outro sistema, não comece pelo worker. Siga esta checklist:

1. Criar crate `crates/emmu-<slug>` com API compatível:
   - `new(rom)`;
   - `runFrame(renderGraphics)`;
   - `setButton(button, pressed, player)`;
   - `saveState()` / `loadState(bytes)`;
   - `restart()`;
   - `audioSamples()` / `audioSampleRate()`.
2. Adicionar ao workspace em `Cargo.toml`.
3. Adicionar `wasm-pack` ao script `build:wasm` em `platforms/web/ui/package.json`.
4. Adicionar extensão em `App.vue` e mapping em `snes.js::createEmulator`.
5. Adicionar import e cases em `snes.worker.js`.
6. Adicionar detect/flag em `Player.vue` para controles touch.
7. Adicionar mapping em `platforms/desktop/src/lib.rs::mesen_init_rom`, se o Mesen suportar o console — se não suportar, rejeite explicitamente e documente o caminho alternativo (como o N64).
8. Atualizar `HelpDialog.vue`, `README.md`, `AGENTS.md` e tabela de licenças.
9. Definir magic de save state e política de histórico.
10. Rodar `npm run build`, `cargo check --workspace` e `cargo tauri build` se desktop mudou.

---

## 11. Submódulos e Git

- Todos os crates e plataformas são submódulos. Commits feitos dentro deles **não** atualizam o repositório principal automaticamente.
- Fluxo correto:
  ```sh
  cd crates/emmu-n64
  git add -A
  git commit -m "..."
  cd ../..
  git add crates/emmu-n64
  git commit -m "Atualiza gitlink do emmu-n64"
  ```
- Não edite diretamente `js/bridge.js` do GBA, `dist/`, `runtime/`, `runtime-link/`, `src/wasm/` ou `public/wasm/`.
- `runtime/` e `runtime-link/` são gerados e ignorados.
- `src/wasm/` é gerado e ignorado; `dist/` é saída de build. `public/wasm/n64/` contém assets copiados do vendor do core.
- `platforms/desktop/scripts/prepare-bundle.sh` prepara MesenCore, SDL2, assets N64 e PSP e licenças; `bundle.resources` os envia no instalador.
- `crates/emmu-ws` ainda é um diretório normal no repositório principal (sem remote/submódulo).
- `crates/emmu-n64/vendor/n64wasm`, `crates/emmu-pce/vendor/jgenesis`, `crates/emmu-gg/vendor/jgenesis`, `crates/emmu-sms/vendor/jgenesis`, `crates/emmu-ws/vendor/swanian-core` e `crates/emmu-psp/vendor/ppsspp-ejs` **não** são submódulos: são códigos vendorizados dentro dos respectivos cores.
- `crates/emmu-gba/vendor/web-gba-emulator` e `crates/emmu-mesen-sys/vendor/SDL` são submódulos de terceiros; evite commits locais neles.
- `crates/tetanes-core`, `crates/emmu-super-sabicom` e `crates/emmu-pce/vendor` são excluídos do workspace por razões de build. `crates/emmu-n64/vendor` também é excluído.

### Estado atual

- `crates/emmu-gg` @ `c807bc1`, `crates/emmu-sms` @ `d55bd69`, `crates/emmu-n64` @ `c066186`, `crates/emmu-nds` @ `70d64fd` e `crates/emmu-psp` @ `49dd022` são submódulos de `EspetoRx`. O remote de `emmu-psp` ainda está vazio: o gitlink local só será utilizável por terceiros após push (que exige confirmação explícita).
- `crates/emmu-ws` foi adicionado como código local (Swanium MIT); decida o remote antes de transformá-lo em submodule.
- A integração de UI/desktop do GG, SMS, N64, NDS e PSP foi commitada nos submódulos correspondentes; os gitlinks são atualizados neste commit do repositório principal.
- O core NDS (`dust` GPL-3.0) roda como WASM no worker (web) e no WebView (desktop), com áudio nativo a 32768 Hz — não altere `AUDIO_SAMPLE_RATE`/`AUDIO_RATE`.
- O runtime PSP (PPSSPP libretro GPL-2.0-or-later) roda na main thread do WebView (web e desktop), com WebGL2/pthreads/COI; os binários pré-compilados ficam em `crates/emmu-psp/vendor/ppsspp-ejs/` e são copiados para `public/wasm/psp/` pelo `build:wasm`.
- Não faça push no repositório principal sem confirmação explícita.

---

## 12. O que NÃO fazer

- Não usar Mesen no web nem WASM no desktop — **exceto N64**, que usa WASM no WebView dos dois.
- Não trocar `TwoButtonGamepad` por 6 botões no PCE “para expor X/Y”.
- Não remover o acumulador de ciclos do `emmu-ws` nem “corrigir” a taxa de áudio para 19 kHz: o Swanium roda a ~75 Hz e o acumulador converte para os 60 Hz da UI.
- Não tratar X/Y/L/R do WonderSwan como botões de face/shoulder: eles são o segundo direcional.
- Não editar arquivos gerados (incluindo `public/wasm/n64/`).
- Não committar `node_modules`, `dist`, `runtime`, `runtime-link` ou WASM gerado.
- Não usar `canvas.toBlob()` para miniatura desktop.
- Não passar frames por `invoke` como array de bytes.
- Não alterar offsets da ABI do Mesen sem comparar com os headers do MesenCE.
- Não apagar save states corrompidos sem confirmação.
- Não assumir que `event.code` existe.
- Não rodar `git push` sem confirmação explícita.
- Não esquecer de atualizar licenças ao introduzir código de terceiros (N64Wasm é MIT, com `UPSTREAM.txt`).
- Não recriar o módulo Emscripten no restart do N64: use `_neil_reset()`.
- Não editar `crates/emmu-n64/vendor/`; patches são aplicados em `js/bridge.js`.
- Não rodar o PPSSPP no `snes.worker.js` nem no Mesen: o PSP é sempre main thread (`PspClient`), web e desktop.
- Não confiar no retorno de `load_state` do RetroArch (retorna `0` também para caminho inexistente): valide `/game.state` no MEMFS.
- Não editar `crates/emmu-psp/vendor/ppsspp-ejs/`; o runtime é pré-compilado e seus hashes estão em `UPSTREAM.txt`.
- Não remover os headers COOP/COEP do Vite/Tauri: sem `SharedArrayBuffer` o pthreads do Emscripten quebra.
- Não usar o `AudioWorklet` do Emmu para o PSP: o áudio é interno ao Emscripten/OpenAL.
- Não “corrigir” o frame PSP para 480×270 nem o canvas para 4:3: é 480×272, `aspect-ratio: 480 / 272`.

---

## 13. Checklist antes de responder “pronto”

Para mudanças de código:

```sh
cargo fmt --all -- --check
cargo check --workspace
cargo test -p <core alterado>
npm run build
```

Para mudanças desktop:

```sh
cargo tauri build
```

Para mudanças WASM:

```sh
npm run build:wasm
npm run build
```

Para mudanças em save state:

- magic/version atualizado (ou validação de gzip no N64, ou magic/versão/tamanhos no PSP);
- teste de round-trip;
- teste de rejeição de estado inválido;
- histórico e recuperação na UI revisados;
- no PSP, `save_state_info` e `/game.state` no MEMFS validados com aba focada.

Para mudanças em input:

- `pressed:true` e `pressed:false` observados;
- `blur` libera tudo;
- teste em ROM de jogo real;
- instrumentação removida;
- no WS, primeiro e segundo direcionais testados (web e desktop);
- no N64, analógico testado no web e no desktop;
- no PSP, D-pad, analógico digital e A/B/X/Y (×/○/□/△) testados na ROM real, com aba focada, no web e no desktop.

Para mudanças em licenças/vendor:

- `UPSTREAM.txt` ou equivalente atualizado;
- texto de licença presente;
- README da raiz atualizado;
- bundle desktop/web continua com os avisos necessários.

---

## 14. Se você estiver em dúvida

Pergunte ao usuário, com escolhas objetivas:

1. “Isso acontece no navegador, no desktop ou nos dois?”
2. “Qual ROM e qual extensão?”
3. “O problema aparece ao abrir a biblioteca, ao iniciar o jogo ou durante a partida?”
4. “Você recarregou a página/app depois da última correção?”
5. “Pode enviar o console log ou o evento `setButton` observado?”

DEBUG REPORT curto é melhor que suposição longa.

---

## 15. Frase final para agentes

> Mude o menor arquivo possível, no backend correto, com o rebuild correto, preservando licenças e formatos de save. Se o problema é de input, prove o evento. Se é de frame, prove o protocolo. Se é de core, prove com ROM real. No N64, prove também o hook do Emscripten e o `_neil_reset`. No PSP, prove o `crossOriginIsolated`, o `frameCount` com aba focada e o `/game.state` no MEMFS.
