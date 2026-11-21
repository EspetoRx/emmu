# Emmu

> Uma biblioteca de jogos e um emulador multiplataforma, com uma única interface para navegador, desktop e dispositivos móveis.

O Emmu reúne núcleos de emulação de consoles clássicos atrás de uma interface Vue 3. No **navegador**, cada sistema roda em WebAssembly dentro de um Web Worker, com áudio via Web Audio. No **desktop**, os mesmos formatos são executados pelo núcleo nativo **MesenCE**, integrado por FFI e empacotado com SDL2. A biblioteca, as miniaturas e os save states ficam no IndexedDB; nada de ROM é distribuído com o projeto.

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
| Navegador | Web Workers + WebAssembly | Executa os seis núcleos WASM fora da thread de UI |
| Desktop | Tauri 2 + Rust | Integra o MesenCE, áudio SDL, menu nativo e protocolo de frames |
| Persistência | IndexedDB + `localStorage` | ROMs, save states, miniaturas, filtros e controles |
| Cores | Rust/JS vendorizado | Cada console tem um crate isolado, com dependências dentro da própria pasta |

A mesma UI atende web e desktop. A troca de backend acontece em `createEmulator()`: com Tauri, instancia-se `MesenTauriClient`; sem Tauri, cria-se o cliente do Web Worker.

---

## Sistemas suportados

| Console | Extensões | Core no navegador | Core no desktop | Save state |
| --- | --- | --- | --- | --- |
| Nintendo Entertainment System | `.nes` | `emmu-nes` → TetaNES | MesenCE (NES) | serializado pelo core / `.mss` |
| Super Nintendo | `.sfc`, `.smc`, `.fig` | `emmu-snes` → Super Sabicom | MesenCE (SNES) | bincode / `.mss` |
| Game Boy Advance | `.gba` | `emmu-gba` → Web-GBA/gbajs | MesenCE (GBA) | `EMMUSAVE1` / `.mss` |
| Game Boy | `.gb` | `emmu-gb` → oxGBC (`Dmg`) | MesenCE (`Gameboy`) | `EMMUGMB1` / `.mss` |
| Game Boy Color | `.gbc` | `emmu-gbc` → oxGBC (`Cgb`) | MesenCE (`AutoFavorGbc`) | `EMMUGBC1` / `.mss` |
| PC Engine / TurboGrafx-16 | `.pce` | `emmu-pce` → JGenesis `pce-core` | MesenCE (`TurboGrafx`) | `EMMUPCE1` / `.mss` |

Detalhes importantes:

- **PC Engine** usa HuCard (`.pce`); não há suporte a jogos de CD-ROM.
- O PCE web usa gamepad de **2 botões** (I/II). O modo 6 botões alternava o estado extra em cada transição de `CLR` e fazia as setas pararem de responder em vários jogos.
- O PCE web gera frames RGBA8888 de **282×242**; o desktop/Mesen publica **256×242**.
- O GBA web exige o `tools/build-bridge.mjs` para concatenar o core JavaScript antes do `wasm-pack`.
- SNES com chips de melhoria (Super FX, SA-1 e outros) não é suportado pelo Super Sabicom.
- Nenhuma BIOS ou ROM de jogo é incluída. A BIOS open-source do GBA usada pelo Mesen vem de `Cult-of-GBA/BIOS`.

---

## Recursos

- **Biblioteca persistente:** ROMs são guardadas como blobs no IndexedDB; a abertura aceita vários arquivos de uma vez. Se uma entrada antiga perder o blob, basta reimportar a mesma ROM.
- **Overlay de carregamento:** mostra progresso real (`x de y jogos`), barra e porcentagem enquanto o IndexedDB é percorrido com cursor.
- **Save states:** checkpoint automático a cada 5 segundos, ao voltar para a biblioteca, ao background e ao desmontar o player. Save manual entra no histórico; os 10 estados anteriores ficam disponíveis em **Histórico**.
- **Recuperação:** estado corrompido oferece reinício limpo ou retorno à biblioteca para escolher outro save.
- **Controles configuráveis:** teclado e toque, com `pointerdown/up/cancel/leave`, `preventDefault()` e liberação de todas as teclas quando a janela perde foco.
- **Áudio:** fila PCM limitada com `AudioWorklet` e fallback para `createBufferSource`. No desktop, o volume também é repassado ao Mesen/SDL.
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
       │                                            └─ emmu_pce.wasm
       └─ useAudio.js ── audio-worklet.js
```

O worker recebe `initialize`, `restart`, `runFrame`, `setButton`, `saveState` e `loadState`, e transfere buffers de frame/áudio/estado de volta para a UI.

### Desktop

```text
Vue UI
  └─ snes.js :: MesenTauriClient
       ├─ invoke("mesen_*")  →  platforms/desktop/src/lib.rs
       │                         └─ emmu-mesen-sys → MesenCore.dylib/.so
       │                                              └─ dlopen(SDL2) para áudio
       └─ emmu-frame://localhost/frame?n=<nonce>  →  frames BMP gerados no Rust
```

O Mesen é inicializado em modo headless. Os frames chegam pelas notificações `PPU_FRAME_DONE` (NES) e `REFRESH_SOFTWARE_RENDERER` (SNES/GBA/GB/GBC/PCE). Save states são gravados em arquivos `.mss` temporários e devolvidos à UI como bytes para o IndexedDB.

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
│   ├── emmu-pce/                   # core PC Engine via JGenesis pce-core
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

Antes do build desktop, prepare o runtime MesenCE + SDL2:

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

No macOS, o instalador aparece em `target/release/bundle/dmg/Emmu_0.1.0_aarch64.dmg` e o app em `target/release/bundle/macos/Emmu.app`.

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
cargo test -p emmu-pce -p emmu-gb -p emmu-gbc -p emmu-mesen-sys -p desktop

# Testes com ROM real (opcionais)
EMMU_NES_TEST_ROM="/caminho/jogo.nes" cargo test -p emmu-nes
EMMU_GBC_TEST_ROM="/caminho/jogo.gbc" cargo test -p emmu-gbc
EMMU_GB_TEST_ROM="/caminho/jogo.gb" cargo test -p emmu-gb
EMMU_PCE_TEST_ROM="/caminho/jogo.pce" cargo test -p emmu-pce
MESEN_TEST_ROM="/caminho/jogo.nes" cargo test -p emmu-mesen-sys
MESEN_PCE_TEST_ROM="/caminho/jogo.pce" cargo test -p emmu-mesen-sys
```

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
| `crates/emmu-pce` | `EspetoRx/emmu-pce` @ `e8a9860` | core PC Engine | GPL-3.0-only |
| `crates/emmu-mesen-sys` | `EspetoRx/emmu-mesen-sys` @ `46dab68` | FFI Mesen + runtime | sem campo declarado |
| `crates/emmu-super-sabicom` | `EspetoRx/emmu-super-sabicom` @ `a7b80ad` | core SNES | MIT |
| `crates/tetanes-core` | `EspetoRx/tetanes-core` @ `e27c108` | core NES | MIT OR Apache-2.0 |
| `platforms/desktop` | `EspetoRx/emmu-desktop` @ `f6bca67` | app Tauri | sem campo declarado |
| `platforms/web` | `EspetoRx/emmu-web` @ `05d658a` | SPA Vue/Vite | sem campo declarado |
| `crates/emmu-gba/vendor/web-gba-emulator` | `alexcerezo/Web-GBA-Emulator` @ `e760d30` | core GBA JS | BSD-2-Clause |
| `crates/emmu-mesen-sys/vendor/SDL` | `libsdl-org/SDL` @ `release-2.32.10` | áudio dlopen no desktop | zlib |
| `crates/emmu-pce/vendor/jgenesis` | código vendorizado (não submodule) @ `8d1bdfb` | `pce-core` | GPL-3.0-only |

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
| `emmu-pce` e JGenesis `pce-core` | GPL-3.0-only | `jsgroth/jgenesis`, commit `8d1bdfba...`; subset HuCard |
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
crates/emmu-pce/LICENSE
crates/emmu-pce/UPSTREAM.txt
crates/emmu-pce/vendor/jgenesis/LICENSE
crates/emmu-super-sabicom/LICENSE
crates/tetanes-core/LICENSE-MIT
crates/tetanes-core/LICENSE-APACHE
crates/emmu-mesen-sys/LICENSE-GBA-BIOS.txt
crates/emmu-mesen-sys/BUNDLE.md
crates/emmu-mesen-sys/vendor/SDL/LICENSE.txt
crates/emmu-mesen-sys/runtime/LICENSE-SDL2.txt   # gerado pelo script
```

> **Atenção:** os núcleos GB, GBC e PCE são GPL-3.0; o MesenCE também é GPLv3. Um bundle desktop que inclui Mesen e/ou um bundle web que inclui esses WASM modules precisa observar as obrigações da GPLv3, incluindo disponibilizar o código-fonte correspondente e manter os avisos de licença. Este documento é informativo, não uma opinião jurídica.

---

## Notas legais

- O Emmu **não inclui ROMs**, BIOS proprietárias, jogos ou dados de save de terceiros.
- O usuário deve possuir ou obter legalmente as ROMs que importa.
- A BIOS GBA incluída é a implementação open-source do projeto `Cult-of-GBA/BIOS`, sob MIT; Mesen a instala em `<home>/Firmware/gba_bios.bin` quando não há arquivo de mesmo tamanho.
- O PC Engine implementa apenas HuCard; System Cards e jogos de CD-ROM não são suportados.
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
| Botão “cola” após soltar | evento sem `code` ou janela sem foco | `useShortcuts.js` tem fallback para `event.key` e libera tudo no `blur` |
| Miniatura não salva no desktop | canvas tainted por `emmu-frame://` | use `mesen_capture_preview()` (PNG gerado no Rust) |
| `EXC_BAD_ACCESS` ao sair | chamada FFI após `Release()` | mantenha o guard de shutdown de `emmu-mesen-sys` |
| Build desktop no Windows falha | `build.rs` espera `.dylib`/`.so` | use macOS/Linux ou adicione suporte a `.dll` |

---

## Contribuindo

Agentes de IA e assistentes de código devem ler [`AGENTS.md`](AGENTS.md) antes de alterar qualquer arquivo: ele contém o mapa de decisão, os contratos internos, os playbooks de debugging e as armadilhas históricas.

1. Crie uma branch no submódulo relevante.
2. Rode `cargo fmt --all -- --check`, `cargo check --workspace` e os testes do core alterado.
3. Para mudanças na UI, rode `npm run build` em `platforms/web/ui`.
4. Commite no submódulo e depois atualize o gitlink no repositório principal.
5. Documente mudanças de ABI, formato de save state e licenças de código vendorizado.

Bons jogos — e lembre-se de preservar os créditos e as licenças de cada núcleo.
