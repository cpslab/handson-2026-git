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

5 秒ごとに自動で更新され、状態が変わったカードは光ります。`C` キーで各自のファイルの中身、`F` キーで全画面表示を切り替えます。
判定は `monitor.sh` と同じです。Python 3 が必要です（標準ライブラリのみ）。サーバーは自分の PC からしか開けません（127.0.0.1 で待ち受け）。

## 受講者に配るテンプレート

ファイル名は `学籍番号.md`（例: `24FI001.md`）。「ひとこと:」の行がコンフリクト演習で使われます。

```markdown
# 24FI001
名前: 山田太郎
ひとこと: よろしくお願いします
```

## 当日の流れ

1. 受講者: 学籍番号のブランチを切り、`学籍番号.md` を add / commit / push する
2. 運営: `./serve.sh` のページを投影して全員の push を確認する（ターミナルなら `./monitor.sh -w 10`）
3. 運営: `./inject-conflict.sh -n` で対象を確認し、`./inject-conflict.sh` で仕込む
4. 受講者: **pull はせずに** 「ひとこと」を書き換えて commit → push する
5. 受講者: push が reject される → `git pull --no-rebase` → コンフリクト → 解決して commit → push
6. 運営: `./monitor.sh` で `RESOLVED` になったか確認する

手順 5 は、受講者の Git の設定によっては素の `git pull` が「divergent branches」で止まります。
手順書には `git pull --no-rebase` と書くか、最初に `git config --global pull.rebase false` を打ってもらってください。

## monitor.sh の STATUS

| STATUS | 意味 |
| --- | --- |
| `NO_BRANCH` | ブランチがまだない（名簿にいる人だけ表示） |
| `NO_FILE` | ブランチはあるが `学籍番号.md` がない。ファイル名の大文字小文字違いなど |
| `PUSHED` | push 済み。仕込み前の状態 |
| `INJECTED` | 運営が書き換えた。受講者の対応待ち |
| `RESOLVED` | 運営コミットの後に受講者が push した |
| `MARKER_LEFT` | `<<<<<<<` などのマーカーが残ったまま push された |
| `FORCE_PUSHED` | 運営のコミットが履歴から消えている（`push -f` された） |

一覧の下には、学籍番号の形式に合わないブランチ（打ち間違い）と、名簿にない学籍番号も表示されます。

## 設定

文言や学籍番号の形式は `config.sh` で変えられます。別のリポジトリで試すときは `REPO_URL=/path/to/repo.git ./monitor.sh` のように実行します。

`inject-conflict.sh` は書き換え済みのブランチを飛ばすので、何度実行しても大丈夫です。push が間に合わず遅れて push した人がいたら、もう一度実行してください。
