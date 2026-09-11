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

- `domain/`：兩位玩家、純資料規則、集中式 Zone／牌庫／供應列／魔物循環／Boss 供應與登場／隊伍／裝備／道具／待選擇服務、target-aware 討伐、FIFO 效果解析、資源與 Boss 規則 evaluator、命令、RNG、invariants；不得依賴 Node 或 Presentation。
- `content/`：基礎版 CardDefinition 與 Content Pack；不含自定義冒險者。
- `app/`：GameSession 與應用程式協調。
- `presentation/`：3D 桌面、HUD、動畫；只呈現已提交結果。
- `scenes/`：可執行場景。
- `tests/`：headless 規則與整合測試。

目前的 vertical slice 已完成 14 種基礎魔物：官方起始配置 → 兩位玩家五階段輪替 → `ATTACK_TARGET` 依最短隊伍前綴討伐 → 參戰者與裝備離場 → 骷髏循環、抽牌／重抽、多區域移除、公開列取得等資料驅動效果；寶箱怪使用可重播的 deterministic D6 資源獎勵；蛇妖從隱藏物資牌庫公開牌至正式輪抽區，並由擊敗者起依座位順序強制取得至各自手牌；所有延遲效果沿用可序列化 `pending_choice`、原子性命令、Legal Commands、事件與 Snapshot/hash。招募區與商店仍只在休息階段統一補列，自定義冒險者維持停用。

0.16.0 已完成 11 張基礎 Boss 的正式規則接線。共用流程涵蓋依玩家數建立本局 Boss 牌庫、公開登場與休息階段輪替、職業／公開區需求修正、參戰人數限制、裝備失效、參戰者替代離場、公開附件、公共牌庫直接取得、強制多張取得，以及巫妖「離場已提交但討伐失敗」例外。多步獎勵由可序列化 `pending_choice` 與 continuation 保持 Boss 在場，完成後才提交擊敗、所有權、統計與進程事件。

HUD 會公開 Boss 數值、規則、附件、獎勵、目前 required actor 與多選進度，強制選擇期間維持鍵盤／手把焦點封閉。協助者輪替與完整 final-round policy 留待後續規則模組；其他特殊 target modifier 與完整官方卡池仍未納入。`docs/` 是本機企劃資料，已由 `.gitignore` 排除，自定義冒險者維持停用。
