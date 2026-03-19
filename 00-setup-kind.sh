#!/bin/bash
# =============================================================
# 事前セットアップ：kind クラスタ作成 + Taint付与
# zone / disktype ラベルは kind-config.yaml で付与済み
# ここでは Taint（専用ノード）のみ追加する
# =============================================================

# ---- kind クラスタ作成 ----
echo "=== kind クラスタ作成 ==="
kind create cluster --config kind-config.yaml --name k8s-demo
kubectl cluster-info --context kind-k8s-demo

# ---- ノード確認 ----
echo ""
echo "=== ノード一覧 ==="
kubectl get nodes --show-labels

# ---- worker ノード名を取得 ----
NODE1=$(kubectl get nodes --selector='topology.kubernetes.io/zone=zone-a' -o jsonpath='{.items[0].metadata.name}')
NODE2=$(kubectl get nodes --selector='topology.kubernetes.io/zone=zone-b' -o jsonpath='{.items[0].metadata.name}')
NODE3=$(kubectl get nodes --selector='topology.kubernetes.io/zone=zone-c' -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "NODE1 (zone-a/ssd): $NODE1"
echo "NODE2 (zone-b/hdd): $NODE2"
echo "NODE3 (zone-c/ssd): $NODE3"

# ---- Taint/Toleration デモ用: NODE3 を専用ノード化 ----
kubectl label node $NODE3 dedicated=high-performance --overwrite
kubectl taint nodes $NODE3 dedicated=high-performance:NoSchedule

echo ""
echo "=== セットアップ完了 ==="
kubectl get nodes --show-labels

echo ""
echo "=== クリーンアップ時 ==="
echo "kind delete cluster --name k8s-demo"
