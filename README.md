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

- `domain/`：兩位玩家、純資料規則、集中式 Zone／牌庫／供應列／隊伍／裝備／道具服務、FIFO 效果解析、資源 evaluator、命令、RNG、invariants；不得依賴 Node 或 Presentation。
- `content/`：基礎版 CardDefinition 與 Content Pack；不含自定義冒險者。
- `app/`：GameSession 與應用程式協調。
- `presentation/`：3D 桌面、HUD、動畫；只呈現已提交結果。
- `scenes/`：可執行場景。
- `tests/`：headless 規則與整合測試。

目前的 vertical slice 使用 placeholder 資產證明：官方起始配置 → 兩位玩家五階段輪替 → 招募區與商店各公開三張 → `BUY_CARD` 購買後進棄牌 → 休息補列／棄牌／洗牌／抽牌 → `PLAY_ADVENTURER` 滿編替換 → `EQUIP_ITEM` 與雙向附件 → `USE_ITEM` 抽牌 → 手牌購買力／隊伍戰力 evaluator → Legal Commands → transaction → events → 3D／2D 呈現 → Snapshot/hash。

目前刻意未納入的下一批規則是 `REFRESH_MARKET` 的多步選擇流程，以及完整官方卡池；`docs/` 是本機企劃資料，已由 `.gitignore` 排除。
