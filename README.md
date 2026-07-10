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
  - `coding` / `writing` / `multi` の3プロファイル
- **Claude Code CLI**: `ANTHROPIC_BASE_URL` を CodeRouter に向けて接続

## セットアップ

1. リポジトリをVS Codeで開き「Dev Containers: Reopen in Container」
2. コンテナ起動後、モデルpull

```bash
ollama pull qwen2.5-coder:7b
```

3. CodeRouterの設定ファイル `~/.coderouter/providers.yaml` を確認・編集(下記「モデル構成」参照)
4. 動作確認

```bash
ollama list
curl http://localhost:11434
curl http://localhost:8088/v1/models
claude
```

## モデル構成 (現状: B案)

VRAM 6GBの制約上、3プロファイル全てを `qwen2.5-coder:7b` 一本に寄せている。

```yaml
profiles:
  - name: coding
    providers:
      - ollama-qwen-coder-7b
  - name: writing
    providers:
      - ollama-qwen-coder-7b
  - name: multi
    providers:
      - ollama-qwen-coder-7b
```

`qwen2.5:7b` / `qwen2.5vl:7b` は削除済み(VRAM節約)。画像添付リクエストは `multi` プロファイル経由でcoderモデルに流れるため精度は期待できない。

## 既知の制約

- 7bクラスモデルはClaude Code本体の複雑なツール呼び出し・長いシステムプロンプトの解釈が不安定。単純な質問(「こんにちは」等)でも意図しないファイル作成提案などが発生することがある。
- 複雑なマルチステップタスクや大規模コンテキスト理解は不向き。用途は軽いQ&A・簡単なコード生成に留めるのが現実的。
- VRAM 6GB環境では14b以上のモデルはCPUオフロードが発生し大幅に遅くなるリスクあり。

## トラブルシューティング

### `ollama list` が接続エラー

```bash
ps aux | grep ollama
```

プロセスが無ければ `entrypoint.sh` が起動していない。手動実行で切り分け:

```bash
bash /entrypoint.sh
```

### `uvx: command not found`

`uv` のインストール先がPATHに乗っていない。Dockerfileで `UV_INSTALL_DIR="/usr/local/bin"` を指定して全ユーザー共通PATHに配置する(本リポジトリのDockerfileは対応済み)。

### CodeRouterが404を返す

`providers.yaml` 内 `profiles:` の参照先モデルが `ollama list` に存在しない可能性。該当モデルをpullするか、既存モデルにマッピングし直す。設定変更後は **CodeRouterプロセスの再起動が必須**(自動リロードなし)。

```bash
ps aux | grep coderouter
kill <PID> <PID>
nohup uvx --from coderouter-cli coderouter serve --port 8088 > /tmp/coderouter.log 2>&1 &
disown
```

### zstd関連のollamaインストール失敗

Dockerfileに `apt-get install -y zstd` を追加(本リポジトリのDockerfileは対応済み)。

## 今後の検討事項

- モデルサイズ上位化(14b等)による精度改善余地
- profile別に別モデルを使い分ける構成(VRAM拡張時)
- 用途をシンプルなQ&Aに絞った運用ルール整備
