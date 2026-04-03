# ============================================================
# デモ進行ガイド：Kubernetes Pattern
# 自動的配置（5パターン）& StatefulSet（MySQL）
# ============================================================
# クラスタ構成（kind-config.yaml）:
#   k8s-demo-control-plane : control-plane（Pod は配置されない）
#   k8s-demo-worker        : zone-a / disktype=ssd
#   k8s-demo-worker2       : zone-b / disktype=hdd
#   k8s-demo-worker3       : zone-c / disktype=ssd（Taintなし）
#
# 事前準備: bash 00-setup-kind.sh を実行済みであること
# ※ Taint はデモ5の直前に手動で付与する
# ============================================================


## ─────────────────────────────────────────
## 発表前の動作確認
## ─────────────────────────────────────────

# ノード構成を確認（ラベルが正しいこと）
kubectl get nodes --show-labels

# worker3 に Taint がないことを確認（デモ1〜4はTaintなしで実施）
kubectl describe node k8s-demo-worker3 | grep -A3 "Taints:"
#   → Taints: <none>

# 前回の残骸がないことを確認
kubectl get pods,deployments,statefulset,pvc


## ─────────────────────────────────────────
## デモ1: nodeSelector（単純）
## 「disktype=ssd のノードだけ使う」
## ─────────────────────────────────────────

kubectl apply -f scheduling/01-nodeselector.yaml
kubectl get pods -o wide

# ポイント:
#   → worker(zone-a/ssd) と worker3(zone-c/ssd) にだけ配置される
#   → worker2(hdd) には1つも配置されない
#   → シンプルだが「In / NotIn」のような条件式は書けない → Node Affinity へ

kubectl delete -f scheduling/01-nodeselector.yaml


## ─────────────────────────────────────────
## デモ2: Node Affinity（条件指定）
## 「zone-a/b に限定、かつ ssd ノードを優先」
## ─────────────────────────────────────────

kubectl apply -f scheduling/02-node-affinity.yaml
kubectl get pods -o wide

# ポイント:
#   → worker3(zone-c) には1つも配置されない（required 条件で除外）
#   → worker(zone-a/ssd) と worker2(zone-b/hdd) に配置される
#   → worker に多めに配置される傾向がある（preferred weight=20）
#   → nodeSelector より柔軟な「必須 / 推奨」の2段階で制御できる

kubectl delete -f scheduling/02-node-affinity.yaml


## ─────────────────────────────────────────
## デモ3: Pod Affinity / Anti-Affinity
## 「cache の近くに app を置き、app 同士は分散」
## ─────────────────────────────────────────

kubectl apply -f scheduling/03-pod-affinity.yaml
kubectl get pods -o wide

# ポイント:
#   → cache は worker / worker2 に1つずつ（Anti-Affinity で分散）
#   → app は cache がいる worker / worker2 に同居（Pod Affinity）
#   → app 同士は同じノードにいない（Pod Anti-Affinity）
#   ※ worker3 には cache がいないため app の Affinity 条件を満たせない

# replicas を増やして Pending を体感
kubectl scale deployment demo-pod-affinity --replicas=3
kubectl get pods -o wide
#   → 3つ目の app は置ける場所がなく Pending になる
#   → これを解決するのが Topology Spread（次のデモへ）

kubectl delete -f scheduling/03-pod-affinity.yaml


## ─────────────────────────────────────────
## デモ4: Topology Spread（均等配置）
## 「Anti-Affinity の詰まり問題を解決」
## ─────────────────────────────────────────

kubectl apply -f scheduling/04-topology-spread.yaml
kubectl get pods -o wide
#   → 6 Pod が 3ノードに各2つずつ均等配置

# replicas を変えて挙動の違いを見せる
kubectl scale deployment demo-topology-spread --replicas=9
kubectl get pods -o wide
#   → 各ノード3つずつ均等配置

kubectl scale deployment demo-topology-spread --replicas=7
kubectl get pods -o wide
#   → 1ノードだけ3つ、残り2つ（maxSkew=1 の範囲内で許容）
#   → Anti-Affinity と違い、ノード数を超えても Pending にならない

kubectl delete -f scheduling/04-topology-spread.yaml


## ─────────────────────────────────────────
## デモ5の直前: Taint を付与（専用ノード化）
## ─────────────────────────────────────────

kubectl label node k8s-demo-worker3 dedicated=high-performance --overwrite
kubectl taint nodes k8s-demo-worker3 dedicated=high-performance:NoSchedule

# 付与されたことを確認
kubectl describe node k8s-demo-worker3 | grep -A3 "Taints:"
#   → Taints: dedicated=high-performance:NoSchedule


## ─────────────────────────────────────────
## デモ5: Taint / Toleration（専用ノード）
## 「worker3 は許可証を持つ Pod だけ入れる」
## ─────────────────────────────────────────

kubectl apply -f scheduling/05-taint-toleration.yaml
kubectl get pods -o wide

# ポイント（2つの Deployment を比較）:
#   → demo-no-toleration  : worker / worker2 のみ（worker3 は Taint で弾かれる）
#   → demo-with-toleration: worker3 にも配置可能（Toleration が許可証）
#   → Toleration は「乗れる許可証」であり「必ず worker3 に行く」ではない
#   → worker3 に集中させたい場合は nodeSelector / Node Affinity を組み合わせる

kubectl delete -f scheduling/05-taint-toleration.yaml


## ─────────────────────────────────────────
## デモ5 → デモ6 の間: Taint を解除
## worker3 を StatefulSet の配置先として開放する
## ─────────────────────────────────────────

kubectl taint nodes k8s-demo-worker3 dedicated=high-performance:NoSchedule-

# 解除されたことを確認（Taints: <none> になること）
kubectl describe node k8s-demo-worker3 | grep -A3 "Taints:"


## ─────────────────────────────────────────
## デモ6: StatefulSet（MySQL）
## ─────────────────────────────────────────

kubectl apply -f statefulset/06-statefulset-mysql.yaml


## Step 1: デプロイ → 順番起動を確認
## ポイント:「Deploymentと違い、0→1→2の順で起動する」

kubectl get pods -w
# 出力イメージ:
#   mysql-0   0/1   Init:0/1   → Running
#   mysql-1   0/1   Init:0/1   → Running  ← 0が Ready になってから起動
#   mysql-2   0/1   Init:0/1   → Running  ← 1が Ready になってから起動
# Ctrl+C で抜ける

# 説明ポイント:
#   Deployment/ReplicaSet は並列起動
#   StatefulSet は前の Pod が Ready になってから次を起動
#   → DB クラスタの初期化順序を保証するために必須


## Step 2: Pod名・PVC・DNS の固定を確認
## ポイント:「各 Pod が固有の ID・ストレージ・名前を持つ」

# Pod名が固定（mysql-0, mysql-1, mysql-2）
kubectl get pods -o wide

# 各 Pod に PVC が 1対1 で割り当てられていることを確認
kubectl get pvc
# 出力イメージ:
#   data-mysql-0   Bound   ...   1Gi
#   data-mysql-1   Bound   ...   1Gi
#   data-mysql-2   Bound   ...   1Gi

# Init コンテナが Primary と Replica を自動判別していることを確認
kubectl logs mysql-0 -c init-mysql   # → Role: Primary (server-id=100)
kubectl logs mysql-1 -c init-mysql   # → Role: Replica (server-id=101)
kubectl logs mysql-2 -c init-mysql   # → Role: Replica (server-id=102)


## Step 3: MySQL にデータを書き込む
## ポイント:「PVC にデータが永続化される」

kubectl exec -it mysql-0 -- mysql -u root -p"Demo1234!" demodb -e "
  CREATE TABLE IF NOT EXISTS demo (id INT AUTO_INCREMENT PRIMARY KEY, value VARCHAR(100));
  INSERT INTO demo (value) VALUES ('hello from StatefulSet');
  SELECT * FROM demo;
"

# 固定 DNS で mysql-0 に直接アクセス（別 Pod から）
kubectl run mysql-client --image=mysql:8.0 --rm -it --restart=Never -- \
  mysql -h mysql-0.mysql-svc.default.svc.cluster.local \
        -u root -p"Demo1234!" demodb -e "SELECT * FROM demo;"
#   → mysql-0 の固定 DNS で確実にアクセスできることを確認


## Step 4: Pod 削除 → 同じ名前・同じ PVC で復活（最大の見せ場）
## ポイント:「Deployment と決定的に違う点」

kubectl delete pod mysql-1
kubectl get pods -w
#   → mysql-1 として再起動（ランダム名にならない）

kubectl get pvc
#   → data-mysql-1 は削除されずに再バインドされる

# 説明ポイント:
#   Deployment なら再作成 Pod はランダムな ID になり
#   別の PVC にバインドされてデータが消える
#   StatefulSet なら mysql-1 は必ず mysql-1 に戻り
#   data-mysql-1 のデータを引き継ぐ


## Step 5: スケールダウン → 逆順停止を確認
## ポイント:「DB クラスタの整合性を保つための順序保証」

kubectl scale statefulset mysql --replicas=1
kubectl get pods -w
#   → mysql-2 → mysql-1 の順で削除される（逆順）

kubectl get pvc
#   → data-mysql-1, data-mysql-2 の PVC は残る
#   → スケールインしてもデータは保持される


## クリーンアップ
kubectl delete -f statefulset/06-statefulset-mysql.yaml
kubectl delete pvc -l app=mysql   # PVC は手動削除が必要（データ保護のため自動削除されない）


## ─────────────────────────────────────────
## 全クリーンアップ
## ─────────────────────────────────────────
# kind delete cluster --name k8s-demo
