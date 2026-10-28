# RollTag

本機 B-roll 素材倉庫。檔案依然保留在你的硬碟或資料夾中，不上傳雲端、不變更儲存位置。專為標籤標註、關鍵字搜尋、原檔預覽設計，必要時可快速剪輯精華片段。原生 macOS 應用程式。

A local B-roll warehouse for macOS: tag, search, preview, and trim footage on your own disks. For everyone else, it is also a fast viewer for photos and videos already on a drive.

介面跟隨系統語言：繁體中文 macOS 顯示繁體中文，英文 macOS 顯示英文。

目前版本 **1.0.2**。跟上一版差在哪，看 [CHANGELOG.md](CHANGELOG.md)。

這不是非線性剪輯軟體（不具備多軌時間軸、調色或複雜特效剪輯），剪輯成片請回到你慣用的專業剪輯工具。對一般使用者而言，只要把存放照片、短片或手機備份的資料夾拖曳進來，它也非常適合作為高效率的照片與影片檢視器：點選檢視原檔畫質、空白鍵播放、全螢幕檢視、觸控板雙指縮放、切換下一張／下一部影片；日後想尋找特定旅程或親友時，再依賴標籤與關鍵字搜尋。本軟體不取代 Apple 系統「照片」的 iCloud 相簿，檔案永遠存放在你自己的外接硬碟上。

---

## 適用族群與使用方式

不必輸入任何 API 金鑰，就能加入倉庫、作為照片與影片檢視器、手動標籤、搜尋、剪輯片段與尋找重複檔案。AI 輔助打標預設先使用本機端 AI（畫面完全留在本機，不外傳雲端），亦可設定 Gemini／OpenAI 金鑰作為進階備援。匯入素材時**絕不會**自動執行 AI 打標。

### 拍片與剪輯創作者（頻道經營、活動記錄、後製剪輯）

**常見痛點：** 煙火、空鏡、街景、人物訪談等 B-roll 素材散落在好幾顆外接硬碟中。每開啟一個新的剪輯專案都要重新翻找一次，且相機原始檔名往往無法反映畫面內容。

**推薦工作流程：**

1. 把存放素材的外接硬碟或資料夾拖曳進視窗，登記為一個「倉庫」。卸載硬碟時顯示離線，重新接回後所有標籤依然完好。
2. 在左側邊欄勾選本次要處理的目錄（例如某一場活動資料夾），搜尋與標籤標註將只鎖定該範圍。
3. 影片縮圖沒有滑鼠時，中間有半透明播放圖示。停超過 2 秒會在格子裡自動播，移開就停。點選後主播放區載入原檔；正在看的那支，縮圖不再跟著滑鼠播。空白鍵播放，P 進入全螢幕，`[` / `]` 切上一部／下一部。接兩台螢幕時可用「視窗 → 雙螢幕」，讓播放區和打標資料欄到主要顯示器。
4. 同一場景的畫面可多選批次處理，於右側欄位點選主題／情緒／鏡頭等預設標籤，或自行輸入客戶名稱、專案名稱。輸入中文時會自動對應補上英文關鍵字，日後以兩種語言皆能精準搜尋。
5. 大量未標註素材可批次請本機 AI 協助；人物姓名與專屬品牌仍建議自行輸入。不合適的標籤點擊即可移除。
6. 搜尋「夜景」「無人」「drone」等關鍵字將合適素材篩選出來，直接從格線拖進瀏覽器、DaVinci、Photoshop、Terminal 或 Finder（送出原檔完整路徑，對方讀硬碟上的檔）。
7. 若只要其中數秒：點選右側「剪輯」拉動入點與出點，迅速匯出為新素材。
8. 同一部影片若備份了多份：點選左側「重複檔案」保留一份，其餘移至系統垃圾桶。

換到下一個剪輯專案時，不必重新掃描硬碟。本版本目前未提供與 DaVinci 等剪輯軟體的直接外掛連動。

### 攝影愛好者、旅遊與活動記錄者

**常見痛點：** 相機 RAW 檔、JPEG 與手機 HEIF 混雜在同一目錄；同一張照片存在多個備份；想用「星空」「海邊」搜尋時，Finder 卻只能依檔名與日期排序。

**推薦工作流程：**

1. 把當年度的旅遊硬碟或「活動照片」資料夾拖曳進來。
2. 透過左側目錄樹先縮小範圍，再搜尋地名或自行標記的標籤（例如城市名、餐廳名或同行親友）。
3. 點選後主檢視區直接載入原檔畫質（非模糊小縮圖）。影片縮圖停超過 2 秒會在格子裡播。全螢幕瀏覽照片與影片：空白鍵播放、雙指縮放、Z 鍵適應視窗、`[` / `]` 切換上一張／下一部，不必開啟大量「預覽程式」視窗。
4. 批次 AI 可協助歸類主題與地點（內含 GPS 資訊者會優先寫入地名標籤）；仍請抽查檢視，尤其是人物或情緒標籤。
5. 進入「重複檔案」清理 RAW＋JPEG＋備份中多出來的複本，迅速釋放寶貴的硬碟空間。

### 同一張照片、同一部影片存有多個複本

**常見痛點：** 相機同時儲存 RAW 與 JPEG；手機備份又整包複製到外接硬碟；同一資料夾曾重複拷貝。Finder 檔名極為相似，分不清哪一份該保留。

**推薦工作流程：**

1. 把這些資料夾或硬碟拖曳進 RollTag，靜待背景掃描完成。
2. 點選左側邊欄「重複檔案」，或按下 **⌘⇧D**。上半部並排比對目錄路徑與畫面細節，下半部逐組確認。
3. **A** 保留最左、**D** 保留最右、**S** 該組全部保留。確認無誤後按 **Enter**，未保留的複本移至垃圾桶。不確定時可按 **P** 進入全螢幕仔細檢視選中的檔案。
4. 若只想清理特定旅程：先在側邊欄勾選該資料夾，重複檔案便只會列出與該目錄相關的組別。
5. 暫時不想處理的組別可直接跳過，徽章數字顯示的是尚未處理的組數。

刪除時是將複本移至系統垃圾桶，原檔儲存路徑維持不變。在軟體中移除倉庫不會刪除硬碟上的實體檔案。

### 硬碟存放大量生活照片與短片的日常使用者

**常見痛點：** 外接硬碟存放了多年來的手機備份。Finder 開啟資料夾反應緩慢，「預覽程式」一次只能開啟單一檔案，難以尋找某次家庭聚會的影片。

**推薦工作流程：**

1. 把該外接硬碟或「照片／影片」資料夾拖曳進 RollTag，靜候背景掃描完成（左側顯示即時進度）。初次建立資料庫需要一些時間，但格線隨掃隨出，點選即享有原檔畫質。不需急著一次完成所有標籤。
2. 全螢幕（P）瀏覽照片與影片：空白鍵播放、雙指縮放、Z 鍵適應視窗、`[` / `]` 或 `,` / `.` 切換上一張／下一部。照片與短片可共存於同一資料夾無縫翻看。
3. 日後欲尋找某次旅行或特定人物：搜尋記憶中的關鍵字，或從左側「已打標」分類切入。常翻閱的代表性檔案標上幾個標籤即可，其餘暫不處理無妨。
4. 硬碟離線拔除無虞。下次重新接上，原先建立的標籤完整保留，可隨時繼續搜尋與檢視。

失效路徑會歸類至左側「找不到」，絕不無聲消失。移除倉庫僅為取消軟體登記，**絕不刪除硬碟上的實體檔案**。

### 初次使用建議步驟

1. 拖曳一個資料夾或外接硬碟進入視窗。
2. 在格線中點選幾張照片或影片，確認原檔預覽無誤；可按 P 進入全螢幕體驗翻看。
3. 挑選幾部檔案手動加上兩個標籤，再於上方搜尋欄測試檢索。
4. 有需要時再填入 AI 金鑰；無金鑰亦絲毫不影響日常檢視與搜尋。
5. 詳細按鍵與格式請參閱下方「操作說明」。

**本版本不適用：** 期望在此進行成片多軌剪輯、需多人協作雲端庫存，或需 Windows／Linux 環境者。目前專注於單機 Mac 最佳體驗。

---

## 安裝

需要 **macOS 14 或更新版本** 的 Mac，不需要 Apple 開發者帳號。

### 下載預先編譯的 App

1. 前往 [GitHub Releases](https://github.com/ticktock35/RollTag/releases) 閱讀說明，下載 `RollTag.zip`。
2. 解壓縮後將 `RollTag.app` **拖曳進「應用程式」（Applications）資料夾**。若留在下載項目中，Finder 的應用程式清單可能不會列出。
3. 初次開啟若被系統擋下：在 Finder 對 App **按右鍵 → 打開**，再點選「打開」。此因目前使用本機自簽憑證，尚未經 Apple 官方公證。
4. macOS 26 的應用程式圖示網格常略過未公證的本機簽章 App，請使用網格搜尋、Finder → 應用程式，或直接拖曳至 Dock。
5. 關閉最後一個視窗或按下 ⌘Q 即可結束程式。

### 從原始碼編譯

**系統需求：**

- 一台執行 **macOS 14** 或更新版本的 Mac
- [Xcode 16](https://developer.apple.com/xcode/) 或更新版本（請至 App Store 安裝完整 Xcode；僅安裝 Command Line Tools 不足）
- 不需登入付費的 Apple Developer Program 帳號

初次安裝完 Xcode 後，請開啟一次並同意授權條款。若終端機尚未指定編譯器路徑，請執行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

**一鍵編譯與安裝（建議方式）：**

```bash
git clone https://github.com/ticktock35/RollTag.git
cd RollTag
./scripts/build.sh --install
```

編譯完成的 App 會儲存於 `build/RollTag.app`；Release 建置還會額外產出 `build/RollTag.zip` 供發布使用。`--install` 參數會自動將其複製到 `/Applications` 並開啟。使用本機簽章，不需要設定 Team。

| 指令 | 說明 |
|---|---|
| `./scripts/build.sh` | Release 正式建置，輸出 `build/RollTag.app` 與 `build/RollTag.zip` |
| `./scripts/build.sh --debug` | Debug 開發建置 |
| `./scripts/build.sh --test` | 建置後自動執行單元測試 |
| `./scripts/build.sh --run` | 建置完成後立即啟動 App |
| `./scripts/build.sh --install` | 安裝至 `/Applications` 並自動啟動 |

**使用 Xcode 開啟：**

```bash
open RollTag.xcodeproj
```

選取 RollTag scheme，按下 Run（⌘R）。Signing 已配置為本機簽章（Sign to Run Locally），Signing & Capabilities 欄位不需填寫 Team。

**常見問題排解：**

- `xcodebuild not found`：尚未安裝完整 Xcode，或尚未執行 `xcode-select` 指向 Xcode。
- 開啟 Xcode 時持續要求選取 Team：關閉自動簽章，改用專案內建的本機簽章（Sign to Run Locally），或直接使用 `./scripts/build.sh`。
- 初次開啟自行編譯的 App 被系統攔截：在 Finder 中對 App 按右鍵 → 選擇「打開」。
- 執行 `./scripts/build.sh --install` 成功後，應用程式網格中未顯示 RollTag：此為正常現象，請透過 Spotlight 搜尋、Finder 的「應用程式」目錄開啟，或直接拖曳至 Dock。

---

## 操作說明

### 加入倉庫

把存放素材的資料夾或外接硬碟**拖曳進視窗**，或按 **⌘O**／於設定中新增路徑。

- 掃描會在背景執行，左側邊欄可檢視當前進度。初次建立資料庫需要一些時間，但已辨識出的檔案可隨時預覽。
- 移除倉庫僅為取消軟體登記，**絕不刪除硬碟上的實體檔案**。
- 拔除外接硬碟時會自動標示為離線，搜尋暫時隱藏該批素材；重新插回後將立即恢復讀取。
- 若要重新掃描目前已連線的倉庫：按下 **⌘R**。

支援格式：

- 影片：`mov`、`mp4`、`m4v`、`avi`、`mkv`、`mxf`、`webm`、`mpg`、`mpeg`
- 照片：`heic`、`heif`、`hif`、`jpg`、`jpeg`、`png`、`webp`、`gif`、`tif`、`tiff`、`avif`、`arw`、`dng`、`cr2`、`cr3`、`nef`、`raf`、`raw`
- 音訊：`mp3`、`m4a`、`aac`、`wav`

### 尋找素材與原檔預覽

- 左側邊欄為智慧清單（全部素材、已打標、未打標、找不到、重複檔案）與自訂分類。
- 倉庫可展開檢視完整目錄樹。點選單一目錄或勾選多個資料夾，搜尋、標籤標註與重複檔案比對將僅限於該範圍；點選倉庫名稱或「看整倉」可重設為全庫檢視。
- 右半部頂端設有搜尋欄與排序選單，僅搜尋目前已連接且可讀取的倉庫。視窗最右上角的書本圖示可開啟內建使用手冊（涵蓋加入倉庫、檢視照片與影片、重複檔案比對、常用快速鍵、搜尋、AI 輔助打標、GPX 軌跡等）。
- 點選任一檔案：主檢視區載入原檔畫質（影片載入專用播放器、照片依螢幕解析度解碼），右側欄位呈現檔案路徑、拍攝時間、GPS 座標（有記錄才顯示）與標籤。格線維持縮圖。
- 影片縮圖滑鼠不在上面時，中間有半透明播放圖示。停超過 2 秒會在格子裡自動播，移開就停。主播放區正在看的那支，縮圖不再跟著滑鼠播。照片維持靜態。音訊在格子上不播，點選後在播放區聽。
- WebM／MKV 的 VP8、VP9 用系統瀏覽器引擎播。AV1 這台 Mac 解不開；有裝 ffmpeg（Homebrew）會先做成預覽再播，第一次要等一下，做完留在這台 Mac，下次直接播。這裡播不了時，可改用預設 App、QuickTime、預覽，或自己挑一個打開原檔。格線右鍵也有同一項。
- 倉庫選單支援匯入 GPX，匯入後的航跡會列在左側邊欄的 GPX 專區。在倉庫資料夾按右鍵套用指定軌跡後，拍攝時間落在該航程時段內的照片／短片會集中列出；缺少 GPS 者會自動計算內插座標並寫入倉庫索引（不修改原檔）。各資料夾亦可自訂相機時鐘偏移。

常用快速鍵（可於「設定 → 快速鍵」中自訂；按下 **⌘/** 檢視完整清單）：

| 操作動作 | 預設快速鍵 |
|---|---|
| 播放／暫停 | 空白鍵 |
| 全螢幕模式 | P（再次按下或按 Esc 離開） |
| 上一則／下一則檔案 | [ ／ ]（主畫面選取；全螢幕模式下亦可用 , ／ .） |
| 在格線中移動選取鄰近格子 | 方向鍵 或 W A S D（按住 Shift 可連續多選） |
| 全選目前篩選結果 | ⌘A |
| 開啟偏好設定 | ⌘, |

### 手動標籤標註

1. 在格線中選取單一檔案，或按住快速鍵連續選取多個相似檔案。可先勾選特定目錄縮小範圍，再切換至「未打標」，按下 ⌘A 全選目前結果。
2. 於右側欄位展開預設分類（主題、情緒、地點、鏡頭、人物等）點選細項；或於輸入框鍵入自訂字詞後按下 Return。使用逗號或頓號可一次新增多個標籤。
3. 點選已套用的標籤徽章即可將其移除。單一檔案與多選檔案的操作方式完全一致。

輸入中文等非英語標籤時，系統會自動補上對應的英文關鍵字，日後無論搜尋中文或英文皆能精準檢索。常用人名、品牌亦可於「設定 → 字詞對應」中自行擴充。

### AI 智慧打標

**AI 提供之標籤偶有誤差**（地點細節、情緒氛圍或關鍵字皆可能未盡精確；畫面人數會優先經由本機 Apple Vision 檢驗，仍建議稍作抽查）。不合適的標籤點擊即可移除。匯入素材時**絕不會**自動執行 AI 打標。

請先至「設定 → AI」（⌘,）選取運作模式：

- **本機 AI（預設啟用、優先執行）：** 不需輸入 API 金鑰。**畫面完全保留在您的 Mac 本機運算**，絕不上傳 Google 或 OpenAI。提供三款本機引擎選用：Apple Vision（系統原生、免下載、零硬碟佔用）、MS Florence-2 Base（密集場景描述，約 370 MB）與 RAM++（開放式標籤庫，約 2.8 GB）。後兩者支援在設定頁面隨選下載／刪除，或於首次打標時顯示確認提示框（可選擇立即下載並打標、改用 Apple Vision 或切換為雲端備援）。未安裝或執行失敗時，才會自動改用已設定的 Gemini／OpenAI 備援。
- **Gemini：** 使用 Google 帳號前往 [Google AI Studio API keys](https://aistudio.google.com/api-keys) 免費申請金鑰並貼入設定中。
- **OpenAI：** 前往 [OpenAI API keys](https://platform.openai.com/api-keys) 建立 Secret Key 並貼入設定中（需預先充值帳戶額度）。

雲端運算費用由各服務商直接計費。API 金鑰僅安全儲存在這台 Mac 的 `~/rolltag/config.json`，請勿任意分享該檔案。

執行方式：

1. 在格線中選取**影片或照片**（已標註過的檔案亦可重新送出）。音訊檔、過小檔案或無法解碼之檔案將自動略過。
2. 點選右側欄位的「AI 打標」按鈕，或按下快速鍵 **⌥⌘T**。當模型回傳結果後：按下「完成」或 Return 保留標籤；按下「取消」或 Esc 放棄本次結果。
3. 或於左側邊欄的「未打標」項目，或在格線中選取檔案後按右鍵選取「**AI 批次打標**」。系統將逐一發送並自動保存，不需每張手動確認，因此更建議事後進行抽查。側邊欄「未打標」僅會處理**身上完全無標籤**的檔案；若欲修正先前打錯的檔案，請直接在格線中選取並按右鍵批次打標，系統才會替換舊有 AI 標籤。
4. 單次批次超過 10 個檔案時，進度列會提供「**終止**」按鈕：可隨時中途停止發送，已完成的標籤完整保留，尚未處理的檔案則安全略過。執行中會清楚標示當前使用的模型平台與上一部檔案的成功/失敗狀態。若檔案內含 GPS 資訊，會優先反查地名並寫入城市／地區／國家標籤。送出前會先經由本機 Apple Vision 檢驗**真實人體軀幹**（玩具公仔與雕像不算）；若畫面無人，則不會虛構人物或肖像標籤。重新打標會覆蓋先前的 AI 標籤，但會**完整保留您手動加入的標籤**。

大批次處理時，後段檔案可能因雲端平台配額限制或連線逾時而暫時失敗，檔案本身往往完好無損。狀態列會顯示成功與失敗數量並於約 10 秒後淡出。稍候數分鐘對尚未標註的檔案再次執行即可。

### 重複檔案比對與片段剪輯

- 左側邊欄「重複檔案」或 **⌘⇧D**：並排比對畫面與目錄。A 保留最左、D 保留最右、S 全部保留，按下 Enter 確認後，未保留的複本將移至系統垃圾桶。
- 選取單一部影片時，點選右側欄位「剪輯」開啟獨立剪輯視窗：中央僅播放入點至出點區間，下方片帶拖曳調整範圍，並即時顯示起始、結束與總時長。播放至出點時畫面與聲音同步停止。空白鍵僅控制該剪輯視窗的播放，不影響主視窗。匯出新素材時支援系統儲存面板，預設開啟於原檔所在目錄；儲存於倉庫內會自動登記為新素材，儲存至倉庫外則僅輸出純影片檔案。返回主畫面時，儲存於倉庫內者自動選取新檔，儲存於倉庫外者維持選取原檔。

### 資料儲存路徑

- 應用程式全域設定（倉庫清單、API 金鑰、快速鍵等）：`~/rolltag/config.json`
- 本機端 AI 模型權重檔案：`~/rolltag/models/florence2/`、`~/rolltag/models/ram_plus/`
- GPS 離線反查地名快取：`~/rolltag/geocode-cache.json`
- 各倉庫之標籤索引與縮圖快取：`<倉庫>/.rolltag/`  
  包含匯入之 GPX 航跡複本、各目錄時鐘偏移值與軌跡關聯均存放於此，**資料跟著硬碟走**。

更詳細之技術規範請以 [SPEC.md](SPEC.md) 為準。

---

## 軟體授權

[MIT 授權條款](LICENSE)

中英關鍵字辭典改編自 [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict)（採 CC BY-SA 4.0 授權），詳細聲明請見 `RollTag/Resources/CCCEDICT.NOTICE.txt`。

---

## English


Current version: **1.0.2**. See [CHANGELOG.md](CHANGELOG.md).

This is not an NLE and not a photo library. Files stay on your disks. Tag, search, preview, and trim here; edit the story in your usual cutting app.

You do not need an API key to add a warehouse, preview, hand-tag, search, trim, or find duplicates. AI tagging is optional and never runs on import.

**Editors and filmmakers:** drop a drive in as a warehouse. Scope a folder for one job, tag B-roll by theme / mood / shot, search in Chinese or English, trim a few seconds, and send keepers to your timeline. Unplug the drive and the tags stay with it; a new DaVinci project does not need a new index. This version does not connect to DaVinci.

**Photographers and travel / event shooters:** mix RAW, JPEG, and phone HEIF in one warehouse. Search by place or people you tagged. Review originals (not tiny thumbs), pinch-zoom in fullscreen, and clear duplicate RAW+JPEG+backup copies.

**People sitting on duplicate photos and videos:** the same shot often exists as RAW + JPEG, a phone backup, and a copied folder. Drop those disks in, open **Duplicates** (or ⌘⇧D), compare side by side, then **A** keep left, **D** keep right, **S** keep all, **Enter** send the rest to Trash. Pin a trip folder first if you only want groups that touch that folder. The sidebar number is unfinished groups, not files.

**Anyone with years of photos and clips on a disk:** drag the disk in, wait for the background scan, and tag only what you will look for again. Unplugging is fine; plug it back in and previous tags are still there. Removing a warehouse does not delete files.

**A first session:** drop one folder → click a few clips → add two hand tags → search for them. Add an AI key later if you want.

This version is a single-Mac tool. It does not finish a film, host a shared cloud library, or run on Windows / Linux.

### Install

Requires **macOS 14+**.

**Ready-made app:** the [Release](https://github.com/ticktock35/RollTag/releases) page itself has first-launch steps above the download button. Download `RollTag.zip`, unzip it (you will see `RollTag.app` and `第一次打開.txt`), and drag the app into **Applications**. A copy left in Downloads will not show up in Finder’s Applications list. If Gatekeeper blocks the first launch, right-click the app in Finder → **Open**. On macOS 26 the Apps / Gemini icon grids often hide unsigned local builds — use the grid search field, Finder → Applications, or the Dock.

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
./scripts/build.sh --install
```

That copies the app into Applications and opens it. Finder lists it there. On macOS 26 the old Launchpad is gone; the new Apps grid often hides ad-hoc (not notarized) builds, so use the grid’s search field, Finder → Applications, or drag `/Applications/RollTag.app` to the Dock. Use `--debug`, `--test`, or `--run` if you want. Or open `RollTag.xcodeproj` and press ⌘R — signing is already set to Sign to Run Locally, so you do not pick a Team.

### Use

1. Drop a footage folder or drive on the window, or press **⌘O**. Removing a warehouse only unregisters it; files on disk stay. Unplugged drives go offline until you plug them back in. Rescan with ⌘R.
2. Browse the sidebar lists and folders. Search and sort sit at the top of the right pane. The open-book icon at the far top-right opens the user guide. Click a clip and the main pane shows the original: video loads a player, photos are decoded to the screen. The grid stays on thumbnails. A video thumbnail shows a faint play mark when the pointer is off it. Rest there for 2 seconds and it plays in the tile; move away and it stops. The clip already open in the main player does not play again in its tile. Photos stay still. Audio does not play in the grid. Drag a tile to a browser, DaVinci Resolve, Photoshop, Terminal, or Finder and the other app gets the original path. Space plays, P toggles fullscreen, [ / ] moves to the previous / next item. ⌘/ lists shortcuts.
3. **Hand tags:** select one clip or a similar group, click a preset on the right, or type your own word and press Return. Click a tag to remove it.
4. **AI tags:** local AI is on by default and runs first. Frames stay on this Mac. Choose Apple Vision (built in), Florence-2 Base (about 370 MB), or RAM++ (about 2.8 GB) under `~/rolltag/models/`. If that model is missing or fails, RollTag can fall back to a [Gemini](https://aistudio.google.com/api-keys) or [OpenAI](https://platform.openai.com/api-keys) key. Import never runs AI by itself. Inspector / ⌥⌘T waits for Done or Cancel. Right-click **Untagged** or the grid for **AI Batch Tag**. Sidebar **Untagged** only sends files with no tags yet; to replace bad AI tags, select those clips and batch again. A batch of more than 10 files shows **Stop**. Files with GPS get a place name first. Folder names are hints only and are not written as tags. On-device Vision checks for a real person; empty scenes do not get portrait tags. Running AI again replaces previous AI tags and keeps hand tags. **AI tags can be wrong — review them.**
5. **Video files the Mac cannot decode:** WebM / MKV using VP8 or VP9 play through the system browser engine. AV1 does not. If ffmpeg from Homebrew is installed, RollTag makes an H.264 preview and plays that; the first time waits, later opens use the cached preview. Otherwise use **Open with default app**, or QuickTime, Preview, or another app. The grid context menu has the same action.
6. **Duplicates:** sidebar or ⌘⇧D. A / D keep one side, S keeps all, Enter sends the rest to Trash. **Trim** on a single video uses an in/out strip; pick a folder and filename, then the new clip is indexed in the background. **GPX:** import a track from the warehouse menu, then right-click a folder to apply it. Coordinates go into the warehouse index, not the original file.

Settings: `~/rolltag/config.json` (do not share). Place-name cache: `~/rolltag/geocode-cache.json`. Local models: `~/rolltag/models/`. Tags, thumbs, and imported GPX: `<warehouse>/.rolltag/`. AV1 previews: `~/Library/Caches/RollTag/av1-preview/`. Full contract: [SPEC.md](SPEC.md).
