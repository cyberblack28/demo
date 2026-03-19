# ============================================================
# デモ進行ガイド：Kubernetes Pattern
# 自動的配置（5パターン）& StatefulSet（MySQL）
# ============================================================
# クラスタ構成（kind-config.yaml）:
#   k8s-demo-control-plane : control-plane（Pod は配置されない）
#   k8s-demo-worker        : zone-a / disktype=ssd
#   k8s-demo-worker2       : zone-b / disktype=hdd
#   k8s-demo-worker3       : zone-c / disktype=ssd / Taint: dedicated=high-performance:NoSchedule
#
# 事前準備: bash 00-setup-kind.sh を実行済みであること
# ============================================================


## ─────────────────────────────────────────
## 発表前の動作確認
## ─────────────────────────────────────────

# ノード構成を確認（ラベル・Taintが正しいこと）
kubectl get nodes --show-labels
kubectl describe node k8s-demo-worker3 | grep -A3 "Taints:"

# 前回の残骸がないことを確認
kubectl get pods,deployments,statefulset,pvc


## ─────────────────────────────────────────
## デモ1: nodeSelector（単純）
## 「disktype=ssd のノードだけ使う」
## ─────────────────────────────────────────

kubectl apply -f scheduling/01-nodeselector.yaml
kubectl get pods -o wide

# ポイント:
#   → worker(ssd) と worker3(ssd) にだけ配置される
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
#   → worker(zone-a/ssd) に多めに配置される（preferred weight=80）
#   → worker2(zone-b/hdd) にも配置されるが少なめ
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

# replicas を増やして Pending を体感
kubectl scale deployment demo-pod-affinity --replicas=3
kubectl get pods -o wide
#   → 3つ目の app は置ける場所がなく Pending になる
#   （cache がいない worker3 には Affinity が満たせず配置不可）
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
## デモ5の前に Taint を付与（専用ノード化）
## ─────────────────────────────────────────

NODE3=$(kubectl get nodes --selector='topology.kubernetes.io/zone=zone-c' \
  -o jsonpath='{.items[0].metadata.name}')

kubectl label node $NODE3 dedicated=high-performance --overwrite
kubectl taint nodes $NODE3 dedicated=high-performance:NoSchedule

# 確認
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
## デモ6: StatefulSet（MySQL）
## 詳細は statefulset/MYSQL-DEMO-RUNBOOK.md を参照
## ─────────────────────────────────────────

kubectl apply -f statefulset/06-statefulset-mysql.yaml

# 1. 順番起動を確認（0 → 1 → 2）
kubectl get pods -w
# Ctrl+C

# 2. Pod名・PVC の固定を確認
kubectl get pods -o wide
kubectl get pvc

# 3. Init コンテナで Primary / Replica が自動判別されていることを確認
kubectl logs mysql-0 -c init-mysql   # → Role: Primary (server-id=100)
kubectl logs mysql-1 -c init-mysql   # → Role: Replica (server-id=101)

# 4. データ書き込み
kubectl exec -it mysql-0 -- mysql -u root -p"Demo1234!" demodb -e "
  CREATE TABLE IF NOT EXISTS demo (id INT AUTO_INCREMENT PRIMARY KEY, value VARCHAR(100));
  INSERT INTO demo (value) VALUES ('hello from StatefulSet');
  SELECT * FROM demo;
"

# 5. 固定 DNS でアクセス
kubectl run mysql-client --image=mysql:8.0 --rm -it --restart=Never -- \
  mysql -h mysql-0.mysql-svc.default.svc.cluster.local \
        -u root -p"Demo1234!" demodb -e "SELECT * FROM demo;"

# 6. Pod削除 → 同じ名前・同じ PVC で復活（最大の見せ場）
kubectl delete pod mysql-1
kubectl get pods -w
kubectl get pvc
#   → mysql-1 として再起動、data-mysql-1 は残ったまま再バインド

# 7. スケールダウン（逆順停止）
kubectl scale statefulset mysql --replicas=1
kubectl get pods -w
#   → mysql-2 → mysql-1 の順で削除

# クリーンアップ
kubectl delete -f statefulset/06-statefulset-mysql.yaml
kubectl delete pvc -l app=mysql


## ─────────────────────────────────────────
## 全クリーンアップ
## ─────────────────────────────────────────
# kind delete cluster --name k8s-demo
