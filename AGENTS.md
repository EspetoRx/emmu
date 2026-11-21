# AGENTS.md

> Manual operacional para qualquer agente de IA que vá ler, manter ou corrigir o Emmu.
> Para contexto humano, comece pelo [`README.md`](README.md). Para contexto de código, este arquivo é a fonte mais rápida.

---

## 0. Regra de ouro

Antes de alterar código, responda mentalmente a três perguntas:

1. **O problema é no web ou no desktop?** Os backends são diferentes.
2. **Qual core está envolvido?** Cada console tem um crate, um WASM e um caminho Mesen próprios.
3. **A mudança precisa de rebuild de WASM, bridge JS, runtime Mesen/SDL ou gitlink de submódulo?**

Se não souber a resposta, pergunte ao usuário **qual ROM, qual plataforma e qual tela**. Não tente “corrigir” os dois backends às cegas.

---

## 1. Resumo em 60 segundos

| Item | Fato |
| --- | --- |
| UI | Vue 3 + Vite 6 em `platforms/web/ui`, compartilhada por web, Tauri desktop e scripts mobile |
| Web | Web Worker (`snes.worker.js`) + oito pacotes WASM gerados por `wasm-pack` |
| Desktop | Tauri 2 + Rust; emulação via MesenCE (`emmu-mesen-sys`), não via WASM |
| Consoles | NES, SNES, GBA, GB, GBC, GG, WS/WSC, PCE |
| Persistência | IndexedDB `emmu-library` v2; `localStorage` para filtros e controles |
| Save states | `EMMUGMB1`, `EMMUGBC1`, `EMMUGG01`, `EMMUWS01`, `EMMUPCE1`, `EMMUSAVE1`, bincode/TetaNES no web; `.mss` no desktop |
| Frames web | RGBA8888 via `putImageData` |
| Frames desktop | BMP 24-bit via protocolo `emmu-frame://`; miniatura via PNG gerado no Rust |
| Cores GPL | GB, GBC, GG e PCE no web; Mesen no desktop |
| Cores MIT/permisivos | NES, SNES, GBA e WS (Swanium) no web |
| Submódulos | Todos os crates e plataformas antigos são submódulos; `crates/emmu-ws` é diretório local até receber remote |
| Push | `emmu-gg` foi publicado; os demais repositórios/commits continuam locais. Não faça push sem confirmar remotos |

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
8. O `README.md` do core específico envolvido no bug.

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

---

## 4. Contratos e invariantes

Não quebre estes contratos sem uma razão explícita e testes.

### 4.1 Backend

- `createEmulator(romBytes, format)` em `snes.js`:
  - com Tauri → `MesenTauriClient`;
  - sem Tauri → `EmulationWorkerClient`.
- No desktop, **todos** os consoles usam Mesen. Nenhum WASM é usado no desktop.
- No web, NES/SNES/GBA/GB/GBC/GG/WS/PCE usam cores separados, todos via Worker.

### 4.2 Extensões e formatos

```text
.gb   → GB
.gbc  → GBC
.gg   → GG
.ws   → WS
.wsc  → WS (WonderSwan Color; mesmo core/magic)
.pce  → PCE
.gba  → GBA
.nes  → NES
.sfc/.smc/.fig → SNES
```

ZIPs são expandidos antes da importação; somente entradas `.gg`, `.ws` e `.wsc` são extraídas. `.wsc` é normalizado para o formato lógico `WS`.

Qualquer valor diferente cai em `SNES` no `createEmulator`. Isso é intencional como fallback, mas pode mascarar bugs de extensão.

### 4.3 Save states

| Caminho | Prefixo/formato |
| --- | --- |
| GB web | `EMMUGMB1` + JSON do oxGBC |
| GBC web | `EMMUGBC1` + JSON do oxGBC |
| GG web | `EMMUGG01` + bincode do `smsgg-core` |
| WS web | `EMMUWS01` + versão u32 + estado bincode do `swanium-core` |
| PCE web | `EMMUPCE1` + bincode |
| GBA web | `EMMUSAVE1` |
| SNES web | bincode do Super Sabicom |
| NES web | serialização do TetaNES |
| Desktop | arquivos `.mss` do Mesen |

Ao mudar um formato, **troque o magic/version** e ofereça caminho de recuperação. Nunca faça load silencioso de estado incompatível.

### 4.4 Frames

- Web: RGBA8888, `putImageData`.
- Desktop: `emmu-frame://localhost/frame?n=<nonce>` devolve BMP 24-bit, `Content-Type: image/bmp`, `Cache-Control: no-store`.
- Não tente passar `Vec<u8>`/array JSON de pixels por `invoke`: já foi tentado e é lento/fragil.
- O canvas que consome `emmu-frame://` fica **tainted**. Para miniatura, use `capturePreview()` → `mesen_capture_preview()` → PNG gerado no Rust.

### 4.5 Resoluções

| Console | Web WASM | Desktop/Mesen |
| --- | --- | --- |
| NES | 256×240 | 256×240 |
| SNES | 256×224 | 256×224 |
| GBA | 240×160 | 240×160 |
| GB/GBC | 160×144 | 160×144 |
| GG | 160×144 | 160×144 (overscan 48 px no Mesen) |
| WS/WSC | 224×144 | 224×144 (`AutoRotate`/ícones desligados no Mesen) |
| PCE | 282×242 | 256×242 |

Não “corrija” essa diferença PCE sem verificar overscan e o consumidor do frame. O `runFrame` do `emmu-ws` acumula `MASTER_CLOCK_HZ / 60` ciclos e executa um ou dois frames internos do Swanium por chamada; não remova esse acumulador para “simplificar”: o hardware roda a ~75,47 Hz e a UI chama a 60 Hz.

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

### 4.8 Controle WonderSwan

- O hardware tem dois direcionais de 4 vias (X e Y), A, B e Start; não há Select nem P2.
- `Up/Down/Left/Right` → primeiro pad (`KeyState::X1..X4` no Swanium; `up/down/left/right` no `DebugControllerState` do Mesen).
- `U/D/L/R` → segundo pad (`KeyState::Y1..Y4`; `u/d/l/r` no Mesen). A UI usa os nomes dos bindings `X/Y/L/R` e `coreButtonForFormat()` em `useEmulator.js` os converte para `U/D/L/R`.
- A UI esconde P2 e Select no WS, mostra um pad compacto para o segundo direcional no touch e rotula os bindings como “Segundo pad”.
- Swanium não expõe o botão de som do hardware; `Select` é ignorado.

### 4.9 Teclado

- `useShortcuts.js` usa `event.code`, com fallback para `event.key`.
- Alguns browsers embutidos emitem `code: ""`.
- `blur` da janela deve liberar todos os botões.
- `pressButton` no `Player.vue` chama `preventDefault()` e `blur()` no elemento para evitar scroll/foco preso.

### 4.10 Persistência

- IndexedDB: `emmu-library`, versão 2, stores `games` e `settings`.
- `MAX_SAVE_HISTORY = 10`.
- `CHECKPOINT_INTERVAL = 5000` ms.
- `MIN_LIBRARY_LOADING_MS = 450`.
- Filtros em `localStorage: emmu.library.filters`.
- Bindings de controle também em `localStorage`.

---

## 5. Arquitetura em fluxo

### Web

```text
App.vue
 → useEmulator.js
   → EmulationWorkerClient
     → snes.worker.js
       → initialize | restart | runFrame | setButton | saveState | loadState
       → emmu_snes / emmu_nes / emmu_gba / emmu_gbc / emmu_gb / emmu_gg / emmu_ws / emmu_pce
 → useAudio.js
   → audio-worklet.js
 → libraryStore.js
   → IndexedDB
```

Worker mensagens importantes: `initialize`, `restart`, `runFrame`, `setButton`, `saveState`, `loadState`. Buffers de frame/áudio/estado são transferidos de volta.

### Desktop

```text
Vue UI
 → MesenTauriClient (snes.js)
   → invoke("mesen_*") → platforms/desktop/src/lib.rs
     → emmu-mesen-sys → MesenCore.dylib/.so
       → dlopen(SDL2) para áudio
   → emmu-frame:// → frames BMP
   → mesen_capture_preview() → PNG para miniatura
```

Comandos Tauri: `mesen_init_rom`, `mesen_run_frame`, `mesen_set_button`, `mesen_reset`, `mesen_stop`, `mesen_release`, `mesen_save_state`, `mesen_load_state`, `mesen_capture_preview`, `mesen_set_volume`, `mesen_set_p2_enabled`.

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

`predev` e `prebuild` já chamam `build:wasm`.

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
EMMU_WS_TEST_ROM="/caminho/jogo.ws" cargo test -p emmu-ws
MESEN_TEST_ROM="/caminho/jogo.nes" cargo test -p emmu-mesen-sys
MESEN_PCE_TEST_ROM="/caminho/jogo.pce" cargo test -p emmu-mesen-sys
MESEN_GG_TEST_ROM="/caminho/jogo.gg" cargo test -p emmu-mesen-sys
MESEN_WS_TEST_ROM="/caminho/jogo.ws" cargo test -p emmu-mesen-sys
```

Use ROMs de jogo, não BIOS, para validação de UI/input.

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
5. Para PCE, confirme `TwoButtonGamepad`.
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
2. Verifique se o load rejeita magic diferente.
3. Verifique `libraryStore.js` e o histórico (10 estados).
4. A UI deve oferecer reinício limpo ou voltar à biblioteca.
5. Não apague automaticamente o estado corrompido sem confirmação.

### 7.8 WS lento, áudio desafinado ou segundo pad morto

1. Confirme que `crates/emmu-ws/src/lib.rs` ainda acumula `CYCLES_PER_UI_FRAME` e executa `System::run_frame` enquanto o carry ≥ `CYCLES_PER_FRAME`.
2. Não troque `audio_sample_rate()` para “compensar” 60 Hz: o APU do Swanium gera 24 kHz reais; o acumulador resolve o tempo.
3. Confirme `coreButtonForFormat()` em `useEmulator.js`: X/Y/L/R viram U/D/L/R apenas quando `format === "WS"`.
4. No desktop, `apply_button_to_state()` em `platforms/desktop/src/lib.rs` deve continuar mapeando U/D/L/R para os campos `u/d/l/r` do `DebugControllerState`.
5. Se o frame vier 224×157, `WS_LCD_SHOW_ICONS_OFFSET` em `connect_ws_controllers()` foi ligado por engano.

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

---

## 9. Estrutura crítica de arquivos

```text
platforms/web/ui/src/
├── App.vue                    # orquestração, autosave, diálogos
├── components/Player.vue      # controles touch e ações do player
├── composables/
│   ├── snes.js                # createEmulator + EmulationWorkerClient + MesenTauriClient
│   ├── useEmulator.js         # facade do core; setButton; capturePreview
│   ├── useShortcuts.js        # teclado
│   ├── useLibrary.js          # import/filtros/progresso/saves
│   ├── useAudio.js            # Web Audio
│   └── useControls.js         # bindings
├── stores/libraryStore.js     # IndexedDB
├── workers/
│   ├── snes.worker.js         # protocolo dos cores WASM
│   └── audio-worklet.js       # PCM
└── wasm/                      # gerado; NUNCA editar diretamente

platforms/desktop/src/lib.rs   # Tauri + Mesen + frames + saves
crates/emmu-mesen-sys/
├── src/lib.rs                 # ABI e wrappers
├── src/pce_palette.rs         # paleta PCE
├── build.rs                   # -lMesenCore
└── scripts/build-sdl2.sh      # runtime SDL2

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
7. Adicionar mapping em `platforms/desktop/src/lib.rs::mesen_init_rom`, se o Mesen suportar o console.
8. Atualizar `HelpDialog.vue`, `README.md`, `AGENTS.md` e tabela de licenças.
9. Definir magic de save state e política de histórico.
10. Rodar `npm run build`, `cargo check --workspace` e `cargo tauri build` se desktop mudou.

---

## 11. Submódulos e Git

- Todos os crates e plataformas são submódulos. Commits feitos dentro deles **não** atualizam o repositório principal automaticamente.
- Fluxo correto:
  ```sh
  cd crates/emmu-pce
  git add -A
  git commit -m "..."
  cd ../..
  git add crates/emmu-pce
  git commit -m "Atualiza gitlink do emmu-pce"
  ```
- Não edite diretamente `js/bridge.js`, `dist/`, `runtime/`, `runtime-link/` ou `src/wasm/`.
- `runtime/` e `runtime-link/` são gerados e ignorados.
- `src/wasm/` é gerado e ignorado; `dist/` é saída de build.
- `crates/emmu-ws` ainda é um diretório normal no repositório principal (sem remote/submódulo); toda a dependência de emulação fica dentro dele, em `vendor/swanian-core`.
- `crates/emmu-pce/vendor/jgenesis` e `crates/emmu-ws/vendor/swanian-core` **não** são submódulos: são códigos vendorizados dentro dos respectivos cores.
- `crates/emmu-gba/vendor/web-gba-emulator` e `crates/emmu-mesen-sys/vendor/SDL` são submódulos de terceiros; evite commits locais neles.
- `crates/tetanes-core`, `crates/emmu-super-sabicom` e `crates/emmu-pce/vendor` são excluídos do workspace por razões de build.

### Estado atual

- `crates/emmu-gg` é submodule de `EspetoRx/emmu-gg` @ `081ee8e`, já publicado.
- `crates/emmu-ws` foi adicionado como código local (Swanium MIT, @ `021d61d`); decida o remote antes de transformá-lo em submodule.
- A integração de UI/desktop do GG permanece em commits locais em `emmu-web` e `emmu-desktop`; atualize os gitlinks depois de commitar nesses submódulos.
- O repositório principal não foi pushed.
- `emmu-gb` e `emmu-pce` também têm commits locais; confirme se os remotos existem antes de `git push`.

---

## 12. O que NÃO fazer

- Não usar Mesen no web nem WASM no desktop.
- Não trocar `TwoButtonGamepad` por 6 botões no PCE “para expor X/Y”.
- Não remover o acumulador de ciclos do `emmu-ws` nem “corrigir” a taxa de áudio para 19 kHz: o Swanium roda a ~75 Hz e o acumulador converte para os 60 Hz da UI.
- Não tratar X/Y/L/R do WonderSwan como botões de face/shoulder: eles são o segundo direcional.
- Não editar arquivos gerados.
- Não committar `node_modules`, `dist`, `runtime`, `runtime-link` ou WASM gerado.
- Não usar `canvas.toBlob()` para miniatura desktop.
- Não passar frames por `invoke` como array de bytes.
- Não alterar offsets da ABI do Mesen sem comparar com os headers do MesenCE.
- Não apagar save states corrompidos sem confirmação.
- Não assumir que `event.code` existe.
- Não rodar `git push` sem confirmação explícita.
- Não esquecer de atualizar licenças ao introduzir código de terceiros.

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

- magic/version atualizado;
- teste de round-trip;
- teste de rejeição de estado inválido;
- histórico e recuperação na UI revisados.

Para mudanças em input:

- `pressed:true` e `pressed:false` observados;
- `blur` libera tudo;
- teste em ROM de jogo real;
- instrumentação removida;
- no WS, primeiro e segundo direcionais testados (web e desktop).

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

> Mude o menor arquivo possível, no backend correto, com o rebuild correto, preservando licenças e formatos de save. Se o problema é de input, prove o evento. Se é de frame, prove o protocolo. Se é de core, prove com ROM real.
