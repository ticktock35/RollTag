# RollTag

A local B-roll warehouse. Analyze, tag, search, preview, and trim footage on your own disks. Version 1 is a native macOS app.

Product contract (Traditional Chinese, kept in sync with the app): [SPEC.md](SPEC.md)

The app UI is Traditional Chinese first, with full English localization. It follows the Mac language: English macOS → English UI; 繁中 macOS → 繁中 UI.

## The problem

Travel, events, and daily shoots land on external drives as a mix of DJI clips, iPhone stills, backups, and accidental copies. Finder only searches filenames. DaVinci can search, but the index belongs to **that project**: open a new cut and you start over, unless you maintain a huge Super Bin of the whole library. Finding “golden-hour handheld in Johor” then means either scrubbing files or waiting for another project to come online. If tags live only on one Mac, they vanish when you swap disks.

RollTag registers warehouses on this Mac and **writes metadata inside each disk’s `.rolltag/` folder**, so tags travel with the footage. Scans read duration and file headers; they do not decode an entire 4K library. Thumbnails are built when a cell appears. Tagging is for search later — not a timeline editor, and not an automatic cloud upload.

This version does not: DaVinci integration, a NAS assumption, Linux/Windows, or AI tagging on import.

## Scenarios

**Back from a trip.** A drive holds DJI Pocket clips, iPhone stills, and a folder tree like `馬來西亞/新山/Club Med`. Drop the drive on RollTag. The scan stays metadata-only so the Mac does not stall decoding hundreds of 4K files. Capture time prefers the file header, then the DJI filename, not the copy date. GPS shows when the stills have it.

**Tag by hand or with AI; similar clips together.** After the scan, select a group that belongs together — same scene, same move, a burst — and apply one set of tags to all of them. Preset facets (place, shot, mood) plus custom words (`clubmed`, a person’s name), typed in or suggested with ⌥⌘T. Hover the grid and use Space while you label: you are reviewing the pile and building the library in the same pass. Next edit, type “dusk handheld ocean” or `clubmed` instead of opening every `DJI_…_D.MP4`. Those tags stay on the disk, so every future job reuses them.

**Start a new DaVinci project without re-indexing the library.** Media Pool search only sees what that project has imported. A Super Bin of every trip is possible, but it is slow to build and easy to let rot. RollTag’s search sits on the warehouse: same tags, same drive, every job. Find the clip here, then import just that file (or a trim) into the new timeline.

**AI for the untagged pile, not for import.** If you would rather not label every clip yourself, select Untagged (or a folder’s worth of videos and photos) and press ⌥⌘T. Gemini then OpenAI suggest only from the catalog. Folder names can attach tags you already use (`clubmed` matches `Club Med Ria`). Audio, 1 KB empties, and unreadable files are skipped. Import never burns tokens in the background.

**Two copies of the same clip.** Backup + camera dump often mean the same bytes twice. Duplicates compares them side by side. Keep one (A / D), merge tags, Enter sends the rest to Trash. Keep-all (S) when both paths are intentional.

**Need thirty seconds, not the whole take.** Open Trim on one video, set in/out, export a new file in `.rolltag/trimmed/`. Tag that clip on its own. The timeline in the main player is for checking, not grading.

**Swap Macs or unplug the drive.** Tags live in `<warehouse>/.rolltag/`, not only on this computer. Offline warehouses stay in Settings; search hides them until the disk is back.

## How it saves an editor time

| Without RollTag | With RollTag |
|---|---|
| Finder by filename; scrub every clip in the NLE | Search tags, path, notes; hover-preview then play only candidates |
| DaVinci search only after the project (or a Super Bin) is indexed | Warehouse search is ready on the next job; no Super Bin to rebuild |
| Importing a drive into an NLE just to browse | Warehouse scan does not decode 4K; thumbnails appear when a cell is on screen |
| Copy date looks like shoot date | Header / DJI filename / file date, shown in the inspector |
| Duplicate dumps eat disk and attention | Keep-one, trash the rest, tags stay on the keeper |
| Auto-AI on every import, or no AI at all | Hand tags, AI, or both; you choose the batch; failures do not write path tags |
| Similar takes watched one by one in the NLE just to remember them | Select the similar group; review and tag in one pass; reuse on the next job |
| Tags on one Mac’s database | Tags travel on the disk with the footage |
| Cut a subclip only after a full project is open | Trim one file to a new warehouse clip |

RollTag is the **find and label** step before the timeline: a fast library search that does not reset when you open a new DaVinci project. It does not replace Resolve or a multi-track cut.

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

The left sidebar has smart lists (All, Tagged, Untagged, Missing, Duplicates) and categories you have used. Expand a warehouse to browse its folders. Click a folder — or check a few — to search, tag, and handle duplicates only in those folders first; click the warehouse name (or Whole library) for the rest. Switching to Untagged or Duplicates keeps the same folders. Search and sort sit above the grid. Only online warehouses are searched.

Select a clip: player on the left (video/audio scrub; photos show a still), inspector on the right (path, capture time, GPS if present, tags). Hover a grid cell to preview video/audio. Space plays/pauses; P or Esc toggles fullscreen. ⌘/ lists every shortcut.

### Tag

Tag by hand or with AI. Check the folders you want to finish first, open Untagged, then ⌘A. For a run of similar clips, select them together so one pass covers the group — faster than one file at a time, and you are already looking at the footage. The inspector accepts preset facets (theme, mood, place, shot, …) or custom words (`clubmed`, a person’s name). Single clip and batch use the same controls. Click a chip to remove it. Search uses these tags later, on every job that opens this warehouse.

For AI tagging, add a Gemini or OpenAI API key in Settings (⌘,). After you select a **video or photo**, the inspector and Tag menu show the action (⌥⌘T). Import never runs AI by itself. Audio, tiny files, and unreadable files are skipped. When the model succeeds, RollTag also applies this warehouse’s existing place/custom tags that match folder names.

### Duplicates and trim

Sidebar Duplicates or ⌘⇧D: compare side by side. If working folders are set, only groups that touch those folders appear; you still see every copy in the group. A keeps the leftmost, D the rightmost, S keeps all; Enter confirms sending the others to Trash.

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

旅行、活動、日常拍回來的片子通常散在外接碟與資料夾裡：DJI、iPhone、備份、重複拷貝混在一起。Finder 只靠檔名。DaVinci 也能搜，但索引屬於**那一個專案**：換一個案子就要再匯入、再等它建好，除非你維護一個涵蓋整庫的超大 Super Bin。要找「新山黃昏手持」就變成要嘛一支支翻，要嘛等專案初始化。標籤若只存在某一台電腦的資料庫裡，換碟、換 Mac 就斷了。

RollTag 把倉庫登記在本機，**metadata 寫在那顆硬碟的 `.rolltag/` 裡**，跟著素材走。掃描只讀長度與檔頭、不一次解整庫 4K；縮圖等格子出現才做。打標是給之後搜尋用的，不是剪輯時間軸、也不是自動上傳雲端。

這一版刻意不做：DaVinci 串接、NAS 假設、Linux／Windows、匯入就自動跑 AI。

## 使用情境

**旅行剛回來。** 外接碟裡混著 DJI Pocket 影片、iPhone 照片，資料夾可能是 `馬來西亞/新山/Club Med`。把碟拖進 RollTag。掃描只讀檔頭與長度，不會一次解開整庫 4K 把 Mac 卡住。拍攝時間優先檔頭、再試 DJI 檔名，而不是拷進硬碟的那天。照片有 GPS 才顯示座標。

**可 AI 打標，也可手打；相似的一起打。** 掃完後把同一組相近的片子一次選起來（同場景、同鏡頭、同一段連拍），預設分類（地點、鏡頭、情緒）加上自訂字（`clubmed`、人名），手打或 ⌥⌘T 都可以。格線 hover、空白鍵一邊審一邊標，不必進時間軸才決定這支是什麼。標寫在硬碟上，之後搜「黃昏 手持 海」或 `clubmed` 就能用，每個案子都不必再審一次。

**開新的 DaVinci 案子，不必重做素材庫索引。** Media Pool 搜尋只看這個專案已經匯入的東西。把每次旅行都丟進 Super Bin 做得到，但建立慢、也容易過期。RollTag 的搜尋綁在倉庫：同一顆碟、同一套標，每個案子都能用。在這裡找到再把那一支（或 trim 過的）匯進新時間軸。

**AI 打未打標的一堆，不是匯入就跑。** 不想一支支手打時，點「未打標」（或一次選一層影片／照片），⌥⌘T。Gemini 失敗再 OpenAI，只能從現有分類選。資料夾名可套你已經在用的標（`clubmed` 對得上 `Club Med Ria`）。音訊、1 KB 空檔、解不開的會跳過。匯入不會在背景燒 token。

**同一段拷了兩份。** 相機倒出加上備份，常常位元組一樣。重複檔並排比較，A／D 留一個、標籤合併，Enter 把其他丟進垃圾桶。兩邊都要留就按 S。

**只要三十秒，不要整支。** 單支影片開「剪輯」，進出點後輸出成 `.rolltag/trimmed/` 的新檔，可另外打標。主畫面時間軸是核對用，不是調色。

**換電腦或拔掉硬碟。** 標籤在 `<倉庫>/.rolltag/`，不是只存在這台 Mac。離線倉庫留在設定裡，搜尋暫時不出現，碟插回再讀。

## 怎麼幫剪輯師省時間

| 沒有 RollTag | 有 RollTag |
|---|---|
| Finder 靠檔名；進時間軸一支支刷 | 搜標籤、路徑、備註；hover 再播候選 |
| DaVinci 搜尋要等專案（或 Super Bin）建好索引 | 倉庫搜尋換案子就能用，不必重建 Super Bin |
| 為了瀏覽就把整顆碟匯進後製 | 掃描不解 4K；縮圖等格子出現才做 |
| 拷貝日被當成拍攝日 | 檔頭／DJI 檔名／檔案日期，檢查器寫來源 |
| 重複備份佔空間又佔注意力 | 留一個、其餘進垃圾桶，標籤跟留下的走 |
| 要么匯入就自動 AI，要么完全手打 | 手打、AI、或混用；自己選批次；模型失敗連路徑標都不寫 |
| 相似片進時間軸一支支看才記得是什麼 | 同一組一次選、審的同時打標；之後每案都能搜 |
| 標籤綁在某一台電腦 | 標籤跟著硬碟走 |
| 要開完整專案才能切一小段 | 單支 trim 成倉庫裡的新素材 |

RollTag 是進時間軸**之前**的找片與打標：換 DaVinci 案子也不必重做素材庫索引。不取代 Resolve 或多軌剪輯。

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

左側是智慧列表（全部、已打標、未打標、找不到、重複）與已用過的分類。倉庫可展開看底下的目錄；點一層或勾幾個重點，搜尋、打標與重複檔只先做那些資料夾與其下層。再點「未打標」或「重複檔」不會丟掉範圍。點倉庫名或「看整倉」才回到整庫。右下格線上面有搜尋與排序。只搜現在讀得到的倉庫。

點一支：右上左欄播放（影片／音訊可拉時間軸；照片看大圖），右欄看路徑、拍攝時間、GPS（有才顯示）與標籤。格線 hover 可預覽影片／音訊。空白鍵播放／暫停；P 或 Esc 進出全螢幕。⌘/ 看全部快捷鍵。

### 打標

可手打，也可 AI。先勾要處理的重點目錄，再進「未打標」、⌘A。同一組相似的影片建議一起選、一次打，比一支支快，而且審素材的同時標就打完了。右側可打預設分類（主題、情緒、地點、鏡頭等）或自訂字（例如「皓皓」「clubmed」）。單支與批次同一套。點 chip 可拿掉。搜尋吃這些標，之後每個案子都能再用。

AI 打標要先在設定（⌘,）填 Gemini 或 OpenAI 的 API key。選了**影片或照片**之後，右側與標籤選單才出現按鈕（⌥⌘T）。匯入不會自動跑。音訊、空檔、解不開的會跳過。模型成功時，也會把這個倉庫裡已有的地點／自訂標從資料夾名套上去。

### 重複檔與切段

左側「重複檔」或 ⌘⇧D：並排比較。有重點目錄時，只列出至少有一支落在那些目錄的組，比較時仍看得到組內所有複本。A 留最左、D 留最右、S 全留下，Enter 確認後其他複本進垃圾桶。

只選一支影片時，右側「剪輯」開獨立視窗，輸出成倉庫內新檔，可另外打標。

## 資料放哪

- 程式設定：`~/rolltag/config.json`（倉庫名單與 AI key，不含 tags）。不要把這個檔拿去分享或進公開 git。
- 每個倉庫：`<倉庫>/.rolltag/warehouse.sqlite`、縮圖、trim 輸出。跟著硬碟走。
