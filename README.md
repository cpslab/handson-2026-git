# handson-2026-git 運営用

受講者ブランチの監視と、コンフリクト演習の仕込みをするスクリプトです。
`main` とは履歴を共有しない orphan ブランチ `admin` に置いています。

Git Bash で動きます。

## セットアップ

```bash
git clone -b admin git@github.com:cpslab/handson-2026-git.git handson-2026-admin
cd handson-2026-admin
# 名簿 (任意)。1 行に 1 人の学籍番号。あれば未 push の人も一覧に出る
vi students.txt
```

初回実行時に `.work/` へ作業用の clone が作られます。`.work/`、`students.txt`、`injected.tsv` は commit されません。

## 投影用ページ

```bash
./serve.sh              # http://localhost:8000 を開く
PORT=8080 ./serve.sh    # ポートを変える場合
```

5 秒ごとに自動で更新され、状態が変わったカードは光ります。

- 右上のボタンか `1` / `2` キーで「進捗」と「自己紹介」を切り替えます。`http://localhost:8000/#intro` を開くと最初から自己紹介を表示します
- 自己紹介は各ブランチの `学籍番号.md` の今の中身から、`名前:` と `一言:` を大きく表示し、ほかの `項目: 値` の行や自由な文もそのまま並べます
- `C` キーで各自のファイルの中身 (進捗の画面)、`F` キーで全画面表示を切り替えます
判定は `monitor.sh` と同じです。Python 3 が必要です（標準ライブラリのみ）。サーバーは自分の PC からしか開けません（127.0.0.1 で待ち受け）。

## 受講者に配るテンプレート

`main` の `template.md` をコピーして `学籍番号.md`（例: `24FI001.md`）を作ってもらいます。
ブランチ名・ファイル名・名簿の大文字小文字は区別しません（`24fi001` も `24FI001` として扱い、一覧では大文字で表示します）。

```markdown
# 24FI001

- 名前: 山田太郎
- 趣味: 自転車
- 好きなこと: カレーを食べること
- 一言: よろしくお願いします
```

## 当日の流れ

事前に運営は `./inject-conflict.sh -w 5` と `./serve.sh` を起動しておきます。

1. 受講者: 学籍番号のブランチを切り、`学籍番号.md` を add → commit → push する（最初の push は成功する）
2. 運営（自動）: `inject-conflict.sh -w` が push されたファイルを見つけ、一番下に運営の 1 行（`config.sh` の `INJECT_LINE`）を追記して push する
3. 受講者: **ファイルの一番下に** 1 行追加して（例: `- 最近のマイブーム: 〇〇`）add → commit → push → **reject される**
4. 受講者: `git pull --no-rebase` → コンフリクト → 解決して commit → push
5. 運営: 投影ページで全員が「解決」になったか確認する

手順 3 で一番下以外（途中の行の間など）に追加すると、運営の追記と場所が離れるのでコンフリクトせずに自動でマージされます。手順書では「一番下に」を強調してください。

手順 4 は、受講者の Git の設定によっては素の `git pull` が「divergent branches」で止まります。
手順書には `git pull --no-rebase` と書くか、最初に `git config --global pull.rebase false` を打ってもらってください。

## monitor.sh の STATUS

| STATUS | 意味 |
| --- | --- |
| `NO_BRANCH` | ブランチがまだない（名簿にいる人だけ表示） |
| `BRANCH_ONLY` | ブランチだけ push された（ファイルはまだ） |
| `NO_FILE` | 受講者の `学籍番号.md` がない。`template.md` を直接編集した、ファイル名を間違えたなど |
| `PUSHED` | `学籍番号.md` が push された。自動モードがすぐ仕込む |
| `INJECTED` | 運営が追記した。受講者の対応待ち |
| `RESOLVED` | 受講者がコンフリクトを解決して push した |
| `MERGED_CLEAN` | 運営の後に push されたが、コンフリクトせずにマージされた（一番下以外に追加した、`template.md` に追加したなど） |
| `MARKER_LEFT` | `<<<<<<<` などのマーカーが残ったまま push された |
| `FORCE_PUSHED` | 運営のコミットが履歴から消えている（`push -f` された） |

`MERGED_CLEAN` の判定には `git merge-tree --write-tree` を使うので、Git 2.38 以降が必要です。
一覧の下には、学籍番号の形式に合わないブランチ（打ち間違い）と、名簿にない学籍番号も表示されます。

## 設定

追記する文言や学籍番号の形式は `config.sh` で変えられます。別のリポジトリで試すときは `REPO_URL=/path/to/repo.git ./monitor.sh` のように実行します。

`inject-conflict.sh` は仕込み済みのブランチを飛ばすので、何度実行しても大丈夫です。自動モードを止めていた間に push した人がいたら、`./inject-conflict.sh` を一度実行してください。
