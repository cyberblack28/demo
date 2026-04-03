# Kubernetes Pattern デモ資料
Oracle Cloud Hangout Café Season 11 #3

---

## 概要

Kubernetes Patterns の以下のデモで使用するマニフェストおよび進行スクリプト一式です。

- **自動的配置（Automated Placement）**：5パターン
- **StatefulSet（Stateful Service）**：MySQL を使ったデモ

---

## ファイル構成

```
k8s-demo/
├── README.md                         # このファイル
├── kind-config.yaml                  # kind クラスタ定義
├── 00-setup-kind.sh                  # クラスタ作成スクリプト
├── DEMO-RUNBOOK.md                   # デモ当日の進行ガイド
├── scheduling/
│   ├── 01-nodeselector.yaml          # デモ1: nodeSelector
│   ├── 02-node-affinity.yaml         # デモ2: Node Affinity
│   ├── 03-pod-affinity.yaml          # デモ3: Pod Affinity / Anti-Affinity
│   ├── 04-topology-spread.yaml       # デモ4: Topology Spread Constraint
│   └── 05-taint-toleration.yaml      # デモ5: Taint / Toleration
└── statefulset/
    ├── 06-statefulset-mysql.yaml     # デモ6: StatefulSet（MySQL）
    └── MYSQL-DEMO-RUNBOOK.md         # StatefulSet デモ詳細手順
```

---

## クラスタ構成

| ノード名 | ゾーン | disktype | Taint |
|---|---|---|---|
| k8s-demo-control-plane | - | - | - |
| k8s-demo-worker | zone-a | ssd | なし |
| k8s-demo-worker2 | zone-b | hdd | なし |
| k8s-demo-worker3 | zone-c | ssd | デモ5直前に手動付与 |

> **注意**：Taint（`dedicated=high-performance:NoSchedule`）はクラスタ作成時には付与しません。
> デモ5の直前に DEMO-RUNBOOK.md の手順に従って手動で付与してください。

---

## 事前準備

### 前提条件

- `kind` がインストール済みであること
- `kubectl` がインストール済みであること
- Docker が起動していること

### クラスタ作成

```bash
bash 00-setup-kind.sh
```

クラスタ作成後、ノードとラベルを確認します。

```bash
kubectl get nodes --show-labels
```

---

## デモの流れ

| # | デモ内容 | マニフェスト | Taint状態 |
|---|---|---|---|
| 1 | nodeSelector | 01-nodeselector.yaml | なし |
| 2 | Node Affinity | 02-node-affinity.yaml | なし |
| 3 | Pod Affinity / Anti-Affinity | 03-pod-affinity.yaml | なし |
| 4 | Topology Spread Constraint | 04-topology-spread.yaml | なし |
| ↓ | **Taint 付与** | - | **付与** |
| 5 | Taint / Toleration | 05-taint-toleration.yaml | あり |
| ↓ | **Taint 解除** | - | **解除** |
| 6 | StatefulSet（MySQL） | 06-statefulset-mysql.yaml | なし |

詳細な進行手順は **DEMO-RUNBOOK.md** を参照してください。

---

## デモ別ポイント

### デモ1: nodeSelector
`disktype=ssd` のノード（worker / worker3）にのみ配置される。
worker2（hdd）には1つも配置されないことを確認する。

### デモ2: Node Affinity
`zone-a / zone-b` を必須条件、`disktype=ssd` を推奨条件として設定。
worker3（zone-c）には配置されず、workerとworker2に分散されることを確認する。

### デモ3: Pod Affinity / Anti-Affinity
cacheがいるノードにappを同居させ（Affinity）、app同士は別ノードに分散（Anti-Affinity）。
`replicas=3` にスケールアップすると3つ目がPendingになることを確認する。

### デモ4: Topology Spread Constraint
デモ3の「Pendingで詰まる問題」を解決するデモ。
`replicas=6→9→7` と変えて均等配置の挙動を確認する。

### デモ5: Taint / Toleration
worker3をTaint付きの専用ノードとして設定。
TolerationなしのPodはworker3に配置されず、Tolerationありは配置可能になることを確認する。

### デモ6: StatefulSet（MySQL）
固定Pod名・専用PVC・Headless Serviceによる安定ネットワーク・起動順序保証を確認する。
`kubectl delete pod mysql-1` 後に同じ名前・同じPVCで復活することが最大の見せ場。

---

## クリーンアップ

```bash
# クラスタごと削除
kind delete cluster --name k8s-demo
```
