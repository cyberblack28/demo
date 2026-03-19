# Kubernetes デモ環境セットアップ

## ファイル構成

```
k8s-demo/
├── README.md
├── kind-config.yaml          ← クラスタ定義（ラベル付き）
├── 00-setup-kind.sh          ← クラスタ作成 + Taint付与スクリプト
├── DEMO-RUNBOOK.md           ← デモ進行ガイド
├── scheduling/
│   ├── 01-nodeselector.yaml
│   ├── 02-node-affinity.yaml
│   ├── 03-pod-affinity.yaml
│   ├── 04-topology-spread.yaml
│   └── 05-taint-toleration.yaml
└── statefulset/
    └── 06-statefulset-mysql.yaml
```

## 事前準備

- Docker がインストールされていること
- kind がインストールされていること
- kubectl がインストールされていること

```bash
# kind のインストール（未インストールの場合）
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# kubectl のインストール（未インストールの場合）
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

## セットアップ手順

```bash
# 1. セットアップスクリプトを実行（クラスタ作成 + Taint付与）
chmod +x 00-setup-kind.sh
bash 00-setup-kind.sh

# 2. ノード構成を確認
kubectl get nodes --show-labels
kubectl describe node k8s-demo-worker3 | grep -A3 "Taints:"
```

### 期待される構成

| ノード名 | Zone | disktype | Taint |
|---|---|---|---|
| k8s-demo-worker | zone-a | ssd | なし |
| k8s-demo-worker2 | zone-b | hdd | なし |
| k8s-demo-worker3 | zone-c | ssd | dedicated=high-performance:NoSchedule |

## デモ実行

DEMO-RUNBOOK.md を参照してください。

## クリーンアップ

```bash
kind delete cluster --name k8s-demo
```
