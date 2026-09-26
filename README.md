# RollTag

本機 B-roll 倉庫。在自己的硬碟或資料夾裡打標、搜尋、預覽與切段。第一版是 macOS App。

A local B-roll warehouse for macOS: tag, search, preview, and trim footage on your own disks.

介面跟著系統語言：繁中 macOS 顯示繁中，英文 macOS 顯示英文。

---

## 安裝

需要 **macOS 14 或更新** 的 Mac。不必有 Apple Developer 帳號。AI 打標還需要本機 **Python 3**（系統內建的 `/usr/bin/python3` 即可，不用 pip）。

### 用現成的 App

1. 到 [GitHub Releases](https://github.com/ticktock35/RollTag/releases) 下載最新的 `.app` 壓縮檔，解壓後放到「應用程式」或任何資料夾。
2. 第一次開啟若被系統擋下：在 Finder 對 App **按右鍵 → 打開**，再按打開。這是因為目前用本機簽章，不是 App Store。
3. 關閉最後一個視窗或按 ⌘Q 就會結束。

### 從原始碼建置

**需要**

- 一台 Mac，系統 **macOS 14** 或更新
- [Xcode 16](https://developer.apple.com/xcode/) 或更新（App Store 安裝完整 Xcode；只裝 Command Line Tools 不夠）
- 不必登入付費的 Apple Developer Program

第一次裝完 Xcode，打開一次、同意授權。若終端機還找不到編譯器：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

**一鍵建置（建議）**

```bash
git clone https://github.com/ticktock35/RollTag.git
cd RollTag
./scripts/build.sh
open build/RollTag.app
```

建好的 App 在 `build/RollTag.app`。本機簽章，不必選 Team。

| 指令 | 做什麼 |
|---|---|
| `./scripts/build.sh` | Release 建置，輸出 `build/RollTag.app` |
| `./scripts/build.sh --debug` | Debug 建置 |
| `./scripts/build.sh --test` | 建置後跑單元測試 |
| `./scripts/build.sh --run` | 建完就打開 App |

**用 Xcode**

```bash
open RollTag.xcodeproj
```

選 RollTag scheme，按 Run（⌘R）。Signing 已設成本機簽章（Sign to Run Locally），Signing & Capabilities 不必填 Team。

**常見問題**

- `xcodebuild not found`：還沒裝完整 Xcode，或還沒 `xcode-select` 指到 Xcode。
- 打開 Xcode 一直要你選 Team：關掉自動簽章，改用專案裡的本機簽章即可；或改跑 `./scripts/build.sh`。
- 第一次開自己編的 App 被擋：Finder 對 `build/RollTag.app` 按右鍵 → 打開。
- AI 打標說 sidecar 不可用：確認這台 Mac 有 `/usr/bin/python3`。不必另外 `pip install`。

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
- 右半最上緣有加框的搜尋欄與排序。只搜現在插著、讀得到的倉庫。
- 點一支：左上看原檔（影片載入播放器、照片依螢幕大小從原檔解），右側看路徑、拍攝時間、GPS（有才顯示）與標籤。格線仍用縮圖。
- 滑過格子可預覽影片／音訊。

常用快捷鍵（可在設定 → 快捷鍵改；⌘/ 看全部）：

| 動作 | 預設 |
|---|---|
| 播放／暫停 | 空白鍵 |
| 全螢幕 | P（再按一次或 Esc 離開） |
| 上一則／下一則 | [ ／ ]（主畫面選取；全螢幕也可用 , ／ .） |
| 格線移到相鄰格子 | 方向鍵或 W A S D（⇧ 加選） |
| 全選目前結果 | ⌘A |
| 設定 | ⌘, |

### 手打標

1. 在格線選一支，或把同一組相似的一次選起來。可先勾重點目錄，再進「未打標」、⌘A 全選目前範圍。
2. 右側打開預設分類（主題、情緒、地點、鏡頭、人物等）點細項；或在輸入框打自己的字後按 Return。逗號、頓號可一次加多個。
3. 點已加上的標籤可拿掉。單支與一次選多支，用法相同。

打中文等非英語標時，會一併補上對應的英文關鍵字，之後搜中文或英文都找得到。常用人名、品牌可在設定 → 字詞對應裡自己加。

### AI 打標

**AI 給的標可能錯**（地點、情緒、關鍵字都可能不對；人數先由這台 Mac 的 Vision 判斷，仍請看過）。不對的點掉。匯入**不會**自動打標。

先到設定 → AI（⌘,）填一把 key（有兩把更好）：

- **Gemini：** 用 Google 帳號到 [Google AI Studio API keys](https://aistudio.google.com/api-keys) 建立，貼到設定。說明：[Using Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key)
- **OpenAI：** 到 [OpenAI API keys](https://platform.openai.com/api-keys) 建立 secret key，貼到設定。帳號可能要先開計費

用量由各平台計費。Key 只存在這台 Mac 的 `~/rolltag/config.json`，不要分享那個檔。

然後任選一種方式：

1. 選**影片或照片**（已打過的也可再送）。音訊、太小或解不開的會跳過。
2. 按右側「AI 打標」或 **⌥⌘T**。模型回來後：按「完成」或 Enter 保留；按「取消」或 Esc 拿掉這次標。
3. 或在側欄「未打標」、或媒體區選一支／多支後按右鍵「**AI 批次打標**」。一支一支送，打完就留下，不必再確認，所以更要事後檢查。側欄「未打標」只會打**身上還沒有任何標**的檔；已經打錯的請在格線選起來再右鍵批次，才會換掉舊 AI 標。
4. 一次超過 10 檔時，進度條有「**終止**」：停掉目前這次送出，已打的留下，還沒打的不再送。進行中會寫正在用哪個平台，以及上一支是成功還是失敗。平台名可點進去看該帳號用量。檔裡有 GPS 時會先查出地名並寫成標（城市／地區／國家），模型失敗也寫。目錄只當暗示，不會把資料夾名寫成標。附近約 1 公里內的座標會記住，不必每支都查。送出前會先用這台 Mac 的 Vision 數**人體**（玩偶臉不算）；沒人就不寫人像或人名。再打一次會換掉上次的 AI 標，手打的留下。人名等已有自訂標請自己點或手打。

大批次後面幾支可能因平台配額或逾時失敗，檔案本身往往沒問題。狀態列會寫成功與失敗支數，約 10 秒後消失。等幾分鐘再對還沒打的跑一次即可。

### 重複檔與切段

- 左側「重複檔」或 **⌘⇧D**：並排比較。A 留最左、D 留最右、S 全留下，Enter 確認後其他複本進垃圾桶。
- 只選一支影片時，右側「剪輯」開獨立視窗：中間只播入點到出點，下面片帶拉範圍，並顯示起始、結束與總時長。播到出點畫面與聲音一起停。空白鍵控制這個視窗的播放，不播後面的主視窗。存成新素材用系統儲存面板，預設開在原檔目錄；存進倉庫才寫這一支的資料，存到倉庫外只輸出影片。回到主畫面時，倉庫內選新檔、倉庫外仍選原檔。

### 資料放哪

- 程式設定（倉庫名單、API key、快捷鍵等）：`~/rolltag/config.json`  
  不要分享這個檔，也不要放進公開 git。
- GPS 反查地名快取：`~/rolltag/geocode-cache.json`
- 每個倉庫的標籤與縮圖：`<倉庫>/.rolltag/`  
  切段可存倉庫內或倉庫外；只有存進倉庫才寫這一支的資料。
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

**From source** (no Apple Developer account):

1. Install [Xcode 16+](https://developer.apple.com/xcode/) from the App Store (full Xcode, not only Command Line Tools).
2. Open Xcode once to accept the license. If needed:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

3. Build:

```bash
git clone https://github.com/ticktock35/RollTag.git
cd RollTag
./scripts/build.sh
open build/RollTag.app
```

The app lands at `build/RollTag.app`. Use `--debug`, `--test`, or `--run` if you want. Or open `RollTag.xcodeproj` and press ⌘R — signing is already set to Sign to Run Locally, so you do not pick a Team.

AI tagging uses the system `/usr/bin/python3`. No `pip install`.

### Use

1. Drop a footage folder or drive on the window, or press **⌘O**. Removing a warehouse only unregisters it; files on disk stay. Unplugged drives go offline until you plug them back in. Rescan with ⌘R.
2. Browse the sidebar lists and folders. Search and sort sit in a boxed field at the top of the right pane. Click a clip to see its stored thumb. Space or Play loads video/audio. Drag the bar between the player and the file info pane to resize them. P toggles fullscreen; ⌘/ lists shortcuts.
3. **Hand tags:** select one clip or a similar group, click a preset on the right, or type your own word and press Return. Click a tag to remove it.
4. **AI tags:** paste a [Gemini](https://aistudio.google.com/api-keys) or [OpenAI](https://platform.openai.com/api-keys) key in Settings → AI. Import never runs AI by itself. Inspector / ⌥⌘T waits for Done or Cancel. Right-click **Untagged** or the grid for **AI Batch Tag** (keeps tags immediately). Sidebar **Untagged** only sends files with no tags yet; to replace bad AI tags, select those clips in the grid and batch again. A batch of more than 10 files shows **Stop**. While it runs, the banner shows which provider is sending and whether the last clip succeeded or failed; the provider name opens that platform’s usage page. Files with GPS get a place name first and those locality parts are always written as tags (even if the model fails); nearby shots within about 1 km reuse that result. Folder names are hints only and are not written as tags. On-device Vision counts human bodies (toy faces and dog bodies do not count); empty scenes do not get portrait or name tags. Running AI again replaces the previous AI tags and keeps hand / path tags. Existing custom labels such as people’s names are not auto-applied by AI — add those by hand. **AI tags can be wrong — review them.** Later files in a large batch may fail on quota; the status line clears after about 10 seconds. Wait and retry what is still untagged.
5. **Duplicates:** sidebar or ⌘⇧D. A / D keep one side, S keeps all, Enter sends the rest to Trash. **Trim** on a single video uses an iPhone-style in/out strip; pick a folder and filename, then the new clip is indexed in the background.

Settings: `~/rolltag/config.json` (do not share). Place-name cache: `~/rolltag/geocode-cache.json`. Tags and thumbs: `<warehouse>/.rolltag/`. Full contract: [SPEC.md](SPEC.md).
