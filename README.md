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

- `domain/`：純資料規則、命令、RNG、invariants；不得依賴 Node 或 Presentation。
- `content/`：基礎版 CardDefinition 與 Content Pack；不含自定義冒險者。
- `app/`：GameSession 與應用程式協調。
- `presentation/`：3D 桌面、HUD、動畫；只呈現已提交結果。
- `scenes/`：可執行場景。
- `tests/`：headless 規則與整合測試。

第一個 vertical slice 使用 placeholder 資產證明：內容載入 → Legal Commands → transaction → events → 3D／2D 呈現 → Snapshot/hash。
