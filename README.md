# RollTag

本機 B-roll 倉庫：分析、打標、切段、搜尋與預覽。第一版是 macOS 原生 App。

產品規格（會跟著實作更新）：[SPEC.md](SPEC.md)

## 需求

- macOS 14+
- Xcode 16+
- Python 3（本機 sidecar，不做介面）

## 開啟

```bash
open RollTag.xcodeproj
```

或：

```bash
xcodebuild -scheme RollTag -destination 'platform=macOS' test
```

## 資料放哪

- 程式設定：`~/rolltag/config.json`（倉庫名單與 AI key，不含 tags）
- 每個倉庫：`<倉庫>/.rolltag/warehouse.sqlite` 與縮圖

倉庫離線時仍留在設定裡；硬碟插回後會重讀裡面的資料。刪倉庫只是取消登記，不刪片子。
