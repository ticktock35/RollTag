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
- Scanning runs in the background; progress shows on the warehouse row.
- Removing a warehouse only unregisters it. **Files on disk are not deleted.**
- Unplug a drive and it goes offline; search hides those clips until you plug it back in.
- Rescan online warehouses with ⌘R.

Expand a warehouse to see folders. Click one level, or pin several folders, so search, tagging, and duplicates stay in that scope.

## View photos {#photos}

- Click a photo: the left pane shows the original, decoded to fit the screen — not the grid thumbnail.
- The grid stays on thumbs; hovering a photo does not play it.
- Fullscreen (P by default) supports pinch-zoom; Z fits the frame. Two-finger pan after zoom can be reversed in Settings.
- [ and ] move to the previous / next item. In fullscreen you can also use , and .

Common still formats and camera RAW are supported (HEIC, JPEG, PNG, TIFF, AVIF, ARW, DNG, CR2, CR3, NEF, RAF, and more).

## Watch videos {#videos}

- Click a clip to see the first frame. Space or Play loads the player.
- Drag the timeline to scrub. While playing, ← → skip back / forward 5 seconds.
- Hold the mouse on the picture for 2× speed; release to return. If you have zoomed in, drag moves the frame instead.
- P while playing pauses, enters fullscreen, then resumes from the same time.
- Hover a grid tile to preview video or audio.
- With a single video selected, **Trim** on the right cuts a new file.

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

## Shortcuts {#shortcuts}

Common defaults (change them in Settings → Shortcuts; ⌘/ shows the full list):

- **Space**: play / pause
- **P**: fullscreen (again or Esc to leave)
- **[ / ]**: previous / next (in fullscreen also , / .)
- **Arrows or W A S D**: move to the neighboring tile (⇧ to extend the selection)
- **⌘A**: select all current results
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

## AI tagging {#ai}

**AI tags can be wrong** (place, mood, and keywords). People-count comes from on-device Vision; still review it. Import never runs AI by itself.

1. Settings → AI (⌘,) — paste a Gemini or OpenAI key. Keys live only in `~/rolltag/config.json` on this Mac. Do not share that file.
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

The same menu sets a **camera clock offset** (minutes) for that folder. A more specific child folder wins if you apply a different track there. You can stop applying GPX on a folder. Audio is skipped.
