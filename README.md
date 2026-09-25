# RollTag

本機 B-roll 倉庫。在自己的硬碟或資料夾裡打標、搜尋、預覽與切段。第一版是 macOS App。

A local B-roll warehouse for macOS: tag, search, preview, and trim footage on your own disks.

介面跟著系統語言：繁中 macOS 顯示繁中，英文 macOS 顯示英文。

---

## 安裝

需要 **macOS 14 或更新**。AI 打標還需要本機已安裝 **Python 3**（系統內建的 `/usr/bin/python3` 即可）。

### 用現成的 App

1. 到 [GitHub Releases](https://github.com/ticktock35/RollTag/releases) 下載最新的 `.app` 壓縮檔，解壓後放到「應用程式」或任何資料夾。
2. 第一次開啟若被系統擋下：在 Finder 對 App **按右鍵 → 打開**，再按打開。這是因為目前用本機簽章，不是 App Store。
3. 關閉最後一個視窗或按 ⌘Q 就會結束。

### 從原始碼執行

1. 安裝 [Xcode 16](https://developer.apple.com/xcode/) 或更新。
2. 打開專案並執行：

```bash
open RollTag.xcodeproj
```

3. 在 Xcode 選 RollTag scheme，按 Run（⌘R）。

---

## 操作說明

### 加入倉庫

把裝素材的資料夾或外接碟**拖進視窗**，或按 **⌘O**／設定裡新增路徑。

- 掃描會在背景跑，左側看得到進度。
- 刪倉庫只是取消登記，**不會刪硬碟上的檔**。
- 硬碟拔掉會顯示離線，搜尋暫時看不到那些片子；插回後會再讀裡面的資料。
- 要重掃目前讀得到的倉庫：⌘R。

支援：

- 影片：`mov`、`mp4`、`m4v`、`avi`、`mkv`、`mxf`
- 照片：`heic`、`heif`、`jpg`、`jpeg`、`png`、`webp`、`gif`
- 音訊：`mp3`、`m4a`、`aac`、`wav`

### 找片子與預覽

- 左側是智慧列表（全部、已打標、未打標、找不到、重複檔）與已用過的分類。
- 倉庫可展開看目錄。點一層或勾幾個資料夾，搜尋、打標與重複檔只先做那些範圍；點倉庫名或「看整倉」回到整庫。
- 格線上方可搜尋與排序。只搜現在插著、讀得到的倉庫。
- 點一支：左上播放（影片／音訊可拉時間軸；照片看大圖），右側看路徑、拍攝時間、GPS（有才顯示）與標籤。
- 滑過格子可預覽影片／音訊。

常用快捷鍵（可在設定 → 快捷鍵改；⌘/ 看全部）：

| 動作 | 預設 |
|---|---|
| 播放／暫停 | 空白鍵 |
| 全螢幕 | P（再按一次或 Esc 離開） |
| 全螢幕上一則／下一則 | [ 或 , ／ ] 或 . |
| 格線移到相鄰格子 | 方向鍵或 W A S D（⇧ 加選） |
| 全選目前結果 | ⌘A |
| 設定 | ⌘, |

### 手打標

1. 在格線選一支，或把同一組相似的一次選起來。可先勾重點目錄，再進「未打標」、⌘A 全選目前範圍。
2. 右側打開預設分類（主題、情緒、地點、鏡頭、人物等）點細項；或在輸入框打自己的字後按 Return。逗號、頓號可一次加多個。
3. 點已加上的標籤可拿掉。單支與一次選多支，用法相同。

打中文等非英語標時，會一併補上對應的英文關鍵字，之後搜中文或英文都找得到。常用人名、品牌可在設定 → 字詞對應裡自己加。

### AI 打標

**AI 給的標可能錯**（人數、地點、情緒、關鍵字都可能不對）。請自己看過，不對的點掉。匯入**不會**自動打標。

先到設定 → AI（⌘,）填一把 key（有兩把更好）：

- **Gemini：** 用 Google 帳號到 [Google AI Studio API keys](https://aistudio.google.com/api-keys) 建立，貼到設定。說明：[Using Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key)
- **OpenAI：** 到 [OpenAI API keys](https://platform.openai.com/api-keys) 建立 secret key，貼到設定。帳號可能要先開計費

用量由各平台計費。Key 只存在這台 Mac 的 `~/rolltag/config.json`，不要分享那個檔。

然後任選一種方式：

1. 選**影片或照片**（已打過的也可再送）。音訊、太小或解不開的會跳過。
2. 按右側「AI 打標」或 **⌥⌘T**。模型回來後：按「完成」或 Enter 保留；按「取消」或 Esc 拿掉這次標。
3. 或在側欄「未打標」、或媒體區選一支／多支後按右鍵「**AI 批次打標**」。一支一支送，打完就留下，不必再確認，所以更要事後檢查。
4. 一次超過 10 檔時，進度條有「**終止**」：停掉目前這次送出，已打的留下，還沒打的不再送。進行中會寫正在用哪個平台，以及上一支是成功還是失敗。平台名可點進去看該帳號用量。檔裡有 GPS 時會先查出地名再送給 AI；附近約 1 公里內的座標會記住，不必每支都查。

大批次後面幾支可能因平台配額或逾時失敗，檔案本身往往沒問題。狀態列會寫成功與失敗支數，約 10 秒後消失。等幾分鐘再對還沒打的跑一次即可。

### 重複檔與切段

- 左側「重複檔」或 **⌘⇧D**：並排比較。A 留最左、D 留最右、S 全留下，Enter 確認後其他複本進垃圾桶。
- 只選一支影片時，右側「剪輯」開獨立視窗，切一段另存成倉庫裡的新檔，可另外打標。

### 資料放哪

- 程式設定（倉庫名單、API key、快捷鍵等）：`~/rolltag/config.json`  
  不要分享這個檔，也不要放進公開 git。
- GPS 反查地名快取：`~/rolltag/geocode-cache.json`
- 每個倉庫的標籤、縮圖與切段：`<倉庫>/.rolltag/`  
  跟著硬碟走。

更細的規則以 [SPEC.md](SPEC.md) 為準。

---

## 授權

[MIT](LICENSE)

中英關鍵字詞庫改自 [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict)（CC BY-SA 4.0），說明見 `RollTag/Resources/CCCEDICT.NOTICE.txt`。

---

## English

### Install

Requires **macOS 14+**. AI tagging also needs **Python 3** on this Mac (`/usr/bin/python3` is fine).

**Ready-made app:** download the latest `.app` zip from [Releases](https://github.com/ticktock35/RollTag/releases), unzip, and move it wherever you like. If Gatekeeper blocks the first launch, right-click the app in Finder → **Open**.

**From source:** install Xcode 16+, then:

```bash
open RollTag.xcodeproj
```

Run the RollTag scheme (⌘R).

### Use

1. Drop a footage folder or drive on the window, or press **⌘O**. Removing a warehouse only unregisters it; files on disk stay. Unplugged drives go offline until you plug them back in. Rescan with ⌘R.
2. Browse the sidebar lists and folders. Search and sort sit above the grid. Click a clip to play it (photos show a still). Space plays/pauses; P toggles fullscreen; ⌘/ lists shortcuts.
3. **Hand tags:** select one clip or a similar group, click a preset on the right, or type your own word and press Return. Click a tag to remove it.
4. **AI tags:** paste a [Gemini](https://aistudio.google.com/api-keys) or [OpenAI](https://platform.openai.com/api-keys) key in Settings → AI. Import never runs AI by itself. Inspector / ⌥⌘T waits for Done or Cancel. Right-click **Untagged** or the grid for **AI Batch Tag** (keeps tags immediately). A batch of more than 10 files shows **Stop**. While it runs, the banner shows which provider is sending and whether the last clip succeeded or failed; the provider name opens that platform’s usage page. Files with GPS get a place name first; nearby shots within about 1 km reuse that result. **AI tags can be wrong — review them.** Later files in a large batch may fail on quota; the status line clears after about 10 seconds. Wait and retry what is still untagged.
5. **Duplicates:** sidebar or ⌘⇧D. A / D keep one side, S keeps all, Enter sends the rest to Trash. **Trim** on a single video writes a new clip in the warehouse.

Settings: `~/rolltag/config.json` (do not share). Place-name cache: `~/rolltag/geocode-cache.json`. Tags and thumbs: `<warehouse>/.rolltag/`. Full contract: [SPEC.md](SPEC.md).
