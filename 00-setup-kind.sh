#!/bin/bash
# =============================================================
# 事前セットアップ：kind クラスタ作成
# zone / disktype ラベルは kind-config.yaml で付与済み
# Taint はデモ5の直前に手動で付与する
# =============================================================

echo "=== kind クラスタ作成 ==="
kind create cluster --config kind-config.yaml --name k8s-demo
kubectl cluster-info --context kind-k8s-demo

echo ""
echo "=== ノード一覧 ==="
kubectl get nodes --show-labels

echo ""
echo "=== セットアップ完了 ==="
echo "Taint はデモ5の直前に以下のコマンドで付与してください："
echo "kubectl taint nodes k8s-demo-worker3 dedicated=high-performance:NoSchedule"

echo ""
echo "=== クリーンアップ時 ==="
echo "kind delete cluster --name k8s-demo"
