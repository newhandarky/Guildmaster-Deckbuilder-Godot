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

- `domain/`：兩位玩家、純資料規則、集中式 Zone／牌庫／供應列／魔物循環／Boss 與協助者供應、登場及輪替／隊伍／裝備／道具／待選擇服務、target-aware 討伐、FIFO 效果解析、資源與 Boss 規則 evaluator、命令、RNG、invariants；不得依賴 Node 或 Presentation。
- `content/`：基礎版 CardDefinition 與 Content Pack；不含自定義冒險者。
- `app/`：GameSession 與應用程式協調。
- `presentation/`：3D 桌面、HUD、動畫；只呈現已提交結果。
- `scenes/`：可執行場景。
- `tests/`：headless 規則與整合測試。

目前的 vertical slice 已完成 14 種基礎魔物：官方起始配置 → 兩位玩家五階段輪替 → `ATTACK_TARGET` 依最短隊伍前綴討伐 → 參戰者與裝備離場 → 骷髏循環、抽牌／重抽、多區域移除、公開列取得等資料驅動效果；寶箱怪使用可重播的 deterministic D6 資源獎勵；蛇妖從隱藏物資牌庫公開牌至正式輪抽區，並由擊敗者起依座位順序強制取得至各自手牌；所有延遲效果沿用可序列化 `pending_choice`、原子性命令、Legal Commands、事件與 Snapshot/hash。招募區與商店仍只在休息階段統一補列，自定義冒險者維持停用。

0.16.0 已完成 11 張基礎 Boss 的正式規則接線。共用流程涵蓋依玩家數建立本局 Boss 牌庫、公開登場與休息階段輪替、職業／公開區需求修正、參戰人數限制、裝備失效、參戰者替代離場、公開附件、公共牌庫直接取得、強制多張取得，以及巫妖「離場已提交但討伐失敗」例外。多步獎勵由可序列化 `pending_choice` 與 continuation 保持 Boss 在場，完成後才提交擊敗、所有權、統計與進程事件。

0.17.0 已補齊 30 種官方冒險者、每種 2 張，共 60 張正式招募供應；名稱、費用、戰力、榮譽、職業、份數、卡面文案與效果均來自企劃文件，自定義冒險者未混入。共用 operation 涵蓋隊伍進場、戰鬥開始／結束、條件與位置戰力、公開魔物指定／刷新、私有牌庫查看／移除／排序、卡牌移動、供應取得、骰子、裝備政策與冒險者作為裝備；多步流程沿用正式 Zone、`pending_choice`、Legal Commands、Snapshot 與 deterministic hash。招募區空位仍只在休息階段補滿。

0.18.0 已補齊 28 種官方物資（物資 01～03 各 3 張、其餘各 2 張，共 59 張）。共用效果支援棄牌成本與後續效果、棄牌堆回收、多區域移除、抽牌、全隊／全手牌棄置、依職業或印刷數值抽牌、跨玩家棄牌目的地替代、每回合一次、跳過討伐、公開魔物減益，以及裝備職業限制、target-aware 戰力、隊伍相鄰／其他隊員加成、戰鬥離場移除／抽牌與討伐時成本。道具維持在 `playArea` 到休息階段，商店空位也只在休息階段補滿；自定義物資未混入。

0.19.0 已加入 12 張官方協助者（各 1 張），每局按 Boss 數選取，僅公開 1 張。Boss 討伐後與通用輪替 operation 共用離場→容量收斂／離場效果→新卡登場／進場效果 transition；回合開始、購買開始、休息抽牌前與持續效果也由權威狀態觸發。情報商的跨玩家交牌與進／離場輪抽沿用正式 Zone、可序列化 pending choice、required actor、Legal Commands 及原子性 dispatch。自定義協助者未載入。

正式卡池逐卡對照見 [`content/packs/OFFICIAL_ADVENTURERS.md`](content/packs/OFFICIAL_ADVENTURERS.md)、[`content/packs/OFFICIAL_RESOURCES.md`](content/packs/OFFICIAL_RESOURCES.md) 與 [`content/packs/OFFICIAL_HELPERS.md`](content/packs/OFFICIAL_HELPERS.md)。

HUD 會顯示官方卡牌與目前協助者的完整效果，並在待選擇狀態顯示來源、候選、進度與 required actor；強制選擇期間維持鍵盤／手把焦點封閉。完整 final-round policy 留待後續規則模組。`docs/` 是本機企劃資料，已由 `.gitignore` 排除，自定義卡片維持停用。
