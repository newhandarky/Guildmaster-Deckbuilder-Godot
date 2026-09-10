# Guildmaster Deckbuilder — Godot 4.7.2

基礎版 Godot 3D／2D 重製專案。自定義冒險者目前不載入。

## 開發環境

- Godot 4.7.2 stable，GDScript，Forward+。
- macOS 與 Windows 桌面版。
- 參考解析度 1280×720，UI 使用 anchors 與 containers。
- 大型二進位資產使用 Git LFS。

## 執行

```bash
godot --path . --editor
godot --path .
```

## Headless smoke test

```bash
godot --headless --path . --script res://tests/headless/run_smoke.gd
```

## 架構邊界

- `domain/`：兩位玩家、純資料規則、集中式 Zone／牌庫／供應列／魔物循環／隊伍／裝備／道具／待選擇服務、target-aware 討伐、FIFO 效果解析、資源 evaluator、命令、RNG、invariants；不得依賴 Node 或 Presentation。
- `content/`：基礎版 CardDefinition 與 Content Pack；不含自定義冒險者。
- `app/`：GameSession 與應用程式協調。
- `presentation/`：3D 桌面、HUD、動畫；只呈現已提交結果。
- `scenes/`：可執行場景。
- `tests/`：headless 規則與整合測試。

目前的 vertical slice 使用 placeholder 資產證明：官方起始配置 → 兩位玩家五階段輪替 → `ATTACK_TARGET` 依最短隊伍前綴討伐 → 參戰者與裝備離場 → 骷髏可領取或略過 +4 購買力並回循環；兔妖／史萊姆抽牌後進勝者棄牌；自動機械弓兵／戰士使用共用、可序列化的 `pending_choice`，分別只允許從自己的手牌／棄牌堆移除 1 張至公開移除區或略過，且無候選時直接完成效果 → 魔物列補位 → 招募區與商店各公開三張 → `BUY_CARD` 購買後進棄牌 → `REFRESH_MARKET` 棄 1 張手牌並更換同列 1～3 張 → 休息補列／棄牌／洗牌／抽牌 → `PLAY_ADVENTURER`（含起始冒險者）滿編替換 → `EQUIP_ITEM` 與雙向附件 → `USE_ITEM` 抽牌 → Legal Commands → transaction → events → 3D／2D 呈現 → Snapshot/hash。

目前刻意未納入的是其餘 9 種官方魔物、Boss、其他特殊 target modifier 與完整官方卡池；`docs/` 是本機企劃資料，已由 `.gitignore` 排除。
