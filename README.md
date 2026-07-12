# claude-local-llm

Devcontainer単体で Ollama + CodeRouter + Claude Code CLI を動かすローカルLLM環境。

参考記事: https://note.com/zephel01/n/n0d53c62dca07
CodeRouter本体: https://github.com/zephel01/CodeRouter

## 動作環境

- Windows 11 + Docker Desktop (WSL2バックエンド)
- NVIDIA GPU (RTX 3060 Laptop 6GB で動作確認済み)
- VS Code + Dev Containers拡張

## 構成

```
.devcontainer/
  devcontainer.json
  Dockerfile
  entrypoint.sh
```

- **Ollama**: ローカルLLM推論サーバー (port 11434)
- **CodeRouter** (v2.9.0): リクエストをprofile別に振り分けるルーター (port 8088)
  - `claude-code-nim` / `nim-first` / `free-only-nim` / `openrouter-first` の4プロファイル
- **Claude Code CLI**: `ANTHROPIC_BASE_URL` を CodeRouter に向けて接続

## セットアップ

1. リポジトリをVS Codeで開き「Dev Containers: Reopen in Container」
2. コンテナ起動後、モデルpull

```bash
ollama pull qwen2.5-coder:7b
```

3. num_ctx焼き込み済みモデルを作成(Ollama側の`options.num_ctx`はCodeRouterのAnthropic→OpenAI翻訳パスでは効かないため必須)

```bash
mkdir -p ~/modelfiles && cd ~/modelfiles
cat > Modelfile.7b << 'EOF'
FROM qwen2.5-coder:7b
PARAMETER num_ctx 32768
EOF
ollama create qwen2.5-coder-32k:7b -f Modelfile.7b
```

4. CodeRouter本体をインストール(pip経由、npm版`coderouter`は同名の別パッケージなので注意)

```bash
uv tool install coderouter-cli
coderouter --version
```

5. `~/.coderouter/providers.yaml` と `~/.coderouter/.env` を配置(下記「providers.yaml 全文」参照)、`source ~/.coderouter/.env`
   - `.env`の`source`は**シェルプロセス単位**でしか有効にならない(ファイル自体は永続するが、読み込むかはシェルごとに別)。新しいターミナルタブを開くたび・コンテナ再起動のたびに毎回必要。手動が面倒な場合は`~/.bashrc`に1行追加して自動化する:
     ```bash
     echo 'source ~/.coderouter/.env' >> ~/.bashrc
     ```
6. 疎通確認

```bash
coderouter doctor --check-model ollama-qwen-coder-7b
```

7. 起動

```bash
coderouter serve --port 8088
# 別ターミナル
ANTHROPIC_BASE_URL=http://localhost:8088 ANTHROPIC_AUTH_TOKEN=dummy claude
```

`http://localhost:8088/dashboard` で使用providerと成功率をリアルタイム確認できる。

## モデル構成 (現状: 2026-07-11時点)

VRAM 6GBの制約上、ローカルは実質 `qwen2.5-coder-32k:7b` 一本を全profileのプライマリに据えている。

```yaml
profiles:
  - name: claude-code-nim
    providers:
      - ollama-qwen-coder-7b
      - nim-qwen3-coder-480b
      - openrouter-free
      - openrouter-gpt-oss-free
```

`qwen2.5-coder-32k:1.5b`は実用不可と判断し、**Ollamaモデル・providers.yaml定義とも完全に削除済み**(下記「既知の制約」参照)。

## 既知の制約

- **1.5bモデルは実用不可と判断し撤去済み。** 指示追従能力が低く、`こんにちは`のような簡単な挨拶にも無関係な内容やハルシネーションを返していた。しかもHTTP 200を返すため、CodeRouterのfallback判定(成功/失敗の二値)では「成功」扱いになり、後段の7bやNIMに切り替わらない問題があった(1.5bが1番目に居ると常にゴミ応答で固定される)。**profileの1番目には7b以上のモデルのみを置くこと。**
- **qwen3.5:9b / qwen3.5:4bも見送り。** 9bはVRAM 6GBに収まらずCPUオフロード(GPU56%程度)が発生する上、thinkingモデルで簡単な質問にも長大な思考過程を出力するため実用速度が出ない。4bはVRAM負荷は軽いがコーディング品質が7bに明確に劣る(「速いが頭が悪い」)。7b一本運用が現状の最適解。
- **gemma4:26b-a4bは検討不要。** Q4量子化でも16〜20GB級のVRAMが必要で、RTX 3060 6GBでは全く手が届かない。
- 7bクラスでも複雑なマルチステップタスクや大規模コンテキスト理解は不向き。用途は軽いQ&A・簡単なコード生成に留めるのが現実的。
- VRAM 6GB環境では14b以上のモデルはCPUオフロードが発生し大幅に遅くなるリスクあり。
- **NVIDIA NIMの無料枠モデルは頻繁にEOL(廃止)される。** 現在`qwen/qwen3-next-80b-a3b-instruct`で生存確認済み(2026-07-12、`nim-qwen3-coder-480b`/`nim-qwen-coder-32b-chat`とも`coderouter doctor --check-model`でauth+basic-chat/tool_calls [OK]・Exit 0確認済み)だが、将来的に410 Goneになる可能性が高い。EOLになった場合は下記手順でカタログを取り直すこと。なお`qwen/qwen3.5-122b-a10b`は前回EOL扱いだったが2026-07-12時点でカタログに復活していることを確認(NIM無料枠のカタログは流動的で、一度EOLになったモデルが再度現れることもある)。
- **`nim-qwen-coder-32b-chat`のtools宣言ズレを修正済み(2026-07-12)。** 実際は`tool_calls`をネイティブに返せるモデルなのに、providers.yamlでは`tools: false`宣言のままだったため`coderouter doctor`が`[NEEDS TUNING]`を出していた。`tools: true`に修正しExit 0確認済み(下記「providers.yaml全文」に反映済み)。
- OpenRouterの無料モデル(`:free`サフィックス)は未課金アカウントの場合、日次50リクエスト/分間20リクエストの上限がある(人気モデルはこれをすぐ使い切る)。$10課金すると日次1000リクエストに緩和されるが必須ではない。profileのfallback待機として機能する分には実害なし。

## トラブルシューティング

### `ollama list` が接続エラー

```bash
ps aux | grep ollama
```

プロセスが無ければ `entrypoint.sh` が起動していない。手動実行で切り分け:

```bash
bash /entrypoint.sh
```

### `uvx: command not found` / `coderouter: command not found`

`uv` のインストール先がPATHに乗っていない。Dockerfileで `UV_INSTALL_DIR="/usr/local/bin"` を指定して全ユーザー共通PATHに配置する(本リポジトリのDockerfileは対応済み)。`coderouter`本体は`uv tool install coderouter-cli`でインストールする(npm版の`coderouter`パッケージは無関係の別物なので入れないこと)。

### CodeRouterが404を返す

`providers.yaml` 内 `profiles:` の参照先モデルが `ollama list` に存在しない可能性。該当モデルをpullするか、既存モデルにマッピングし直す。設定変更後は **CodeRouterプロセスの再起動が必須**(自動リロードなし)。

```bash
ps aux | grep coderouter
kill <PID>
coderouter serve --port 8088
```

### NIMプロバイダが410 Goneを返す

そのモデルIDがEOL(廃止)された。現行の生存モデル一覧をカタログから直接取得して確認する:

```bash
curl -s https://integrate.api.nvidia.com/v1/models \
  -H "Authorization: Bearer $NVIDIA_NIM_API_KEY" | python3 -m json.tool | grep '"id"'
```

有望なモデルIDに差し替えたら `coderouter doctor --check-model <provider名>` で疎通確認(`auth+basic-chat`が`[OK]`になることを確認)。

### NIM/OpenRouterプロバイダが401を返す

`NVIDIA_NIM_API_KEY` / `OPENROUTER_API_KEY`がそのシェルセッションで未設定。`source ~/.coderouter/.env`を忘れずに(新しいターミナルタブを開くたび・コンテナ再起動のたびに必要。`~/.bashrc`に`source ~/.coderouter/.env`を追加済みなら自動)。`echo ${#OPENROUTER_API_KEY}`等で文字数が0でないか確認すると切り分けが早い。

### OpenRouterプロバイダが429を返す

429には2種類あるので、まずレスポンスヘッダーで切り分ける:

```bash
curl -sS -D - -o /dev/null https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3-coder:free","messages":[{"role":"user","content":"hi"}]}'
```

- `X-RateLimit-*`ヘッダーが付く → **自分のアカウントの日次/分間枠**(未課金は日次50・分間20)を使い切った。待つか$10課金で緩和。
- `X-RateLimit-*`ヘッダーが無く`retry-after`が数秒程度 → **upstream(モデル提供元)側の一時的な混雑**。自分の日次枠とは無関係で、数秒〜数分待てば解消することが多い。設定ミスではない。

いずれの場合もCodeRouterのprofileがfallbackで動く分には実害なし。

### zstd関連のollamaインストール失敗

Dockerfileに `apt-get install -y zstd` を追加(本リポジトリのDockerfileは対応済み)。

### `curl -v`でAPIキーを露出させない

Authorizationヘッダーを含むcurl出力をそのまま貼らないこと。過去に一度発生し、NVIDIA NIMキーを失効・再発行した実績あり。

## providers.yaml 全文(現状・2026-07-11時点で疎通確認済み)

```yaml
allow_paid: false
default_profile: claude-code-nim
display_timezone: Asia/Tokyo
mode_aliases:
  default: claude-code-nim
  coding: claude-code-nim
  general: claude-code-nim
  reasoning: nim-first
  multi: claude-code-nim
  fast: free-only-nim
  cheap: free-only-nim
  think: nim-first
  vision: claude-code-nim
providers:
  - name: ollama-qwen-coder-7b
    kind: openai_compat
    base_url: http://localhost:11434/v1
    model: qwen2.5-coder-32k:7b
    paid: false
    timeout_s: 120
    output_filters: [strip_thinking]
    capabilities:
      chat: true
      streaming: true
      tools: false
  - name: nim-qwen3-coder-480b
    kind: openai_compat
    base_url: https://integrate.api.nvidia.com/v1
    model: qwen/qwen3-next-80b-a3b-instruct
    api_key_env: NVIDIA_NIM_API_KEY
    paid: false
    timeout_s: 120
    capabilities:
      chat: true
      streaming: true
      tools: true
  - name: nim-qwen-coder-32b-chat
    kind: openai_compat
    base_url: https://integrate.api.nvidia.com/v1
    model: qwen/qwen3-next-80b-a3b-instruct
    api_key_env: NVIDIA_NIM_API_KEY
    paid: false
    timeout_s: 60
    output_filters: [strip_thinking]
    capabilities:
      chat: true
      streaming: true
      tools: true
  - name: openrouter-free
    kind: openai_compat
    base_url: https://openrouter.ai/api/v1
    model: qwen/qwen3-coder:free
    api_key_env: OPENROUTER_API_KEY
    paid: false
    timeout_s: 60
    capabilities:
      chat: true
      streaming: true
      tools: true
  - name: openrouter-gpt-oss-free
    kind: openai_compat
    base_url: https://openrouter.ai/api/v1
    model: openai/gpt-oss-120b:free
    api_key_env: OPENROUTER_API_KEY
    paid: false
    timeout_s: 60
    capabilities:
      chat: true
      streaming: true
      tools: true
profiles:
  - name: claude-code-nim
    providers:
      - ollama-qwen-coder-7b
      - nim-qwen3-coder-480b
      - openrouter-free
      - openrouter-gpt-oss-free
  - name: nim-first
    providers:
      - nim-qwen3-coder-480b
      - openrouter-free
      - openrouter-gpt-oss-free
  - name: free-only-nim
    providers:
      - ollama-qwen-coder-7b
      - nim-qwen3-coder-480b
      - openrouter-free
      - openrouter-gpt-oss-free
  - name: openrouter-first
    providers:
      - openrouter-free
      - openrouter-gpt-oss-free
      - ollama-qwen-coder-7b
      - nim-qwen3-coder-480b
```

APIキー(`NVIDIA_NIM_API_KEY` / `OPENROUTER_API_KEY`)は `~/.coderouter/.env` に `export` 形式で保存し、起動前に `source` すること。このファイル自体はリポジトリにコミットしない。

## profileの切り替え方

`coderouter serve`起動時に`--mode <profile名>`で指定する(環境変数は`CODEROUTER_MODE`)。Claude Code CLI起動時の環境変数では切り替わらないので注意。

```bash
coderouter serve --port 8088 --mode nim-first
```

## ダッシュボード (http://localhost:8088/dashboard)

`coderouter serve`起動中はブラウザで開ける。以下がリアルタイムで確認できる:

- 現在のprofile名、稼働時間、リクエスト総数
- provider別の試行回数・成功率(`ok%`)・直近エラー
- fallback発生率、paid-gateブロック件数、capability degraded件数(cache_control等の非対応機能)
- 直近60サンプルのリクエスト数推移グラフ
- 直近イベントログ(`try-provider` → `provider-ok` / `provider-failed`の遷移)

NIMやOpenRouterがEOL/レート制限で落ちてfallbackが発動しているか、意図した通り7bが使われているかは、まずここを見て確認するのが早い。数値APIとしても`curl http://localhost:8088/metrics.json`で同じ情報がJSON取得できる。

## 今後の検討事項

- モデルサイズ上位化(14b等)による精度改善余地
- profile別に別モデルを使い分ける構成(VRAM拡張時)
- 用途をシンプルなQ&Aに絞った運用ルール整備
- NIM無料モデルのEOL監視を定期化(現状は`coderouter doctor`の手動実行頼み)
