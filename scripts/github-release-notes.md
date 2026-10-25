## What's New in RollTag 1.0.2 / 這次改了什麼

### 格線裡看影片

- 影片縮圖滑鼠不在上面時，中間有半透明播放圖示，一看就知道是影片。
- 停超過 2 秒會在格子裡播，移開就停。
- 主播放區正在看的那支，縮圖不再跟著滑鼠播。
- 畫面出來才疊上去，不會先黑一下，也不會把視窗卡住。

### WebM、MKV

- VP8、VP9 用系統瀏覽器引擎播。
- AV1 這台 Mac 解不開。有裝 ffmpeg（Homebrew）會先做成預覽再播，第一次要等一下，做完留在這台 Mac，下次直接播。
- 檔不在，跟這裡播不了，會分開講。播不了可以交給預設 App、QuickTime、預覽，或自己挑一個。格線右鍵也有。

### 拖到別的 App

- 格子可拖到瀏覽器、DaVinci、Photoshop、Terminal、Finder。
- 送出的是硬碟上的原檔路徑，不是複本。
- 已選很多支時，從選取裡拖，會一次帶上找得到的原檔。

### 側欄

- 倉庫標題旁邊加了 ＋。
- 最下面的「加入倉庫」不再跟清單疊在一起。

### In the grid

- A video thumbnail shows a faint play mark when the pointer is off it.
- Rest there for 2 seconds and it plays in the tile. Move away and it stops.
- The clip already open in the main player does not play again in its tile.
- The picture appears when the frame is ready, so the tile does not flash black and the window does not hang.

### WebM and MKV

- VP8 and VP9 play through the system browser engine.
- This Mac cannot decode AV1. If ffmpeg from Homebrew is installed, RollTag makes a preview and plays that. The first time waits. Finished previews stay on this Mac.
- A missing file and a file that will not play are shown separately. If it will not play, open it in the default app, QuickTime, Preview, or another app. The grid context menu has the same action.

### Drag out

- Drag a tile to a browser, DaVinci, Photoshop, Terminal, or Finder.
- The other app receives the original file path, not a copy.
- If that tile is already selected, the drag includes every selected file that is still on disk.

### Sidebar

- A ＋ sits beside the Warehouses heading.
- Add Warehouse at the bottom no longer overlaps the list.

---

### 第一次打開

第一次從網路上打開時，macOS 常會擋下（本機簽章、尚未公證）。

1. 下載下面的 `RollTag.zip`，解開。
2. 把 `RollTag.app` 拖進「應用程式」（Applications）。
3. 在 Finder 對 RollTag **按右鍵 → 打開**，再按一次「打開」。不要只按兩下。

解開後同一層也有「第一次打開.txt」，步驟寫在裡面。

---

### First launch

The first launch after download is often blocked (local signature, not notarized).

1. Download `RollTag.zip` below and unzip it.
2. Drag `RollTag.app` into **Applications**.
3. In Finder, **right-click → Open**, then click Open again. Do not only double-click.

The unzipped folder also has `第一次打開.txt` with the same steps.
