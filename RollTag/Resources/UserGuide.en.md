# User Guide

## Getting started {#start}

RollTag lets you browse photos and videos on your own disks, tag them, and search. Files stay where they are; nothing is imported into a private library.

A first session:

1. Drop a folder of photos or clips on the window (or press ⌘O).
2. Wait for the sidebar scan, then click a tile to view it.
3. Tag a few clips on the right, then search for those words in the top search field.

You do not need an API key to add a warehouse, preview, hand-tag, search, trim, or find duplicates.

## Add a warehouse {#warehouse}

A warehouse is a footage folder or an external drive.

- **Drop the folder on the window**, choose **File → Add Warehouse** (⌘O), or use ＋ at the bottom of the sidebar.
- Scanning runs in the background; progress shows on the warehouse row. Building the initial database index takes time on large drives, but you can browse files immediately as they appear.
- Removing a warehouse only unregisters it. **Files on disk are not deleted.**
- Unplug a drive and it goes offline; search hides those clips until you plug it back in.
- Rescan online warehouses with ⌘R.

Expand a warehouse to see folders. Click one level, or pin several folders, so search, tagging, and duplicates stay in that scope.

## View photos {#photos}

- Click a photo: the left pane shows the original, decoded to fit the screen — not the grid thumbnail.
- The grid stays on thumbs; hovering a photo does not play it.
- Drag a tile to a browser, DaVinci Resolve, Photoshop, Terminal, or Finder. RollTag sends the full path so the other app opens the original file. If that tile is already selected, the drag includes every selected file that is online and still on disk.
- Fullscreen (P by default) supports pinch-zoom; Z fits the frame. Two-finger pan after zoom can be reversed in Settings.
- [ and ] move to the previous / next item. In fullscreen you can also use , and .

Common still formats and camera RAW are supported (HEIC, JPEG, PNG, TIFF, AVIF, ARW, DNG, CR2, CR3, NEF, RAF, and more).

## Watch videos {#videos}

- A video thumbnail shows a faint play mark when the pointer is off it. Rest there for 2 seconds and it plays in the tile; move away and it stops. The clip already open in the main player does not play again in its tile. Photos stay still. Audio does not play in the grid; select it to hear it in the player.
- Click a clip to see the first frame. Space or Play loads the player. WebM / MKV using VP8 or VP9 play through the system browser engine. AV1 can't be decoded on this Mac; if ffmpeg from Homebrew is installed, RollTag makes a preview and plays that. The first time takes a moment. Finished previews stay on this Mac and open directly next time.
- Drag the timeline to scrub. While playing, ← → skip back / forward 5 seconds.
- Hold the mouse on the picture for 2× speed; release to return. If you have zoomed in, drag moves the frame instead.
- P while playing pauses, enters fullscreen, then resumes from the same time.
- Video and audio tiles drag the same way: the other app receives the original file path.
- With a single video selected, **Trim** on the right cuts a new file.
- If the player says the file is not on disk, it may have been renamed, moved, or replaced by a `_beauty` copy. Tags stay in the library.
- If the player cannot play a file that is still there, use **Open with default app**, or **Other apps** for QuickTime, Preview, or a picker. The grid context menu has the same action.
- With two or more displays, **Window → Dual Screen** puts the player and tagging inspector on the primary display, and keeps search plus the media list on the other. **Primary Display** chooses which screen is primary. Closing the player window leaves dual-screen mode.

## Duplicates {#duplicates}

If the same photo or video exists more than once (RAW + JPEG, a copied folder, a second backup drive), RollTag groups them by content. The sidebar **Duplicates** badge is the number of groups you have not finished yet.

1. Click **Duplicates** in the sidebar, or press **⌘⇧D**.
2. Compare side by side: folder, warehouse, and an independent player on each side.
3. For each group, choose what to keep. Defaults:

- **A**: keep the left file
- **D**: keep the right file
- **S**: keep all in this group (treat them as separate)
- **Enter**: confirm — the others go to Trash
- **P**: fullscreen the selected side, then the same key or Esc returns to the comparison

If you pin folders first, only groups with at least one file in that scope are listed. The comparison still shows every copy in the group.

Trash only receives the copies you did not keep. Check the keeper before you confirm. Groups you skip stay in the list.

## Retouch review {#retouch}

An export from Lightroom or a phone editor often looks like an earlier photo, but the clock is hours later and GPS is gone. **Retouch review** sits under Duplicates in Library. The badge is how many pairs you have not looked at yet.

1. Open **Retouch review**. The original is on the left, the likely export on the right, with time and place under each.
2. If it is a retouch, click **It's a retouch**: the warehouse copies the original’s capture time and GPS, and tags it Retouch. Original files are not changed.
3. If it is not the same shot, click **Not a retouch**. That pair leaves the list.

Pinned folders limit the list to pairs that touch those directories.

## Shortcuts {#shortcuts}

Common defaults (change them in Settings → Shortcuts; ⌘/ shows the full list):

- **Space**: play / pause
- **P**: fullscreen (again or Esc to leave)
- **[ / ]**: previous / next (in fullscreen also , / .)
- **Arrows or W A S D**: move to the neighboring tile (⇧ to extend the selection). Same keys in single- and dual-screen; they also work when the player window is in front
- **⌘A**: select all items in the current list (click a tile first; in the search field it still selects the text). Same when the dual-screen player window is in front
- **⌘+ / ⌘-**: larger / smaller font (also in Settings → Display)
- **⌘O**: add a warehouse
- **⌘R**: rescan
- **⌥⌘T**: AI-tag the selected video / photo
- **⌘⇧D**: duplicates
- **⌘,**: Settings
- **⌘/**: shortcut list

Help and View menus also open the shortcut list.

## Search tags {#search}

The search field at the top of the right pane only looks in **online, readable** warehouses.

- Search tags, filenames, folder names, and notes.
- Non-English words also match their English keywords (for example 海 also finds ocean).
- Add names and brands in Settings → Glossary.
- Click **Tagged** or a category (mood, place, custom, …) to see only clips that have that group.
- Pin folders first if you want the search limited to those directories.
- Drag matching tiles straight into your editor; you do not have to reveal them in Finder first.

## AI tagging {#ai}

**AI tags can be wrong** (place, mood, and keywords). People-count comes from on-device Vision; still review it. Import never runs AI by itself.

1. Settings → AI (⌘,) — **Local AI** is the switch at the top (on by default, tried first). **Advantage: private** — frames stay on this Mac and are not sent to Google or OpenAI. Choose between Apple Vision (native, 0 disk space), MS Florence-2 Base (~370 MB), or RAM++ (~2.8 GB). Florence-2 and RAM++ can be downloaded or deleted in Settings, or downloaded directly on first tag via the confirmation prompt (with options to download, switch to Apple Vision, or use cloud fallback). Optionally paste a Gemini or OpenAI key as fallback. Keys live only in `~/rolltag/config.json` on this Mac. Do not share that file.
2. Select a **video or photo** (already tagged clips can be sent again). Audio, tiny, or unreadable files are skipped.
3. Click **AI Tag** on the right or press **⌥⌘T**. Then **Done** / Return to keep, or **Cancel** / Esc to drop this pass.

Running AI again replaces the previous AI tags and keeps hand tags. Files with GPS get a place name written as tags first.

## Batch tagging {#batch}

Right-click sidebar **Untagged** or the grid → **AI Batch Tag**. Clips are sent one by one and **kept immediately** — no confirm step — so check them afterwards.

- Sidebar Untagged batch: only files that **still have no tags**.
- To replace bad AI tags, select those clips in the grid and batch again.
- More than 10 files: **Stop** leaves what is already tagged and does not send the rest.

Later clips in a large batch may fail on quota even when the files are fine. Wait a few minutes and retry what is still untagged.

## Import and apply GPX {#gpx}

If a photo or video has no GPS in its header, you can fill coordinates from a GPX track (watch or phone). Coordinates go into the warehouse only. **Original files are not changed.**

1. Connect an online warehouse. **Warehouse → Import GPX…**, or right-click the warehouse / a folder. Choose a `.gpx` file.
2. The sidebar **GPX** section lists the imported track. Import does not write coordinates yet.
3. Right-click the warehouse root or a folder → **Apply GPX** and pick a track.
4. Photos and videos in that folder (and below) whose capture time falls in the track span appear under that GPX item.
5. Files with no GPS get interpolated coordinates. Header GPS is not overwritten, but those files can still appear in the list.

Right-click a warehouse or folder → **Fill in time offset…** to set years, days, hours, minutes, and seconds (plus or minus; default is zero). That difference is added to capture times in the folder before matching GPS or an itinerary. A more specific child folder wins if you apply a different track there. You can stop applying GPX on a folder. Audio is skipped.

## Itineraries and the map {#itinerary}

**Itineraries** sit under Warehouses in the sidebar. Right-click a warehouse or folder:

1. **Bring in GPX file…** copies a `.gpx` and fills missing photo/video coordinates from capture time. Header GPS is left alone. The new itinerary opens a map in the player pane.
2. **Create itinerary from timeline and GPS** groups GPS clips into stays. Clips without GPS show up in the list. If the time sits in a stay, confirm “Was this taken here?” If it sits between two stays, look at the earlier or later stay on the map first, then confirm, or mark a place on the way.

The first time you open an itinerary, the map fits every clip with a place (including a guessed place from the timeline or GPX). After that, pan and zoom are remembered; leave and come back, and you get the same view.

Pins are navy drops. Zoomed out, overlapping clips merge into a count; click the number to zoom in and split. At street scale the counts go away: each clip is its own pin with a filename. Shots stacked on the same table are fanned out so you can tell them apart. The selected pin shows a callout with a thumbnail. Dashed lines follow shooting time: straight on land, curved over sea. A jump that covers an impossible distance in a second or two is ignored.

Clips without GPS are matched to a stay. A restaurant video stays at the restaurant; it is not pulled to Sapporo just because the evening has GPS there. DJI filenames without a time zone are aligned to GPS photos from that day. An export that looks like an earlier photo, but is hours later and has no GPS, can copy that photo’s time and place when you confirm, and is tagged Retouch. Original files are not changed. A file that only has 0,0 is treated as having no GPS.

Right-click an itinerary in the sidebar to **Rename**. Click a clip to focus it. Coordinates are stored in the warehouse only. Original files are not changed.
