# Brick by Brick

A native SwiftUI iPhone, iPad, and macOS app for finding LEGO sets you own and collecting their bricks before a rebuild. Requires iOS 17 or macOS 14 or later. No third-party dependencies.

## Why this exists

I built this so my kids and I can gather all the pieces for the LEGO sets we love building together. Instead of digging through a pile with a paper parts list, you pick a set, and the app turns it into a big, friendly **brick board**: large part pictures and large numbers showing how many of each piece are still to find. Kids tap **Found 1** as they pick each piece up, and the number counts down until the set is ready to build.

It is a personal, hobby project, shared in case it is useful to other families. Feel free to fork it and play around. See [License](#license).

## Run

1. Open `BrickByBrick.xcodeproj` in Xcode 16 or later.
2. Select the **BrickByBrick** scheme and an iPhone simulator, then Run (⌘R).
3. Open **Little brick house** to try the included practice checklist immediately.
4. For real LEGO sets, open **Settings**, follow the Rebrickable account/API-key links, paste your own key, and tap **Connect catalog**. The app verifies the key before saving it in the device Keychain.

For a physical iPhone, select your own Apple development team in the app target’s Signing & Capabilities settings (the project ships with the team left blank), choose your connected device, and Run. Signing and App Store distribution are not configured in this repository.

## Run on your MacBook Pro

Open `BrickByBrick.xcodeproj` in Xcode 16 or later, select the **BrickByBrick** scheme, choose **My Mac** as the run destination, and press **⌘R**. The macOS build uses local ad-hoc signing, so testing on your own Mac does not require an Apple Developer team.

Or build and launch from Terminal in this project folder:

```sh
./scripts/run-macos.sh
```

The app is built at `build/mac/Build/Products/Debug/BrickByBrick.app`. You can reopen that app directly after the first build. Run the script again after source changes.

Open **Little brick house**, then **Start finding bricks** to try the practice checklist without an API key. The native Mac window is resizable; the brick board adds columns as the window widens (up to six) and drops to one column in narrow windows. Quantity editing uses a desktop sheet; right-click a saved set to remove it. Open Settings with the gear on the Sets page or **⌘,**. The existing English/Danish language selection also applies on Mac.

Mac collection data stays in the app sandbox. Transfer sets and progress to iPhone or iPad manually through Settings → Transfer your collection; there is no automatic sync. Catalog access uses the same Rebrickable API key setup. This is a local development build; public distribution and notarization are not configured.

To run the Mac UI test (quantity editing, count/undo, two-column layout, relaunch persistence, and Settings):

```sh
xcodebuild -project BrickByBrick.xcodeproj -scheme BrickByBrick \
  -destination 'platform=macOS' test
```

The Mac UI test uses a separate `BrickByBrick/UITests/collection.json` in the sandbox and skips reading your catalog Keychain item, so it does not change your collection. Xcode may request permission to control the computer for UI testing.

Verified on macOS 26.7.1 with Xcode 27.2: native Mac build and UI test passed; the shared iOS Simulator build also passed. All 21 offline core tests currently pass (`swift test`). The two live API tests were skipped because no test API key was supplied. macOS 14 is the deployment minimum but was not separately runtime-tested.

## iPad

The same app target supports iPhone and iPad. On iPad, all four orientations are enabled. The checklist uses a child-friendly **brick board** with two columns in iPad portrait and three in iPad Pro landscape, large part pictures, and large numbers showing how many pieces are **still to find**. Tap **Found 1** for each piece, or the undo arrow to remove one. Completed cards stay in place, with the picture and a checkmark visible. A compact progress line leaves more room for bricks.

Search and filters slide open from **Search & filters**: a rounded search field, big **All bricks / Still missing / Found** buttons, and tappable color swatches instead of a color menu. Each card’s **…** menu contains quantity entry and bulk completion; the large remaining number is display-only. Quantity editing uses a resizable system sheet and preserves its value during rotation. The grid measures its container and uses one column on iPhone, in narrow iPad windows, and at accessibility text sizes. Set details and settings keep centered, readable widths.

Practice pieces have illustrations with the appropriate stud count and thickness, including a slope and a smooth tile. Real inventories use their catalog photos. If a photo cannot load, supported basic parts use the same shape-aware illustrations; other parts show an explicit unavailable-picture placeholder and part number instead of an unrelated brick.

Select an iPad simulator or a connected iPad in Xcode and run the **BrickByBrick** scheme. Progress is local to each device. Use Settings → Transfer your collection to move it between iPhone, iPad, and Mac manually.

## Transfer sets and progress with AirDrop

1. On the sending device, open **Settings → Transfer your collection → Export collection**.
2. Choose **Share collection… → AirDrop**, or **Save collection to file…** to keep a backup.
3. On the receiving device, open the `.brickbybrick` file in Brick by Brick. On Mac, AirDrop may save it to Downloads first. You can also choose **Settings → Import collection** and select the file.
4. Review the sets and export date. For sets already saved, the default is **Keep this device’s progress**. Choose **Use the file’s progress** to replace matching sets, including lower counts or resets. Unrelated sets remain saved. Real sets retire the practice set, as they do when added from the catalog.
5. Choose **Import**. Canceling the preview makes no changes.

Transfers are manual snapshots, not automatic sync or a merge of brick counts. The file includes inventories and checklist progress, but no Rebrickable API key, device preferences, or image files. Set up the API key separately on each device if you want catalog search. Imported inventories work offline; images can still require a connection.

Use AirDrop for a direct device-to-device transfer. The exported file itself is readable JSON and is not password-protected; storing it in a cloud folder follows that provider’s privacy settings. Temporary sharing copies are stored in the app’s temporary directory; copies older than a day are removed when another share is prepared. No iCloud entitlement or paid developer membership is needed for this feature. It can remain in a future TestFlight or App Store build (distribution requires Apple Developer Program membership).

The versioned format validates file size (25 MB maximum), unique set and part identifiers, quantities, progress, and catalog image hosts before importing. Failed validation leaves saved data untouched; imports use the same atomic save path as checklist edits.

## What it does

- One **Sets** page: your saved sets with progress, a search field to add another, and a gear button for Settings. There is no tab bar.

- Search the Rebrickable catalog by set name or number, with paginated results.
- Saved sets and their progress show on the Sets page below search. The practice set appears only while no real set has been added; adding a real set removes the practice set and its progress.
- Download every page of a set’s inventory before adding it to your sets.
- Show part images, names, part numbers, colors, and required quantities.
- Count down each part’s remaining quantity with **Found 1** and undo; use its options menu to enter a quantity or mark all found.
- Filter by missing/found parts, color (visual swatches), or a part name/number/element ID.
- Light and dark appearance; choose System default, Light, or Dark under **Settings → Appearance**.
- Include minifigure parts when available from Rebrickable; optionally display spare pieces without counting them toward completion.
- Export/import collections through AirDrop or files, with review and explicit handling of existing sets.
- Save inventories and progress locally with atomic writes. Reopening an existing set preserves its checklist.
- Reset a checklist or remove a saved set after confirmation.
- Display actionable connection, authentication, rate-limit, and persistence errors.

The bundled 32-piece practice inventory is an original example, **not an official LEGO set**. Real set data requires an internet connection and your Rebrickable key. Downloaded checklists work offline; remote images may need a connection. One checklist is saved per set number. There is no cloud sync or multiple-copy tracking.

## Structure

- `BrickByBrick/Core/`: Codable catalog models, quantity/progress rules, injectable API client, atomic JSON persistence. Also built as the `BrickCore` Swift package for tests.
- `BrickByBrick/AppStore.swift`: observable app state and Keychain storage; failed saves do not falsely update the UI.
- `BrickByBrick/Views/`: the Sets home page (saved sets plus catalog search), set details, checklist, and settings.
- `Tests/BrickCoreTests/`: unit/integration tests with simulated API responses; no credentials needed.
- `Config/Info.plist`: declares the `.brickbybrick` collection file type used for transfers.
- `scripts/run-macos.sh`: builds and launches the Mac app.
- `docs/`: screenshots, plus `docs/research/ldraw-rendering.md` and `docs/experiments/ldraw/`, an isolated, not-yet-integrated investigation into rendering accurate part pictures from the LDraw library (see its own README; it needs Node and is not part of the app build).
- `BrickByBrickUITests/`: simulator tests covering countdowns, completion, undo, relaunch persistence, missing/found filters, accessibility text sizes, and iPad portrait/landscape layouts with quantity editing across rotation.

## Verification

```sh
swift test
xcodebuild -project BrickByBrick.xcodeproj -scheme BrickByBrick \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project BrickByBrick.xcodeproj -scheme BrickByBrick \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' test
```

Choose an available simulator name from `xcrun simctl list devices available` if yours differs. API tests use injected HTTP responses. A live authenticated catalog request requires your own key and is not part of the automated tests.

Brick board verification on iOS/iPadOS 26.5 simulators (a point-in-time record; the core suite has since grown to 21 tests): The iPad-only rotation test is skipped on iPhone.

| Device | Passed checks |
| --- | --- |
| iPad Pro 11-inch (M5) | Two columns in portrait and landscape, quantity editing across rotation, countdown, completion without moving the card, undo, reset, filters, relaunch persistence, and largest accessibility text |
| iPad mini (A17 Pro) | Two columns in portrait and landscape, quantity editing across rotation, countdown, completion, undo, reset, filters, relaunch persistence, and largest accessibility text |
| iPhone 17 Pro | Single-column board, countdown, completion, undo, reset, filters, relaunch persistence, and largest accessibility text |

Verified board screenshots are saved in `docs/screenshots/brick-board/`; the previous interface screenshots remain in `docs/screenshots/ipad/`. These checks use the bundled practice set; authenticated live catalog access still requires your own API key. Physical-device and Stage Manager window-resizing tests have not been run.

## Catalog and privacy

Catalog requests use the [Rebrickable v3 API](https://rebrickable.com/api/v3/docs/), including `lego/sets/` search and `lego/sets/{set_num}/parts/` with `inc_minifig_parts=1`. An API key is required by [Rebrickable](https://rebrickable.com/api/). Pagination URLs are checked before forwarding credentials. Keys are not embedded in the source or stored with checklist files.

Collection data lives in the app sandbox’s `Application Support/BrickByBrick/collection.json`. The app does not send checklist progress to a server and has no analytics. On iOS, uninstalling the app removes its local collection. On macOS, collection data is stored under `~/Library/Containers/com.brickbybrick.app/Data/Library/Application Support/BrickByBrick/`; deleting only the `.app` can leave this data behind. The app uses system networking for catalog and image requests.

Set and part data/images are provided by Rebrickable. This app is independent and is not endorsed by the LEGO Group or Rebrickable. LEGO is a trademark of the LEGO Group.

## License

Released under the [MIT License](LICENSE). You are welcome to fork, modify, and build on this project, and I would love some attribution if you do: the license requires keeping the copyright notice, and a link back to this repository (for example in your README or an About screen) is much appreciated.

Third-party material keeps its own terms: LDraw part geometry in `docs/experiments/ldraw/library/` is © its contributors under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (see that folder’s `CREDITS.md`). LEGO is a trademark of the LEGO Group, which does not sponsor or endorse this project. Rebrickable data requires following [Rebrickable’s terms](https://rebrickable.com/api/).
