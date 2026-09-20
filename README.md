# RollTag

A local B-roll warehouse. Analyze, tag, search, preview, and trim footage on your own disks. Version 1 is a native macOS app.

Product contract (Traditional Chinese, kept in sync with the app): [SPEC.md](SPEC.md)

The app UI is Traditional Chinese first, with full English localization. It follows the Mac language: English macOS → English UI; 繁中 macOS → 繁中 UI.

## The problem

Travel, events, and daily shoots land on external drives as a mix of DJI clips, iPhone stills, backups, and accidental copies. Finder only searches filenames. Finding “golden-hour handheld in Johor” means scrubbing file by file. If tags live only on one Mac, they vanish when you swap disks.

RollTag registers warehouses on this Mac and **writes metadata inside each disk’s `.rolltag/` folder**, so tags travel with the footage. Scans read duration and file headers; they do not decode an entire 4K library. Thumbnails are built when a cell appears. Tagging is for search later — not a timeline editor, and not an automatic cloud upload.

This version does not: DaVinci integration, a NAS assumption, Linux/Windows, or AI tagging on import.

## How to use it

### Open

Needs macOS 14+, Xcode 16+, and local Python 3 (sidecar, no UI).

```bash
open RollTag.xcodeproj
```

Run the RollTag scheme in Xcode. Tests:

```bash
xcodebuild -scheme RollTag -destination 'platform=macOS' test
```

### Add a warehouse

Drop the footage folder or drive root onto the window, or use ⌘O / Settings. Removing a warehouse only unregisters it; files on disk stay.

Unplugging a drive marks it offline (search hides its clips). Plug it back in and RollTag rereads `.rolltag/`. Large scans run in the background; the sidebar shows phase, filename, and percent. Rescan with ⌘R.

Supported: video (`mov` / `mp4` / `m4v` / `avi` / `mkv` / `mxf`), photos (including HEIC), audio (`mp3` / `m4a` and similar).

### Find and preview

The left sidebar has smart lists (All, Tagged, Untagged, Missing, Duplicates) and categories you have used. Search and sort sit above the grid. Only online warehouses are searched.

Select a clip: player on the left (video/audio scrub; photos show a still), inspector on the right (path, capture time, GPS if present, tags). Hover a grid cell to preview video/audio. Space plays/pauses; P or Esc toggles fullscreen. ⌘/ lists every shortcut.

### Tag

The inspector accepts preset facets (theme, mood, place, shot, …) or custom words (`clubmed`, a person’s name). Single clip and batch use the same controls. Click a chip to remove it. Search uses these tags.

For AI tagging, add a Gemini or OpenAI API key in Settings (⌘,). After you select a **video or photo**, the inspector and Tag menu show the action (⌥⌘T). Import never runs AI by itself. Audio, tiny files, and unreadable files are skipped. When the model succeeds, RollTag also applies this warehouse’s existing place/custom tags that match folder names.

### Duplicates and trim

Sidebar Duplicates or ⌘⇧D: compare side by side. A keeps the leftmost, D the rightmost, S keeps all; Enter confirms sending the others to Trash.

With a single video selected, **Trim** opens a separate window and writes a new file in the warehouse that you can tag on its own.

## Where data lives

- App settings: `~/rolltag/config.json` (warehouse list and AI keys, not tags). Do not share that file or commit it to a public git repo.
- Per warehouse: `<warehouse>/.rolltag/warehouse.sqlite`, thumbnails, and trim exports. They stay on the disk.

---

# 繁中

本機 B-roll 倉庫。在自己的硬碟或資料夾裡分析、打標、搜尋、預覽與切段。第一版是 macOS 原生 App。

完整產品契約：[SPEC.md](SPEC.md)

介面以繁中為主，附完整英文。系統語言是英文就顯示英文，是繁中就顯示繁中。

## 想解決什麼

旅行、活動、日常拍回來的片子通常散在外接碟與資料夾裡：DJI、iPhone、備份、重複拷貝混在一起。Finder 只靠檔名；後製要找「新山黃昏手持」得一支一支翻。標籤若只存在某一台電腦的資料庫裡，換碟、換 Mac 就斷了。

RollTag 把倉庫登記在本機，**metadata 寫在那顆硬碟的 `.rolltag/` 裡**，跟著素材走。掃描只讀長度與檔頭、不一次解整庫 4K；縮圖等格子出現才做。打標是給之後搜尋用的，不是剪輯時間軸、也不是自動上傳雲端。

這一版刻意不做：DaVinci 串接、NAS 假設、Linux／Windows、匯入就自動跑 AI。

## 使用方法

### 打開

需要 macOS 14+、Xcode 16+、本機 Python 3（sidecar，沒有介面）。

```bash
open RollTag.xcodeproj
```

在 Xcode 跑 RollTag scheme。測試：

```bash
xcodebuild -scheme RollTag -destination 'platform=macOS' test
```

### 加入倉庫

把裝 footage 的資料夾或外接碟根目錄拖進視窗，或 ⌘O／設定裡新增路徑。刪倉庫只是取消登記，不刪硬碟上的片子。

硬碟拔掉會顯示離線，搜尋不會出現它的檔；插回後自動重讀裡面的 `.rolltag/`。大目錄掃描在背景跑，左側看得到階段、檔名與百分比。要重掃按 ⌘R。

支援影片（`mov`／`mp4`／`m4v`／`avi`／`mkv`／`mxf`）、照片（含 HEIC）、音訊（`mp3`／`m4a` 等）。

### 找片子與預覽

左側是智慧列表（全部、已打標、未打標、找不到、重複）與已用過的分類。右下格線上面有搜尋與排序。只搜現在讀得到的倉庫。

點一支：右上左欄播放（影片／音訊可拉時間軸；照片看大圖），右欄看路徑、拍攝時間、GPS（有才顯示）與標籤。格線 hover 可預覽影片／音訊。空白鍵播放／暫停；P 或 Esc 進出全螢幕。⌘/ 看全部快捷鍵。

### 打標

右側可打預設分類（主題、情緒、地點、鏡頭等）或自訂字（例如「皓皓」「clubmed」）。單支與批次同一套。點 chip 可拿掉。搜尋吃這些標。

AI 打標要先在設定（⌘,）填 Gemini 或 OpenAI 的 API key。選了**影片或照片**之後，右側與標籤選單才出現按鈕（⌥⌘T）。匯入不會自動跑。音訊、空檔、解不開的會跳過。模型成功時，也會把這個倉庫裡已有的地點／自訂標從資料夾名套上去。

### 重複檔與切段

左側「重複檔」或 ⌘⇧D：並排比較，A 留最左、D 留最右、S 全留下，Enter 確認後其他複本進垃圾桶。

只選一支影片時，右側「剪輯」開獨立視窗，輸出成倉庫內新檔，可另外打標。

## 資料放哪

- 程式設定：`~/rolltag/config.json`（倉庫名單與 AI key，不含 tags）。不要把這個檔拿去分享或進公開 git。
- 每個倉庫：`<倉庫>/.rolltag/warehouse.sqlite`、縮圖、trim 輸出。跟著硬碟走。
