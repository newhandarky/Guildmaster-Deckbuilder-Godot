# 官方冒險者 Content Pack 對照（0.17.0）

來源：`docs/card-data/卡片01-冒險者.md`、`docs/3D專案企劃/03-冒險者與起始角色規格.md`、`docs/3D專案企劃/07-卡牌效果與觸發時機.md` 與已確認 rulings。數值欄依序為費用／戰力／榮譽；每種皆為 2 張。自定義冒險者不在本表及 Content Pack。

| # | 名稱 | 職業 | 數值 | 共用 operation |
|---:|---|---|---|---|
| 01 | 麥娜 | 輔助 | 4／2／2 | `choose_move_card` |
| 02 | 托妮卡 | 近戰 | 3／3／2 | `equipment_policy` |
| 03 | 卡儂 | 法師 | 4／3／1 | `roll_self_combat` |
| 04 | 修爾蒂 | 坦克 | 4／2／2 | `party_combat_aura` |
| 05 | 哈貝妮 | 輔助 | 3／1／1 | `purchase_cost_modifier` |
| 06 | 莉茲米 | 近戰 | 4／2／2 | `gain_from_supply_deck` |
| 07 | 辛芙妮 | 遠程 | 3／2／1 | `choose_refresh_row` |
| 08 | 旋律 | 近戰 | 3／2／1 | `choose_target_combat_modifier` |
| 09 | 芙尼姆 | 坦克 | 3／2／1 | `conditional_combat` |
| 10 | 慕莎 | 近戰 | 4／2／2 | `conditional_combat` |
| 11 | 布蕾斯 | 法師 | 4／1／1 | `inspect_deck_top` |
| 12 | 安比夏 | 坦克 | 3／2／2 | `reposition_source` |
| 13 | 芭米爾 | 輔助 | 4／1／1 | `choose_remove_card` |
| 14 | 席夢娜 | 近戰 | 4／0／1 | `party_combat_aura`、`position_departure` |
| 15 | 阿爾可 | 遠程 | 3／2／2 | `conditional_combat` |
| 16 | 神樂 | 坦克 | 4／3／2 | `reveal_top_if_type` |
| 17 | 蕾普莉絲 | 輔助 | 3／1／1 | `draw_then_choose_discard` |
| 18 | 羅絲瑪莉 | 近戰 | 4／2／2 | `grant_purchase_power` |
| 19 | 賽席莉亞 | 法師 | 4／2／2 | `equipment_policy`、`combat_departure_replacement` |
| 20 | 費歐娜 | 法師 | 3／5／1 | `conditional_combat` |
| 21 | 阿爾梅斯 | 近戰 | 4／2／2 | `combat_departure_replacement` |
| 22 | 露希艾拉 | 坦克 | 3／1／1 | `equipment_policy`、`attached_value_combat` |
| 23 | 拉菲娜 | 法師 | 3／1／1 | `roll_target_combat_modifier` |
| 24 | 索娜莉亞 | 近戰 | 4／1／1 | `conditional_combat` |
| 25 | 米莉安 | 坦克 | 4／2／2 | `self_as_equipment` |
| 26 | 莉莉西斯 | 遠程 | 4／3／2 | `hand_purchase_power_modifier` |
| 27 | 娜塔莉絲 | 輔助 | 3／1／1 | `party_combat_aura` |
| 28 | 塔菲娜 | 輔助 | 3／1／1 | `draw`（進場／配裝觸發） |
| 29 | 莉迪亞 | 法師 | 4／1／1 | `equipment_policy`、通用裝備替換選擇 |
| 30 | 尤伊爾 | 輔助 | 5／0／3 | `choose_remove_card` |

統計：30 種定義、60 個 instance；招募區 3 張，隱藏招募牌庫 57 張。相同 seed 的初始順序固定，公開列空位僅於休息階段補滿。
