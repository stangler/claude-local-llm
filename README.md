# claude-local-llm

Devcontainer単体で Ollama + CodeRouter + Claude Code CLI を動かすローカルLLM環境。

参考記事: https://note.com/zephel01/n/n0d53c62dca07

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
- **CodeRouter**: リクエストをprofile別に振り分けるルーター (port 8088)
  - `claude-code-nim` / `nim-first` / `free-only-nim` の3プロファイル
- **Claude Code CLI**: `ANTHROPIC_BASE_URL` を CodeRouter に向けて接続

## セットアップ

1. リポジトリをVS Codeで開き「Dev Containers: Reopen in Container」
2. コンテナ起動後、モデルpull

```bash
ollama pull qwen2.5-coder:7b
ollama pull qwen2.5-coder:1.5b
```

3. **num_ctx をModelfileに焼き込む(重要・下記「既知の制約」参照)**

```bash
cat > /tmp/Modelfile-7b << 'EOF'
FROM qwen2.5-coder:7b
PARAMETER num_ctx 32768
EOF
ollama create qwen2.5-coder-32k:7b -f /tmp/Modelfile-7b

cat > /tmp/Modelfile-1.5b << 'EOF'
FROM qwen2.5-coder:1.5b
PARAMETER num_ctx 32768
EOF
ollama create qwen2.5-coder-32k:1.5b -f /tmp/Modelfile-1.5b
```

4. CodeRouterの設定ファイル `~/.coderouter/providers.yaml` を確認・編集(下記「モデル構成」参照)。NVIDIA NIM / OpenRouter を使う場合は `~/.coderouter/.env` にAPIキーを `export` 形式で書いて `source` する

```bash
# ~/.coderouter/.env
export NVIDIA_NIM_API_KEY=nvapi-...
export OPENROUTER_API_KEY=sk-or-...
source ~/.coderouter/.env
```

5. 動作確認

```bash
ollama list
curl http://localhost:11434/api/tags
coderouter serve --port 8088
```

別ターミナルで:

```bash
ANTHROPIC_BASE_URL=http://localhost:8088 \
ANTHROPIC_AUTH_TOKEN=dummy \
claude
```

## ダッシュボード(便利)

CodeRouter起動中は `http://localhost:8088/dashboard` が使える。devcontainer内ならVS Codeの「ポート」タブで8088を転送してブラウザで開く。

- どのリクエストがどの `provider`(モデル)で処理されたかがリアルタイムで見える
- 成功率・フォールバック発生率が一目で分かる
- 「今の返答、結局どのモデルが答えたのか?」を毎回ログを目grepしなくても確認できる

`coderouter serve` のログにも同じ情報が出る(`msg: "provider-ok", "provider": "..."` の行)ので、CLIだけで確認したい場合はそちらでも可。

## モデル構成 (現状)

VRAM 6GBの制約上、Ollamaはこの2モデルに絞っている。**Modelfileで `num_ctx: 32768` を焼き込んだバージョン**(`qwen2.5-coder-32k:*`)を使うこと — 理由は下記「既知の制約」参照。

```yaml
providers:
  - name: ollama-qwen-coder-7b
    kind: openai_compat
    base_url: http://localhost:11434/v1
    model: qwen2.5-coder-32k:7b
    output_filters: [strip_thinking]
    capabilities:
      tools: false   # doctorの実測どおり(下記参照)

  - name: ollama-qwen2.5-coder-1.5b
    kind: openai_compat
    base_url: http://localhost:11434/v1
    model: qwen2.5-coder-32k:1.5b
    output_filters: [strip_thinking]
    capabilities:
      tools: false

profiles:
  - name: claude-code-nim
    providers:
      - ollama-qwen-coder-7b
      - ollama-qwen2.5-coder-1.5b
      - nim-qwen3-coder-480b     # NVIDIA NIM free (下記参照)
      - openrouter-free
      - openrouter-gpt-oss-free
```

NVIDIA NIMは無料枠を使う場合、モデルIDが頻繁にEOL(廃止)になる。2026-07時点で稼働確認できたのは以下のみ:

- `qwen/qwen3.5-122b-a10b` (旧 `qwen/qwen3-coder-480b-a35b-instruct` は2026-06-11にEOL)
- Moonshot系(`kimi-k2-instruct` / `kimi-k2-thinking` / `kimi-k2-instruct-0905` / `kimi-k2.6`)は2026-07時点で無料エンドポイントから軒並み消えている(410 Gone or 404)。**Moonshot系は無料枠では使わない前提で組む**
- `meta/llama-3.3-70b-instruct` はネットワーク到達性が不安定(transport error多発)で見送り

導入前に必ず `coderouter doctor --check-model <provider名>` で疎通確認すること。モデルIDはNVIDIA側の都合で無警告に変わる。

## 既知の制約

- **7bクラスモデルは、num_ctxを正しく設定しないとClaude Code本体の長いシステムプロンプト・ツール定義を握りつぶし、「こんにちは」のような雑談でも無関係なファイル作成やコード実行を暴発させる。** Ollamaのデフォルト `num_ctx` は2048で、Claude Codeのシステムプロンプトは軽く1万トークンを超えるため、素の状態では必ず起きる。
- **`providers.yaml` の `extra_body.options.num_ctx` は効かないケースがある。** 実測したところ、CodeRouterの生OpenAI互換パス(`/v1/chat/completions`直叩き)では機能するが、Claude Codeが実際に使うAnthropic→OpenAI翻訳パス(`/v1/messages`経由)では`num_ctx`がOllamaに転送されず、doctorの`num_ctx`プローブが`[NEEDS TUNING]`のまま解消しないことがある。**確実な回避策はOllamaのModelfileに`PARAMETER num_ctx 32768`を焼き込んだ別名モデルを作り、そちらをprovidersに指定すること**(上記セットアップ手順3参照)。
- 7b/1.5bクラスは `tool_calls` をネイティブ形式ではなく本文にJSON文字列として書き出す(doctor実測)。CodeRouterの修復層(repair layer)が実行時に拾って正しい形式に直すため実害はないが、`capabilities.tools` は実態に合わせて `false` で宣言しておくのが正直(repair層が引き続き機能する)。
- 複雑なマルチステップタスクや大規模コンテキスト理解は不向き。用途は軽いQ&A・簡単なコード生成に留めるのが現実的。
- VRAM 6GB環境では14b以上のモデルはCPUオフロードが発生し大幅に遅くなるリスクあり。
- NIMの無料エンドポイントはモデルIDが頻繁に変わる/消える。`providers.yaml`を長期間放置すると気づかぬうちに全滅する。定期的に `coderouter doctor` で疎通確認すること。

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

`uv` のインストール先がPATHに乗っていない。恒久インストールする場合:

```bash
uv tool install coderouter-cli
```

Dockerfileで `UV_INSTALL_DIR="/usr/local/bin"` を指定して全ユーザー共通PATHに配置する(本リポジトリのDockerfileは対応済み)。

### CodeRouterが404を返す

`providers.yaml` 内 `profiles:` の参照先モデルが `ollama list` に存在しない、またはNVIDIA NIM/OpenRouter側でモデルIDがEOL/変更されている可能性。`coderouter doctor --check-model <provider名>` で切り分ける。設定変更後は **CodeRouterプロセスの再起動が必須**(自動リロードなし)。

```bash
ps aux | grep coderouter
kill <PID>
coderouter serve --port 8088
```

### 雑談だけで `Write` やコード実行が暴発する

上記「既知の制約」参照。`coderouter doctor --check-model <provider名>` の `num_ctx` プローブを確認し、`[NEEDS TUNING]` ならModelfileへの焼き込みで解決する。

### `num_ctx` をproviders.yamlの `extra_body` で指定したのにdoctorが直らないと言う

上記の既知の制約どおり、Anthropic翻訳パスでは効かないことがある。Modelfile焼き込み版に切り替える。

### NVIDIA NIMのモデルが404/410を返す

NIM無料枠のモデルはIDが頻繁に変わる/EOLになる。`build.nvidia.com/<vendor>` で現行モデル一覧を確認し、`providers.yaml`の`model:`を更新後、`coderouter doctor --check-model <provider名>`で再確認する。

### zstd関連のollamaインストール失敗

Dockerfileに `apt-get install -y zstd` を追加(本リポジトリのDockerfileは対応済み)。

### APIキーが露出した場合

`curl -v` 等でヘッダーをそのまま貼ってしまった場合は速やかに build.nvidia.com / openrouter.ai の管理画面でキーを失効・再発行し、`~/.coderouter/.env` を更新して `source` し直す。

## 今後の検討事項

- モデルサイズ上位化(14b等)による精度改善余地
- profile別に別モデルを使い分ける構成(VRAM拡張時)
- 用途をシンプルなQ&Aに絞った運用ルール整備
- NIM/OpenRouterのモデルIDが変わった際の自動検知(定期`doctor`実行のcron化など)