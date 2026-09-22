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

**AI for the untagged pile, not for import.** If you would rather not label every clip yourself, right-click Untagged and choose AI Batch Tag, or select videos and photos in the grid and right-click the same command. Gemini then OpenAI suggest only from the catalog. Folder names can attach tags you already use (`clubmed` matches `Club Med Ria`). Audio, 1 KB empties, and unreadable files are skipped. Import never burns tokens in the background. Already tagged clips can be sent again from the inspector or the grid menu. **AI tags can be wrong — review them.**

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

The left sidebar has smart lists (All, Tagged, Untagged, Missing, Duplicates) and categories you have used. Each list shows a count for the current folder scope: files for All / Tagged / Untagged / Missing, and remaining groups for Duplicates. Expand a warehouse to browse its folders. Click a folder — or check a few — to search, tag, and handle duplicates only in those folders first; click the warehouse name (or Whole library) for the rest. Switching to Untagged or Duplicates keeps the same folders. Search and sort sit above the grid. Only online warehouses are searched.

Select a clip: player on the left (video/audio scrub; photos show a still), inspector on the right (path, capture time, GPS if present, tags). Hover a grid cell to preview video/audio. Space plays/pauses and P or Esc toggles fullscreen by default; in fullscreen [ or , is previous and ] or . is next. Change keys in Settings → Shortcuts. ⌘/ lists every shortcut.

### Tag by hand

1. Select one clip, or several similar ones (same scene or burst). Check the folders you want to finish first, open Untagged, then ⌘A if you want the whole pile.
2. In the inspector on the right, open a preset category (theme, mood, place, shot, people, …) and click a facet; or type a custom word (`clubmed`, a person’s name) and press Return. Commas add several at once.
3. Click a chip to remove it. Single clip and batch use the same controls.

Non-English custom tags also get Getty/Pond5 English keywords from the bundled CC-CEDICT word list (chair, forest, hamburger), then your glossary, then romanization. Add your own pairs in Settings → Glossary. Search uses these tags later, on every job that opens this warehouse.

### AI tag

**AI tags can be wrong** — people count, place, mood, and keywords may not match the footage. Review the chips and click off anything that is off. Inspector / ⌥⌘T wait for Done; right-click batch keeps tags immediately, so check afterwards.

1. Add a Gemini or OpenAI API key in Settings → AI (⌘,). Import never runs AI by itself.
2. Select a **video or photo** (already tagged ones can be sent again). Audio, tiny files, and unreadable files are skipped.
3. Press **AI tag** in the inspector or ⌥⌘T. After the model returns, Done or Return keeps the tags; Cancel or Esc discards that batch.
4. Or right-click **Untagged** in the sidebar, or one or more items in the media grid, and choose **AI Batch Tag**. That run is one file at a time and keeps tags immediately — no confirmation.

A large batch can **fail on later files even when the clips are fine**. Gemini’s free or low tier hits rate limits much sooner than OpenAI. A Gemini failure falls through to OpenAI immediately if that key is set — no waiting between files. Failures are not skipped (skipped means audio, tiny, or no frames). The status line shows how many succeeded and failed. Wait a few minutes and run AI Batch Tag again on what is still untagged, or add a second key so one provider can cover the other.

When the model succeeds, RollTag writes catalog tags, short visible non-English custom labels, and Getty/Pond5 English keywords (lowercase, space-separated), plus this warehouse’s existing place/custom tags that match folder names.

### Get an API key

This version only sends tagging to **Gemini** or **OpenAI**. You need at least one key. Keys stay in `~/rolltag/config.json` on this Mac — do not share that file. The provider bills usage on their side.

- **Gemini:** sign in with a Google account at [Google AI Studio API keys](https://aistudio.google.com/api-keys), create a key, paste it under Gemini in Settings. Official steps: [Using Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key).
- **OpenAI:** sign in at [OpenAI API keys](https://platform.openai.com/api-keys), create a secret key, paste it under OpenAI in Settings. You may need billing enabled on the OpenAI account.

Settings → AI also has these two links. Twelve Labs, DashScope, and Claude can store a key but are not wired for tagging in this version.

### Duplicates and trim

Sidebar Duplicates or ⌘⇧D: compare side by side. If working folders are set, only groups that touch those folders appear; you still see every copy in the group. A keeps the leftmost, D the rightmost, S keeps all; Enter confirms sending the others to Trash.

With a single video selected, **Trim** opens a separate window and writes a new file in the warehouse that you can tag on its own.

## Where data lives

- App settings: `~/rolltag/config.json` (warehouse list, AI keys, glossary, shortcut overrides, and recent AI-vs-kept tagging examples — not per-file tags). Do not share that file or commit it to a public git repo.
- Per warehouse: `<warehouse>/.rolltag/warehouse.sqlite`, thumbnails, and trim exports. They stay on the disk.
- Chinese–English keywords: `CCCEDICTKeywords.json` is derived from [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict) (CC BY-SA 4.0). See `RollTag/Resources/CCCEDICT.NOTICE.txt`.

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

**AI 打未打標的一堆，不是匯入就跑。** 不想一支支手打時，在「未打標」按右鍵「AI 批次打標」，或在格線選影片／照片後右鍵同一選單；也可 ⌥⌘T。Gemini 失敗再 OpenAI，只能從現有分類選。資料夾名可套你已經在用的標（`clubmed` 對得上 `Club Med Ria`）。音訊、1 KB 空檔、解不開的會跳過。匯入不會在背景燒 token。**AI 打的標可能錯，請自己檢查。**

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

左側是智慧列表（全部、已打標、未打標、找不到、重複）與已用過的分類。旁邊會顯示目前範圍內的數量：全部／已打標／未打標／找不到是檔數，「重複檔」是還沒處理的組數。倉庫可展開看底下的目錄；點一層或勾幾個重點，搜尋、打標與重複檔只先做那些資料夾與其下層。再點「未打標」或「重複檔」不會丟掉範圍。點倉庫名或「看整倉」才回到整庫。右下格線上面有搜尋與排序。只搜現在讀得到的倉庫。

點一支：右上左欄播放（影片／音訊可拉時間軸；照片看大圖），右欄看路徑、拍攝時間、GPS（有才顯示）與標籤。格線 hover 可預覽影片／音訊。預設空白鍵播放／暫停、P 或 Esc 進出全螢幕；全螢幕時 [ 或 , 上一則、] 或 . 下一則，可在設定「快捷鍵」改。⌘/ 看全部快捷鍵。

### 手打標

1. 在格線選一支，或把同一組相似的一次選起來。可先勾重點目錄，再進「未打標」、⌘A 全選目前範圍。
2. 右側打開預設分類（主題、情緒、地點、鏡頭、人物等）點細項；或在輸入框打自訂字（例如 `clubmed`、人名）後按 Return／加入。逗號、頓號可一次加多個。
3. 點 chip 拿掉。單支與批次同一套。

打中文等非英語標時，會從內建 CC-CEDICT 詞庫補 Getty／Pond5 英文關鍵字（椅子、森林、漢堡這類日常詞也在裡面），對不上才羅馬拼音。常用人名、品牌可在設定「字詞對應」裡自己加。搜尋吃這些標，之後每個案子都能再用。

### AI 打標

**AI 打的標可能錯誤**——人數、地點、情緒、關鍵字都可能不對。請自己看過，不對的點掉。檢查器／⌥⌘T 打完會等你按「完成」；右鍵批次打完就留下，更要事後檢查。

1. 先到設定 → AI（⌘,）填 Gemini 或 OpenAI 的 API key。匯入不會自動跑。
2. 選**影片或照片**（已打過標的也可再送）。音訊、空檔、解不開的會跳過。
3. 按右側「AI 打標」或 ⌥⌘T。模型回來後：完成或 Enter 保留；取消或 Esc 拿掉這次標。
4. 或在側欄「未打標」、或媒體區選一支／多支後按右鍵「AI 批次打標」。一支一支送，打完就留下，不必確認。

大批次後面幾支**可能失敗，檔案本身往往沒問題**。Gemini 免費／低額度比 OpenAI 更容易碰到頻率上限。Gemini 失敗且有 OpenAI key 就立刻改送，支與支之間不停。這種算「失敗」，不是「跳過」（跳過是音訊、太小或抽不出幀）。狀態列會寫成功與失敗支數。等幾分鐘再對還在未打標的跑一次，或再加一把 key 當備援。

模型成功時會寫清單標、畫面裡看得清楚的短中文自訂詞，以及 Getty／Pond5 格式的英文關鍵字（小寫、空白分詞），也會把這個倉庫裡已有的地點／自訂標從資料夾名套上去。

### 如何取得 API key

這一版打標只送 **Gemini** 或 **OpenAI**，至少要有一把 key。Key 存在這台 Mac 的 `~/rolltag/config.json`，不要分享那個檔。用量由各平台計費。

- **Gemini：** 用 Google 帳號到 [Google AI Studio 的 API keys](https://aistudio.google.com/api-keys) 建立，貼到設定裡 Gemini 那一欄。官方說明：[Using Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key)。
- **OpenAI：** 到 [OpenAI API keys](https://platform.openai.com/api-keys) 建立 secret key，貼到設定裡 OpenAI 那一欄。帳號可能要先開計費。

設定 → AI 也有這兩個連結。Twelve Labs、DashScope、Claude 可以存 key，這一版打標尚未接。

### 重複檔與切段

左側「重複檔」或 ⌘⇧D：並排比較。有重點目錄時，只列出至少有一支落在那些目錄的組，比較時仍看得到組內所有複本。A 留最左、D 留最右、S 全留下，Enter 確認後其他複本進垃圾桶。

只選一支影片時，右側「剪輯」開獨立視窗，輸出成倉庫內新檔，可另外打標。

## 資料放哪

- 程式設定：`~/rolltag/config.json`（倉庫名單、AI key、字詞對應、快捷鍵覆寫、最近的 AI／留下範例，不含各檔 tags）。不要把這個檔拿去分享或進公開 git。
- 每個倉庫：`<倉庫>/.rolltag/warehouse.sqlite`、縮圖、trim 輸出。跟著硬碟走。
- 中英關鍵字：`CCCEDICTKeywords.json` 由 [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict) 篩出（CC BY-SA 4.0），說明見 `RollTag/Resources/CCCEDICT.NOTICE.txt`。
