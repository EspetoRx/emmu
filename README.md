# Emmu

> Uma biblioteca de jogos e um emulador multiplataforma, com uma única interface para navegador, desktop e dispositivos móveis.

O Emmu reúne núcleos de emulação de consoles clássicos atrás de uma interface Vue 3. No **navegador**, cada sistema roda em WebAssembly dentro de um Web Worker, com áudio via Web Audio. No **desktop**, os mesmos formatos são executados pelo núcleo nativo **MesenCE**, integrado por FFI e empacotado com SDL2 — com exceção do **Nintendo 64**, do **Nintendo DS** e do **PlayStation Portable**, que rodam o mesmo módulo WASM dentro do WebView porque o MesenCE não implementa esses consoles. O PSP roda na thread principal (não no worker) porque o PPSSPP exige WebGL2 e pthreads com `SharedArrayBuffer`. A biblioteca, as miniaturas e os save states ficam no IndexedDB; nada de ROM é distribuído com o projeto.

---

## Sumário

- [Visão geral](#visão-geral)
- [Sistemas suportados](#sistemas-suportados)
- [Recursos](#recursos)
- [Arquitetura](#arquitetura)
- [Árvore de arquivos](#árvore-de-arquivos)
- [Pré-requisitos](#pré-requisitos)
- [Como compilar e executar](#como-compilar-e-executar)
- [Testes](#testes)
- [Submódulos e subprojetos](#submódulos-e-subprojetos)
- [Licenças e créditos](#licenças-e-créditos)
- [Notas legais](#notas-legais)
- [Solução de problemas](#solução-de-problemas)

---

## Visão geral

| Camada | Tecnologia | Papel |
| --- | --- | --- |
| Interface | Vue 3 + Vite 6 | Biblioteca, player, controles, save states, filtros e diálogos |
| Navegador | Web Workers + WebAssembly | Executa onze núcleos WASM fora da thread de UI; o PSP roda na main thread com WebGL2 |
| Desktop | Tauri 2 + Rust | Integra o MesenCE, áudio SDL, menu nativo e protocolo de frames |
| Persistência | IndexedDB + `localStorage` | ROMs, save states, miniaturas, filtros e controles |
| Cores | Rust/JS vendorizado | Cada console tem um crate isolado, com dependências dentro da própria pasta |

A mesma UI atende web e desktop. A troca de backend acontece em `createEmulator()`: com Tauri, instancia-se `MesenTauriClient`; sem Tauri, cria-se o cliente do Web Worker. N64 e NDS são as exceções — `createEmulator()` sempre cria o cliente do Web Worker para eles, inclusive no desktop. O PSP é outra exceção: `createEmulator()` sempre cria o cliente main-thread (`PspClient`/`PspAdapter`), que roda o PPSSPP diretamente na thread de UI com WebGL2, dentro do Web Worker não há suporte a pthreads; isso vale para web e desktop.

---

## Sistemas suportados

| Console | Extensões | Core no navegador | Core no desktop | Save state |
| --- | --- | --- | --- | --- |
| Nintendo Entertainment System | `.nes` | `emmu-nes` → TetaNES | MesenCE (NES) | serializado pelo core / `.mss` |
| Super Nintendo | `.sfc`, `.smc`, `.fig` | `emmu-snes` → Super Sabicom | MesenCE (SNES) | bincode / `.mss` |
| Game Boy Advance | `.gba` | `emmu-gba` → Web-GBA/gbajs | MesenCE (GBA) | `EMMUSAVE1` / `.mss` |
| Game Boy | `.gb` | `emmu-gb` → oxGBC (`Dmg`) | MesenCE (`Gameboy`) | `EMMUGMB1` / `.mss` |
| Game Boy Color | `.gbc` | `emmu-gbc` → oxGBC (`Cgb`) | MesenCE (`AutoFavorGbc`) | `EMMUGBC1` / `.mss` |
| Sega Game Gear | `.gg` | `emmu-gg` → JGenesis `smsgg-core` | MesenCE (`GameGear`) | `EMMUGG01` / `.mss` |
| Sega Master System | `.sms` | `emmu-sms` → JGenesis `smsgg-core` | MesenCE (`MasterSystem`) | `EMMUSMS1` / `.mss` |
| WonderSwan / WonderSwan Color | `.ws`, `.wsc` | `emmu-ws` → Swanium | MesenCE (`Auto` Mono/Color) | `EMMUWS01` / `.mss` |
| PC Engine / TurboGrafx-16 | `.pce` | `emmu-pce` → JGenesis `pce-core` | MesenCE (`TurboGrafx`) | `EMMUPCE1` / `.mss` |
| Nintendo DS | `.nds` | `emmu-nds` → dust | WASM no WebView (sem Mesen) | `EMMUNDS1` + versão u32 |
| Nintendo 64 | `.z64`, `.n64`, `.v64` | `emmu-n64` → N64Wasm (mupen64plus) | WASM no WebView (sem Mesen) | gzip `/savestate.gz` |
| PlayStation Portable | `.psp`, `.iso`, `.cso`, `.chd`, `.pbp`, `.elf`, `.prx` | `emmu-psp` → PPSSPP libretro (EmulatorJS) | WASM no WebView (sem Mesen) | `EMMUPSP1` + versão u32 |

Detalhes importantes:

- **Game Gear** usa os botões 1/2 (mapeados de A/B) e Start; não há Select, P2, X/Y ou L/R. ROMs `.gg` também podem ser importadas dentro de um `.zip`.
- **Master System** usa os botões 1/2 (mapeados de A/B) e Start; não há Select, X/Y ou L/R, mas há P2. O core web gera frames de **256×224** (NTSC) ou **256×240** (PAL), e ROMs `.sms` também podem vir de um `.zip`.
- **WonderSwan** tem dois direcionais de 4 vias: setas controlam o primeiro; S/A/Q/W (ou X/Y/L/R nos bindings) controlam o segundo. Z/X são A/B e Enter é Start. Não há Select nem P2. `.ws` e `.wsc` usam o mesmo core e também podem vir de um `.zip`.
- **PC Engine** usa HuCard (`.pce`); não há suporte a jogos de CD-ROM.
- O PCE web usa gamepad de **2 botões** (I/II). O modo 6 botões alternava o estado extra em cada transição de `CLR` e fazia as setas pararem de responder em vários jogos.
- O PCE web gera frames RGBA8888 de **282×242**; o desktop/Mesen publica **256×242**.
- **Nintendo DS** roda o core `dust` com BIOS HLE e firmware gerado em runtime; nenhum arquivo de sistema copyrightado é distribuído. A UI empilha as duas telas em um frame RGBA8888 de **256×384 (2:3)**. Toque ou clique na metade inferior usa o painel sensível; A/B/X/Y/L/R/Start/Select são mapeáveis e o console tem um único jogador. O save state é `EMMUNDS1` + versão `u32` + estado do core.
- **Nintendo 64** mantém os quatro jogadores no frontend, mas o N64Wasm envia botões e analógico sempre ao Jogador 1. O analógico tem quatro ações mapeáveis (`Analógico ↑/↓/←/→`) e um pad compacto na interface touch. O frame é **320×240 (4:3)** no web e no desktop.
- **PlayStation Portable** roda o PPSSPP libretro via adaptador Emscripten vendorizado, na thread principal do navegador/WebView (o core usa WebGL2 + pthreads e exige isolamento cross-origin: COOP/COEP + `SharedArrayBuffer`). A/B/X/Y correspondem a ×/○/□/△, com L/R, Select, Start e analógico digital (`Analógico ↑/↓/←/→`); o console tem um único jogador. O áudio é gerenciado pelo próprio core (WebAudio/OpenAL dentro do Emscripten), e o volume é aplicado diretamente nos nós de ganho. O frame é **480×272** e o save state é um envelope `EMMUPSP1` com o estado gzipado do core e um ZIP da save data. Arquivos `.zip` com uma entrada PSP também são aceitos.
- O GBA web exige o `tools/build-bridge.mjs` para concatenar o core JavaScript antes do `wasm-pack`.
- SNES com chips de melhoria (Super FX, SA-1 e outros) não é suportado pelo Super Sabicom.
- Nenhuma BIOS ou ROM de jogo é incluída. A BIOS open-source do GBA usada pelo Mesen vem de `Cult-of-GBA/BIOS`.

---

## Recursos

- **Biblioteca persistente:** ROMs são guardadas como blobs no IndexedDB; a abertura aceita vários arquivos de uma vez, incluindo `.zip` com ROMs `.gg`, `.sms`, `.ws`, `.wsc` e PSP. Se uma entrada antiga perder o blob, basta reimportar a mesma ROM.
- **Overlay de carregamento:** mostra progresso real (`x de y jogos`), barra e porcentagem enquanto o IndexedDB é percorrido com cursor.
- **Save states:** checkpoint automático a cada 5 segundos, ao voltar para a biblioteca, ao background e ao desmontar o player. Save manual entra no histórico; os 10 estados anteriores ficam disponíveis em **Histórico**.
- **Recuperação:** estado corrompido oferece reinício limpo ou retorno à biblioteca para escolher outro save.
- **Alertas:** fila de toasts com 10 segundos de duração, pausa ao passar o mouse, barra de progresso, botão de fechar e dedupe de mensagens idênticas.
- **Controles configuráveis:** teclado e toque, com `pointerdown/up/cancel/leave`, `preventDefault()` e liberação de todas as teclas quando a janela perde foco.
- **Áudio:** fila PCM limitada com `AudioWorklet` e fallback para `createBufferSource`. No desktop, o volume também é repassado ao Mesen/SDL. No PSP, o áudio é do próprio core (WebAudio via Emscripten/OpenAL) e o volume ajusta os nós de ganho das fontes ativas.
- **Filtros da biblioteca:** busca sem acento, ordenação e agrupamento por título similar, console, formato e existência de save. Não é filtro de vídeo.
- **Player:** tela cheia, reinício, volume, salvar estado, carregar estado, histórico e indicação de console.
- **Menus nativos:** no desktop, Arquivo (abrir ROM, voltar à biblioteca, sair), Emulação (configurar controles) e Ajuda emitem eventos para a UI.
- **Miniaturas:** no desktop, o último frame é capturado em PNG diretamente no Rust (`mesen_capture_preview`), evitando o canvas “tainted” do protocolo customizado.

---

## Arquitetura

### Navegador

```text
App.vue
  └─ useEmulator.js
       ├─ EmulationWorkerClient ── snes.worker.js ──┬─ emmu_snes.wasm
       │                                            ├─ emmu_nes.wasm
       │                                            ├─ emmu_gba (JS bridge + WASM)
       │                                            ├─ emmu_gbc.wasm
       │                                            ├─ emmu_gb.wasm
       │                                            ├─ emmu_gg.wasm
       │                                            ├─ emmu_sms.wasm
       │                                            ├─ emmu_ws.wasm
       │                                            ├─ emmu_pce.wasm
       │                                            ├─ emmu_nds.wasm + adapter.js
       │                                            └─ emmu_n64.wasm + n64wasm.js/.wasm/assets.zip
       ├─ PspClient (main thread) ── psp/adapter.js ─┴─ ppsspp_libretro.js/.wasm + ppsspp-assets.zip
       └─ useAudio.js ── audio-worklet.js
```

O worker recebe `initialize`, `restart`, `runFrame`, `setButton`, `setTouch`, `endTouch`, `setVolume`, `saveState` e `loadState`, e transfere buffers de frame/áudio/estado de volta para a UI. O N64 carrega o runtime Emscripten vendorizado em `public/wasm/n64/` e o injeta no worker; o NDS importa o módulo `emmu_nds` gerado pelo `wasm-pack` diretamente pelo `adapter.js`. O PSP **não** usa o worker: `PspClient`/`PspAdapter` rodam na main thread e carregam `ppsspp_libretro.js`, `ppsspp_libretro.wasm` e `ppsspp-assets.zip` de `public/wasm/psp/`, com WebGL2, pthreads e `SharedArrayBuffer` (headers COOP/COEP em dev, preview e Tauri). O adaptador expõe o mesmo contrato de `runFrame`/`setButton`/`saveState`/`loadState`/`restart`/`setVolume`/`capturePreview` dos demais cores.

### Desktop

```text
Vue UI
  └─ snes.js :: MesenTauriClient
       ├─ invoke("mesen_*")  →  platforms/desktop/src/lib.rs
       │                         └─ emmu-mesen-sys → MesenCore.dylib/.so
       │                                              └─ dlopen(SDL2) para áudio
       └─ emmu-frame://localhost/frame?n=<nonce>  →  frames BMP gerados no Rust
```

O Mesen é inicializado em modo headless. Os frames chegam pelas notificações `PPU_FRAME_DONE` (NES) e `REFRESH_SOFTWARE_RENDERER` (SNES/GBA/GB/GBC/GG/SMS/WS/PCE). Save states são gravados em arquivos `.mss` temporários e devolvidos à UI como bytes para o IndexedDB. N64, NDS e PSP não passam por esta camada: `mesen_init_rom()` rejeita os três explicitamente. N64 e NDS usam o worker WASM no WebView; o PSP usa o `PspAdapter` na main thread do WebView (mesmo runtime do navegador). O save state do N64 é um gzip em `/savestate.gz`; o do NDS usa `EMMUNDS1`; o do PSP usa `EMMUPSP1`.

### Persistência

- Banco IndexedDB `emmu-library`, versão 2, com stores `games` e `settings`.
- `MAX_SAVE_HISTORY = 10`.
- `localStorage`: `emmu.library.filters` e bindings de controle.
- `emmu-frame://` é um protocolo assíncrono do Tauri, com `Cache-Control: no-store`.

---

## Árvore de arquivos

```text
emmu/
├── .vscode/
│   ├── chrome-for-testing.sh       # localiza/abre o Chrome de testes
│   ├── extensions.json             # extensões recomendadas (Rust/Vue)
│   ├── launch.json                 # configurações “Emmu: Web” e “Emmu: Desktop”
│   ├── tasks.json                  # tarefas de build do web e do desktop
│   └── web-dev-server.sh           # sobe Vite na porta fixa 5173
├── crates/
│   ├── emmu-core/                  # trait Console + enum JoypadButton (interface comum)
│   ├── emmu-frontend/              # crate auxiliar/placeholder compartilhado
│   ├── emmu-nes/                   # wrapper WASM do TetaNES
│   ├── emmu-snes/                  # wrapper WASM do Super Sabicom
│   ├── emmu-gba/                   # ponte WASM/JS do Web-GBA (gbajs)
│   ├── emmu-gbc/                   # core Game Boy Color via oxGBC
│   ├── emmu-gb/                    # core Game Boy DMG via oxGBC
│   ├── emmu-gg/                    # core Sega Game Gear via JGenesis smsgg-core
│   │   └── vendor/jgenesis/        # subset SMS/GG vendorizado (GPL-3.0-only)
│   ├── emmu-sms/                   # core Sega Master System via JGenesis smsgg-core
│   │   └── vendor/jgenesis/        # subset SMS/GG vendorizado (GPL-3.0-only)
│   ├── emmu-ws/                    # core WonderSwan via Swanium
│   │   └── vendor/swanian-core/    # subset do core Swanium vendorizado (MIT)
│   ├── emmu-pce/                   # core PC Engine via JGenesis pce-core
│   ├── emmu-n64/                   # core Nintendo 64 via N64Wasm (WASM no worker/WebView)
│   │   └── vendor/n64wasm/         # N64Wasm MIT compilado para WASM (não editar)
│   ├── emmu-nds/                   # core Nintendo DS via dust (WASM no worker/WebView)
│   │   └── vendor/dust/            # dust GPL-3.0 + emu-utils/arm-decoder
│   ├── emmu-psp/                   # core PSP via PPSSPP libretro (main thread/WebView)
│   │   ├── js/adapter.js           # PspAdapter: integra Emscripten ao contrato do Emmu
│   │   └── vendor/ppsspp-ejs/      # PPSSPP libretro + assets (GPL-2.0, não editar)
│   ├── emmu-mesen-sys/             # FFI da ABI do MesenCE + runtime SDL2/BIOS
│   ├── emmu-super-sabicom/         # core SNES upstream (MIT)
│   └── tetanes-core/               # core NES upstream (MIT OR Apache-2.0)
├── platforms/
│   ├── desktop/                    # aplicativo Tauri 2 “Emmu”
│   │   ├── capabilities/default.json
│   │   ├── icons/icon.png
│   │   ├── src/lib.rs              # comandos Tauri, frames, save states, menu
│   │   ├── src/main.rs             # entry point
│   │   ├── build.rs                # tauri-build + rpath
│   │   └── tauri.conf.json         # janela, bundle, recursos e hooks
│   └── web/
│       ├── Cargo.toml              # membro virtual do workspace
│       └── ui/                     # SPA Vue 3 + Vite
│           ├── index.html
│           ├── package.json
│           ├── vite.config.js      # porta 5173, strictPort
│           ├── public/             # assets estáticos (atualmente vazio)
│           └── src/
│               ├── App.vue         # orquestração, diálogos, atalhos, autosave
│               ├── main.js
│               ├── style.css
│               ├── components/     # Library, Player, GameCard, diálogos, overlay
│               ├── composables/    # useEmulator, useLibrary, useAudio, snes.js, ...
│               ├── stores/         # libraryStore.js (IndexedDB)
│               ├── workers/        # snes.worker.js + audio-worklet.js
│               └── wasm/           # pacotes gerados por wasm-pack (ignorados no git)
├── .gitignore                      # target, node_modules, dist, ROMs e saves
├── .gitmodules                     # declaração dos submódulos
├── Cargo.toml                      # workspace Cargo + patch local do tetanes-core
├── Cargo.lock
├── package-lock.json               # lockfile legado da raiz (sem package.json)
└── README.md                       # este documento
```

Cada submódulo tem seu próprio `README.md` com árvore, API, build e licenças. Os diretórios `vendor/` dentro dos cores também documentam a procedência do código de terceiros.

---

## Pré-requisitos

### Comuns

| Ferramenta | Versão mínima recomendada | Uso |
| --- | --- | --- |
| Git | qualquer versão recente | clonar e atualizar submódulos |
| Rust | **1.88+** | edition 2024 e MSRV do TetaNES |
| `rustup` | — | instalar toolchain e alvo WASM |
| `wasm-pack` | recente | gerar os pacotes WebAssembly |
| Node.js e npm | LTS (18+) | Vite, Vue e scripts de build |
| Tauri CLI | `cargo install tauri-cli --version "^2"` | builds desktop |

```sh
rustup toolchain install stable
rustup target add wasm32-unknown-unknown
cargo install wasm-pack
cargo install tauri-cli --version "^2"
```

### macOS

- Xcode e Command Line Tools: `xcode-select --install`.
- Para bundle `.app`/`.dmg`, manter o Xcode instalado.
- O script de runtime gera um SDL2 universal (`arm64` + `x86_64`).

### Linux

Em Debian/Ubuntu:

```sh
sudo apt update
sudo apt install -y build-essential curl wget file pkg-config \
  libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev \
  libxdo-dev libssl-dev patchelf
```

`patchelf` é usado para ajustar o rpath `$ORIGIN` do MesenCE. Sem ele, o instalador dependerá de `LD_LIBRARY_PATH`.

### Windows

- O **navegador** funciona normalmente com Node.js, Rust e `wasm-pack`.
- O fluxo **desktop/Mesen ainda não é suportado oficialmente no Windows**: `emmu-mesen-sys/build.rs` e `scripts/build-sdl2.sh` hoje tratam apenas `MesenCore.dylib` e `MesenCore.so`. Para desktop, use macOS/Linux ou contribua com o suporte a `MesenCore.dll`, `SDL2.dll` e ao linker do MSVC.

### Mobile

Os scripts `mobile:android:*` e `mobile:ios:*` existem na UI e usam Tauri 2, mas exigem Android SDK/NDK ou Xcode/CocoaPods. O suporte é experimental; o caminho maduro é web + desktop.

---

## Como compilar e executar

### 1. Clonar com submódulos

```sh
git clone --recurse-submodules <url-do-repositorio> emmu
cd emmu
```

Se o clone já existir:

```sh
git submodule update --init --recursive
```

### 2. Web (desenvolvimento)

```sh
cd platforms/web/ui
npm install
npm run dev
```

O `predev` roda automaticamente `npm run build:wasm`, que recompila os seis cores. A UI fica em `http://127.0.0.1:5173` (porta fixa).

### 3. Web (produção)

```sh
cd platforms/web/ui
npm run build
npm run preview
```

Saída: `platforms/web/ui/dist`.

### 4. Desktop

Antes do build desktop, prepare o runtime MesenCE + SDL2 e os assets do N64Wasm e do PPSSPP. O comando único (recomendado) faz tudo e é o usado por `npm run desktop:build`:

```sh
bash platforms/desktop/scripts/prepare-bundle.sh
```

Ou, para preparar apenas o runtime MesenCE + SDL2:

```sh
# macOS — MESEN_LIB_DIR opcional; padrão: /tmp/MesenCE/InteropDLL/obj.osx-arm64
./crates/emmu-mesen-sys/scripts/build-sdl2.sh

# Linux x86_64
MESEN_TARGET=x86_64-unknown-linux-gnu \
MESEN_LIB_DIR=/caminho/para/MesenCE \
./crates/emmu-mesen-sys/scripts/build-sdl2.sh

# Linux ARM64
MESEN_TARGET=aarch64-unknown-linux-gnu \
MESEN_LIB_DIR=/caminho/para/MesenCE \
./crates/emmu-mesen-sys/scripts/build-sdl2.sh
```

O script:

1. compila SDL2 2.32.10 apenas com áudio a partir de `vendor/SDL`;
2. copia `MesenCore.dylib`/`.so` e `libSDL2...` para `crates/emmu-mesen-sys/runtime/`;
3. cria o alias de linker em `runtime-link/`;
4. ajusta rpath (`@loader_path` no macOS, `$ORIGIN` no Linux);
5. copia a licença do SDL2.

O `prepare-bundle.sh` chama esse script quando necessário e completa o pacote com `n64wasm.js`, `n64wasm.wasm`, `assets.zip` (N64), `ppsspp_libretro.js`, `ppsspp_libretro.wasm`, `ppsspp-assets.zip` (PSP) e os avisos de licença de terceiros. Falha com mensagem clara se faltar alguma dependência.

Depois:

```sh
cd platforms/desktop
cargo tauri dev
cargo tauri build
```

Ou, a partir da UI:

```sh
cd platforms/web/ui
npm run desktop:dev
npm run desktop:build
```

No macOS, o instalador aparece em `target/release/bundle/dmg/Emmu_0.2.0_aarch64.dmg` e o app em `target/release/bundle/macos/Emmu.app`.

### Dependências incluídas no instalador

| Dependência | Uso | Como vai no pacote |
| --- | --- | --- |
| `MesenCore.dylib` / `.so` | todos os consoles Mesen | `bundle.resources` → `Contents/Resources/` |
| `libSDL2-2.0.0.dylib` / `libSDL2-2.0.so.0` | áudio do Mesen (`dlopen`) | `bundle.resources` + rpath `@loader_path`/`$ORIGIN` |
| `n64wasm.js`, `n64wasm.wasm`, `assets.zip` | N64 no WebView | embutidos em `dist/wasm/n64/` **e** declarados em `bundle.resources` |
| `ppsspp_libretro.js`, `ppsspp_libretro.wasm`, `ppsspp-assets.zip` | PSP no WebView | embutidos em `dist/wasm/psp/` **e** declarados em `bundle.resources` |
| BIOS GBA | GBA no Mesen | `include_bytes!` no executável, gravada em `<home>/Firmware/` |
| Textos de licença | SDL2, Mesen (GPL-3 integral), N64Wasm, PPSSPP (GPL-2), Web-GBA, dust, BIOS | `runtime/LICENSE-*.txt` + `THIRD-PARTY-NOTICES.txt` via `bundle.resources` |
| 11 módulos WASM + runtime PPSSPP | navegador e N64/NDS/PSP desktop | embedados no executável como `frontendDist`; validados pelo `postbuild` |

O `postbuild` da UI (`scripts/check-bundle-assets.mjs`) falha o build se algum WASM ou asset N64/PSP estiver ausente em `dist/`, evitando gerar um instalador incompleto. Detalhes em `crates/emmu-mesen-sys/BUNDLE.md`.

### 5. Mobile (experimental)

```sh
cd platforms/web/ui
npm run mobile:android:init
npm run mobile:android:dev
npm run mobile:android:build

npm run mobile:ios:init
npm run mobile:ios:dev
npm run mobile:ios:build
```

### 6. Atualizando submódulos

```sh
git submodule update --init --recursive
git submodule foreach 'git fetch && git checkout origin/main'
git add .gitmodules <caminhos-dos-submódulos>
git commit -m "Atualiza submódulos"
```

Para commits dentro de um submódulo, entre nele, commite normalmente e depois atualize o gitlink no repositório principal.

---

## Testes

```sh
# Formatação e checagem geral
cargo fmt --all -- --check
cargo check --workspace

# Testes dos núcleos e do desktop
cargo test -p emmu-gg -p emmu-sms -p emmu-ws -p emmu-pce -p emmu-gb -p emmu-gbc -p emmu-n64 -p emmu-nds -p emmu-psp -p emmu-mesen-sys -p desktop

# Testes com ROM real (opcionais)
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

O smoke test do PSP é feito pela UI: abrir `.iso`/`.cso`/`.pbp`/`.elf` e validar vídeo (WebGL2), áudio/volume, D-pad/analógico/botões, restart, save/load e histórico. O runtime PPSSPP precisa de isolamento cross-origin (COOP/COEP); o Vite e o Tauri já enviam os headers.

`cargo test -p emmu-mesen-sys` e `-p desktop` exigem que `MesenCore` esteja linkável (runtime preparado ou `MESEN_LIB_DIR`).

Smoke test SNES:

```sh
cargo run -p emmu-snes --example snes_smoke -- Jogo.sfc
```

---

## Submódulos e subprojetos

| Caminho | Repositório fixado | Finalidade | Licença declarada |
| --- | --- | --- | --- |
| `crates/emmu-core` | `EspetoRx/emmu-core` @ `6350ed9` | trait `Console` e `JoypadButton` | sem campo/licença declarada |
| `crates/emmu-frontend` | `EspetoRx/emmu-frontend` @ `e397d66` | crate auxiliar | sem campo/licença declarada |
| `crates/emmu-nes` | `EspetoRx/emmu-nes` @ `2959380` | wrapper WASM NES | MIT |
| `crates/emmu-snes` | `EspetoRx/emmu-snes` @ `7b73668` | wrapper WASM SNES | MIT |
| `crates/emmu-gba` | `EspetoRx/emmu-gba` @ `878a2a6` | ponte WASM/JS GBA | MIT (+ BSD-2-Clause no vendor) |
| `crates/emmu-gbc` | `EspetoRx/emmu-gbc` @ `da3763c` | core GBC | GPL-3.0-only |
| `crates/emmu-gb` | `EspetoRx/emmu-gb` @ `5150825` | core GB DMG | GPL-3.0-only |
| `crates/emmu-gg` | `EspetoRx/emmu-gg` @ `081ee8e` | core Sega Game Gear | GPL-3.0-only |
| `crates/emmu-sms` | `EspetoRx/emmu-sms` @ `d55bd69` | core Sega Master System | GPL-3.0-only |
| `crates/emmu-ws` | diretório local (ainda sem submódulo/remote) | core WonderSwan via Swanium | MIT |
| `crates/emmu-pce` | `EspetoRx/emmu-pce` @ `e8a9860` | core PC Engine | GPL-3.0-only |
| `crates/emmu-n64` | `EspetoRx/emmu-n64` @ `c066186` | core Nintendo 64 via N64Wasm | GPL-3.0-only (+ MIT no vendor) |
| `crates/emmu-nds` | `EspetoRx/emmu-nds` @ `70d64fd` | core Nintendo DS via dust | GPL-3.0 |
| `crates/emmu-psp` | `EspetoRx/emmu-psp` @ `49dd022` (commit local; remote vazio) | core PSP via PPSSPP libretro | GPL-3.0-or-later (+ GPL-2.0 no vendor) |
| `crates/emmu-mesen-sys` | `EspetoRx/emmu-mesen-sys` @ `46dab68` | FFI Mesen + runtime | sem campo declarado |
| `crates/emmu-super-sabicom` | `EspetoRx/emmu-super-sabicom` @ `a7b80ad` | core SNES | MIT |
| `crates/tetanes-core` | `EspetoRx/tetanes-core` @ `e27c108` | core NES | MIT OR Apache-2.0 |
| `platforms/desktop` | `EspetoRx/emmu-desktop` @ `f6bca67` | app Tauri | sem campo declarado |
| `platforms/web` | `EspetoRx/emmu-web` @ `05d658a` | SPA Vue/Vite | sem campo declarado |
| `crates/emmu-gba/vendor/web-gba-emulator` | `alexcerezo/Web-GBA-Emulator` @ `e760d30` | core GBA JS | BSD-2-Clause |
| `crates/emmu-mesen-sys/vendor/SDL` | `libsdl-org/SDL` @ `release-2.32.10` | áudio dlopen no desktop | zlib |
| `crates/emmu-pce/vendor/jgenesis` | código vendorizado (não submodule) @ `8d1bdfb` | `pce-core` | GPL-3.0-only |
| `crates/emmu-gg/vendor/jgenesis` | código vendorizado (não submodule) @ `8d1bdfb` | `smsgg-core` (subset GG) | GPL-3.0-only |
| `crates/emmu-sms/vendor/jgenesis` | código vendorizado (não submodule) @ `8d1bdfb` | `smsgg-core` (subset SMS) | GPL-3.0-only |
| `crates/emmu-ws/vendor/swanian-core` | código vendorizado @ `021d61d` | core WonderSwan Swanium | MIT |

---

## Licenças e créditos

Este projeto combina código próprio e software de terceiros. Respeite cada licença ao redistribuir.

| Componente | Licença | Crédito / observação |
| --- | --- | --- |
| `emmu-core`, `emmu-frontend`, `platforms/desktop`, `platforms/web`, `platforms/web/ui` | não declarada | código Emmu; não há arquivo `LICENSE` nesses submódulos |
| `emmu-nes`, `emmu-snes`, `emmu-gba`, `emmu-super-sabicom` | MIT | `Copyright (c) 2026 EspetoRx` nos wrappers; `Copyright (c) 2022 Hideyuki Tanaka` no Super Sabicom |
| `tetanes-core` | MIT OR Apache-2.0 | `Copyright (c) 2021 Luke Petherbridge <me@lukeworks.tech>` |
| `emmu-gb`, `emmu-gbc` | GPL-3.0-only | texto GPLv3 em `LICENSE`; código em `vendor/oxgbc-core` |
| oxGBC | GPL-3.0-only | `mxmgorin/oxgbc`, commit `b95ff230...`; autor `troidem <mxmgorin@gmail.com>` |
| `emmu-gg` e JGenesis `smsgg-core` | GPL-3.0-only | `jsgroth/jgenesis`, commit `8d1bdfba...`; subset SMS/GG com hardware forçado para Game Gear |
| `emmu-sms` e JGenesis `smsgg-core` | GPL-3.0-only | `jsgroth/jgenesis`, commit `8d1bdfba...`; subset SMS/GG com hardware forçado para Master System |
| `emmu-ws` e Swanium | MIT | `bubio/Swanium` @ `021d61d`; `Copyright (c) 2026 bubio`; subset `crates/core` vendorizado |
| `emmu-pce` e JGenesis `pce-core` | GPL-3.0-only | `jsgroth/jgenesis`, commit `8d1bdfba...`; subset HuCard |
| `emmu-n64` | GPL-3.0-only | código Emmu sob `LICENSE`; wrapper/fachada WASM para N64Wasm |
| `emmu-nds` e dust | GPL-3.0 | `Kelpsyberry/dust` @ `76d79f2`; `emu-utils` e `arm-decoder` são dependências de build sem licença própria no upstream e seguem este trabalho GPL-3.0 |
| `emmu-psp` | GPL-3.0-or-later | fachada/adaptador Emmu; `LICENSE` no crate |
| PPSSPP libretro (EmulatorJS) | GPL-2.0-or-later | `@emulatorjs/core-ppsspp` 4.2.3 (RetroArch 1.21.0 + PPSSPP 2025-06-14); `Copyright (C) 2012-2025 PPSSPP Project / Dolphin Emulator Project`; avisos adicionais do PSPSDK; ver `crates/emmu-psp/UPSTREAM.txt` |
| N64Wasm | MIT | `nbarkhina/N64Wasm` @ `3056c89d` (2024-11-12); `Copyright (c) 2021 Neil Barkhina`; mupen64plus + ParaLLEl-RDP compilados para WebAssembly |
| Web-GBA / gbajs | BSD-2-Clause | `Copyright (c) 2012, Jeffrey Pfau`; adaptação web por `alexcerezo` |
| MesenCE / Mesen 2 | GPL-3.0 | `Copyright (C) 2014-2025 Sour`; binário externo, distribuído via `runtime/` |
| SDL2 2.32.10 | zlib | `Copyright (C) 1997-2025 Sam Lantinga <slouken@libsdl.org>` |
| BIOS GBA | MIT | `Copyright 2020 - 2021 DenSinH and fleroviux`, `Cult-of-GBA/BIOS`, commit `61158c3` |
| Vue 3 | MIT | `Copyright (c) 2018-present, Evan You` |
| Tauri API (JS) | Apache-2.0 OR MIT | `@tauri-apps/api` |
| Vite | MIT | `Copyright (c) 2019-present, Evan You e colaboradores` |
| `@vitejs/plugin-vue` | MIT | time Vue |
| `wasm-bindgen`, `js-sys`, `wasm-bindgen-futures` | MIT OR Apache-2.0 | rustwasm |
| `png` (Rust) | MIT OR Apache-2.0 | usado na captura de miniaturas |
| `meru-interface` | MIT | usado por `emmu-snes` e Super Sabicom |

Arquivos de licença importantes:

```text
crates/emmu-nes/LICENSE
crates/emmu-snes/LICENSE
crates/emmu-gba/LICENSE
crates/emmu-gba/LICENSE-WEB-GBA-EMULATOR.txt
crates/emmu-gbc/LICENSE
crates/emmu-gbc/vendor/oxgbc-core/LICENSE-GPL-3.0
crates/emmu-gbc/vendor/oxgbc-core/UPSTREAM.txt
crates/emmu-gb/LICENSE
crates/emmu-gb/vendor/oxgbc-core/LICENSE-GPL-3.0
crates/emmu-gb/vendor/oxgbc-core/UPSTREAM.txt
crates/emmu-gg/LICENSE
crates/emmu-gg/UPSTREAM.txt
crates/emmu-gg/vendor/jgenesis/LICENSE
crates/emmu-ws/LICENSE
crates/emmu-ws/UPSTREAM.txt
crates/emmu-ws/vendor/swanian-core/LICENSE
crates/emmu-pce/LICENSE
crates/emmu-pce/UPSTREAM.txt
crates/emmu-pce/vendor/jgenesis/LICENSE
crates/emmu-n64/LICENSE
crates/emmu-n64/UPSTREAM.txt
crates/emmu-n64/vendor/n64wasm/LICENSE
crates/emmu-psp/LICENSE
crates/emmu-psp/UPSTREAM.txt
crates/emmu-psp/vendor/ppsspp-ejs/license.txt
crates/emmu-super-sabicom/LICENSE
crates/tetanes-core/LICENSE-MIT
crates/tetanes-core/LICENSE-APACHE
crates/emmu-mesen-sys/LICENSE-GBA-BIOS.txt
crates/emmu-mesen-sys/BUNDLE.md
crates/emmu-mesen-sys/vendor/SDL/LICENSE.txt
crates/emmu-mesen-sys/runtime/LICENSE-SDL2.txt   # gerado pelo script
```

> **Atenção:** os núcleos GB, GBC, GG e PCE são GPL-3.0; o MesenCE também é GPLv3. O runtime PPSSPP do PSP é GPL-2.0-or-later. Um bundle desktop que inclui Mesen e/ou um bundle web que inclui esses WASM modules precisa observar as obrigações das respectivas GPLs, incluindo disponibilizar o código-fonte correspondente e manter os avisos de licença. Este documento é informativo, não uma opinião jurídica.

---

## Notas legais

- O Emmu **não inclui ROMs**, BIOS proprietárias, jogos ou dados de save de terceiros.
- O usuário deve possuir ou obter legalmente as ROMs que importa.
- A BIOS GBA incluída é a implementação open-source do projeto `Cult-of-GBA/BIOS`, sob MIT; Mesen a instala em `<home>/Firmware/gba_bios.bin` quando não há arquivo de mesmo tamanho.
- O PC Engine implementa apenas HuCard; System Cards e jogos de CD-ROM não são suportados.
- O Nintendo 64 usa o mesmo WASM no web e no desktop. O backend Mesen rejeita `N64` explicitamente. O save state é um gzip gerado pelo core; o histórico é mantido pelo Emmu.
- O Nintendo DS usa o mesmo WASM no web e no desktop. O backend Mesen rejeita `NDS` explicitamente. O core `dust` usa BIOS HLE e firmware gerado em runtime, sem distribuir arquivos de sistema proprietários.
- O PSP usa o mesmo runtime PPSSPP no web e no desktop, na main thread do WebView. O backend Mesen rejeita `PSP` explicitamente. O PPSSPP depende de assets de sistema (fontes, shaders, tabelas VFPU) do projeto PPSSPP, distribuídos sob GPL-2.0 em `ppsspp-assets.zip`; nenhuma BIOS ou firmware proprietário de PSP é incluído.
- Nomes de consoles e jogos pertencem aos respectivos proprietários.

---

## Solução de problemas

| Sintoma | Causa provável | Solução |
| --- | --- | --- |
| `Submodule ... not initialized` | clone sem `--recursive` | `git submodule update --init --recursive` |
| `wasm-pack: command not found` | ferramenta não instalada | `cargo install wasm-pack` |
| Erro ao compilar GBA web | bridge JS não gerado | rode `node tools/build-bridge.mjs` em `crates/emmu-gba` |
| Desktop sem áudio | SDL2 não encontrado pelo `dlopen` | rode `scripts/build-sdl2.sh` e reinicie o app |
| Tela PCE preta no desktop | paleta padrão ausente | confirme `src/pce_palette.rs` em `emmu-mesen-sys` |
| Setas do PCE travadas no menu | gamepad 6 botões | use `PceInputDevice::TwoButtonGamepad` (já é o padrão) |
| WS lento ou com áudio desafinado | `runFrame` chamado a 60 Hz contra um hardware de ~75 Hz | confirme o acumulador de ciclos em `crates/emmu-ws/src/lib.rs` |
| Segundo direcional do WS não responde | binding errado | use S/A/Q/W (X/Y/L/R nos bindings) ou o pad na tela; no desktop, U/D/L/R da ABI do Mesen |
| Botão “cola” após soltar | evento sem `code` ou janela sem foco | `useShortcuts.js` tem fallback para `event.key` e libera tudo no `blur` |
| Miniatura não salva no desktop | canvas tainted por `emmu-frame://` | use `mesen_capture_preview()` (PNG gerado no Rust) |
| `EXC_BAD_ACCESS` ao sair | chamada FFI após `Release()` | mantenha o guard de shutdown de `emmu-mesen-sys` |
| Build desktop no Windows falha | `build.rs` espera `.dylib`/`.so` | use macOS/Linux ou adicione suporte a `.dll` |
| N64 abre com erro “não suportado no backend desktop nativo” | console enviado ao Mesen | `createEmulator()` deve usar o worker WASM para N64 também sob Tauri |
| Main loop do N64 não inicia / tela preta | `config.txt` sem `disableAudioSync`/`mobileMode` | índices 39 e 43 devem ser `1` no `js/bridge.js` |
| Frame N64 em um quadrante ou com altura diferente no desktop | canvas trocado no restart ou proporção errada | use `_neil_reset()` e `aspect-ratio: 4 / 3` (`.n64-canvas`) |
| Analógico N64 não responde | hook de input ausente ou `mobileMode` desligado | confirme `__n64PushControls()` e `cfgLines[43] = '1'` |
| NDS abre com erro “não suportado pelo backend Mesen” | console enviado ao Mesen | `createEmulator()` deve usar o worker WASM para NDS também sob Tauri |
| Tela NDS achatada ou toque fora de lugar | `aspect-ratio` sem limite de largura | `.nds-canvas` deve manter `2 / 3` e limitar a largura pelo `max-height` |
| Painel sensível NDS não responde | canvas sem eventos de ponteiro | confirme `set-touch`/`end-touch` no `Player.vue` e `setTouch`/`endTouch` no worker |
| PSP abre tela preta ou não inicia | falta isolamento cross-origin / WebGL2 | confirme os headers COOP/COEP no Vite/Tauri e `crossOriginIsolated === true`; o PPSSPP roda na main thread |
| PSP sem áudio ou áudio distorcido | fonte OpenAL/WebAudio não conectada | o volume atua em `Module.AL.currentCtx.sources[].gain.gain.value`; aba precisa estar em foco |
| Save state PSP falha | envelope `EMMUPSP1` inválido ou gzip ausente | valide magic/versão/tamanhos e o estado gzipado em `/game.state` no MEMFS |
| PSP com botões/analógico mortos | mapeamento RetroArch errado | `simulate_input` usa A=0, B=8, X=1, Y=9, Start=3, Select=2, D-pad=4..7, L/R=10/11, analógico=16..19 |

---

## Contribuindo

Agentes de IA e assistentes de código devem ler [`AGENTS.md`](AGENTS.md) antes de alterar qualquer arquivo: ele contém o mapa de decisão, os contratos internos, os playbooks de debugging e as armadilhas históricas.

1. Crie uma branch no submódulo relevante.
2. Rode `cargo fmt --all -- --check`, `cargo check --workspace` e os testes do core alterado.
3. Para mudanças na UI, rode `npm run build` em `platforms/web/ui`.
4. Commite no submódulo e depois atualize o gitlink no repositório principal.
5. Documente mudanças de ABI, formato de save state e licenças de código vendorizado.

## Versionamento

O Emmu segue versionamento semântico. A versão atual da interface é `0.2.0`, registrada em `platforms/web/ui/package.json` e `package-lock.json`. O suporte a Nintendo 64, Nintendo DS e PlayStation Portable entra nesta versão.

Bons jogos — e lembre-se de preservar os créditos e as licenças de cada núcleo.
