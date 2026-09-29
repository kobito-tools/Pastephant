#!/bin/zsh
cd "${0:A:h}"
./build.sh
status=$?
if [[ $status -eq 0 ]]; then
  echo ""
  echo "Pastephant.appを作成しました。アプリケーションフォルダへ移動して起動すると、メニューバーに常駐します。"
  echo "⌥⌘V で履歴を開けます。貼り付けには「アクセシビリティ」の許可が必要です（初めて貼るときに案内が出ます）。"
fi
echo ""
read "reply?Enterキーで閉じます..."
exit $status
