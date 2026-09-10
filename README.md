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

0.15.0 已建立 Boss 共用框架：11 張正式 Boss 資料與單一實例、依玩家數選出本局牌庫、保留區、公開登場區、休息階段揭示、共用討伐／獎勵／取得／統計事件，以及可序列化且可重播的 zone 與規則 modifier。HUD 會公開 Boss 數值、規則、獎勵、討伐預覽與剩餘數量；「史萊姆娘」作為第一張完整閉環的正式 Boss，可驗證職業修正、擊敗獎勵及下一 Boss 轉換。

其餘 10 張 Boss 的正式資料已納入，但需要單卡規則的 departure、attachment、多人／多張取得與失敗後不回滾等通用 operation 尚未啟用；在完成對應共用 operation 前不會產生可攻擊命令。協助者輪替與 final-round policy 也留待後續 Boss 規則批次。其他特殊 target modifier 與完整官方卡池仍未納入；`docs/` 是本機企劃資料，已由 `.gitignore` 排除。
