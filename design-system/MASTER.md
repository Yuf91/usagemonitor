# AIUsageBar — macOS 設計規範
依據：專案的 ui-ux-pro-max skill；已執行兩次 design-system 搜尋與 swiftui accessibility/state 查詢。
搜尋回傳的 Hero/CTA 網頁布局不適用選單列，因此不採用；以下為平台適配後的一般設計規範，非資料庫確認的專用選單列模板。

- 原生 macOS 選單列 + SwiftUI 面板，寬 390pt；垂直內容，最大高度依螢幕限制。
- 系統字體與 SF Symbols，數值 monospacedDigit。標題 22pt、服務名 16pt、內文 13pt、附註 12pt。
- 8/12/16/20pt 間距，卡片圓角 16pt，系統背景／文字語意色彩。Claude 用橘色、Codex 用藍色做裝飾與進度，不作唯一狀態指示；剩餘 ≤20%／10% 時進度條改橘／紅並加文字。
- 面板：標題 → Claude 卡片（本次、本週、credits 區塊）→ Codex 卡片 → 更新時間與操作。
- credits 與百分比額度分開：雲端 credits 顯示剩餘／總額與到期時間；Usage credits 顯示狀態、本月已用與上限，不推算成儲值餘額。
- 顯示「剩餘」而非混用已用百分比；重置時間副標。額度未知顯示 —，不補零。
- 卡片內有讀取狀態、資料時間、重試或登入入口；設定獨立視窗，使用漸進揭露。
- 無輪播、無裝飾性動畫。更新維持卡片位置；鍵盤焦點、VoiceOver、深淺模式分別檢查。
- 不用手機底部導航、網頁字體或觸控尺寸規範取代 macOS 慣例。

## 玻璃風格（Glassmorphism）
- 面板背景：`NSVisualEffectView`（behind-window，`.hudWindow`）＋橘／藍／紫柔和放射漸層光暈，讓毛玻璃有顏色可透。
- 卡片：`.thinMaterial` 半透明＋頂部白色高光漸層＋1pt 漸層亮邊（左上亮、右下暗）＋柔和陰影；卡片圓角 20pt。
- 內層區塊（credits、狀態標籤、底部操作列）：`.ultraThinMaterial`／`.thinMaterial`，不加陰影以保持層級。
- 更新按鈕為 32pt 圓形玻璃按鈕；進度條加輕微同色光暈。
- Liquid Glass：macOS 26 以上執行時，Claude／Codex 卡片與設定區塊改用系統 `NSGlassEffectView`（regular），底部操作列與更新按鈕用 clear 樣式；因本機 SDK 為 15.5，以執行期 `NSClassFromString` 取得。卡片內的標籤與 credits 區塊不疊加玻璃（避免玻璃疊玻璃）。舊系統自動回到上述毛玻璃樣式。
- 系統「降低透明度」開啟時，自動改回不透明系統背景色，確保文字對比。
- 實作集中在 `Views.swift` 的 `GlassBackdrop`、`Glass`（`.glass()`）、`GlassButtonStyle`、`GlassSection`。

目前範圍：Claude 與 Codex 兩張卡片；不加入其他服務。
