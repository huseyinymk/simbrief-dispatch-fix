# SimBrief Dispatch Sign-In Fix

A small, reversible fix for Navigraph's **SimBrief Dispatch for MSFS** add-on, for when the in-sim panel **never signs in**. The whole fix is one PowerShell script with a menu, plus a one-line launcher.

**Symptoms**

- You click **SIGN IN** in the SimBrief Dispatch panel and get a code.
- You approve the code on navigraph.com/code or with the QR code. The website says the device is connected, and the add-on shows up under your Navigraph account's devices.
- The panel in the simulator keeps showing the code forever. Reinstalling the simulator or the add-on does not help.
- If you disconnect from the internet, the panel reports errors for sign-in requests that were apparently still waiting in the background.

If that is your problem, this fix makes the sign-in complete within a few seconds of approving the code.

## How to use

1. Close Microsoft Flight Simulator completely.
2. Download this repository (**Code > Download ZIP**) and extract it. Keep both files in the same folder.
3. Double-click **`Run-SignInFix.cmd`**. If Windows SmartScreen warns you, choose **More info > Run anyway**.
4. Type **1** and press Enter to apply the patch.
5. Start the simulator, open SimBrief Dispatch and sign in again.

```
  ================================================
    SimBrief Dispatch Sign-In Fix
    Developed by huseyinymk
    Version 1.1.0
  ================================================

  Simulator : MSFS 2020 (Microsoft Store / Xbox app)
  Add-on    : C:\Users\...\Community\navigraph-simbrief-dispatch-2020
  Version   : 1.3.2
  Status    : Not patched

  1- Apply Patch
  2- Revert Patch
  3- Select add-on folder manually
  4- Exit

  Select an option:
```

**Apply Patch** backs up the files it changes to `Documents\SimBriefDispatchFix-Backups` and then patches them. Applying twice is harmless: the script sees that the add-on is already patched.

**Revert Patch** puts the original files back from that backup. Reinstalling the add-on with Navigraph Hub also removes the patch.

**After Navigraph updates the add-on**, the update replaces the patched file. Run the script again and choose **1**.

### Why the `.cmd` file?

Current Windows 11 builds start `.ps1` files from **right-click > Run with PowerShell** without lifting the default script restriction, so the script is stopped with *"running scripts is disabled on this system"* before it can even start. `Run-SignInFix.cmd` starts the same script with that restriction lifted for this one run. It changes no Windows setting.

If you prefer, you can also start the script yourself from a PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1
```

## Where the script looks for the add-on

The script reads each simulator's own settings file, `UserCfg.opt`, to find its Community folder. That also covers Community folders moved to another drive. If a settings file is missing, it checks the default package folder of that edition.

| Simulator | Settings file | Status |
|---|---|---|
| MSFS 2020, Microsoft Store / Xbox app | `%LOCALAPPDATA%\Packages\Microsoft.FlightSimulator_8wekyb3d8bbwe\LocalCache\UserCfg.opt` | Tested |
| MSFS 2020, Steam | `%APPDATA%\Microsoft Flight Simulator\UserCfg.opt` | Detected, not tested |
| MSFS 2024, Microsoft Store / Xbox app | `%LOCALAPPDATA%\Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalCache\UserCfg.opt` | Detected, not tested |
| MSFS 2024, Steam | `%APPDATA%\Microsoft Flight Simulator 2024\UserCfg.opt` | Detected, not tested |

For MSFS 2024, the script only finds the MSFS 2020 version of the add-on (`navigraph-simbrief-dispatch-2020`) if it is installed in the 2024 Community folder.

**If the add-on is not found**, for example with another edition or an unusual setup, the script opens a file window and asks you to select **`manifest.json`** inside the `navigraph-simbrief-dispatch-2020` folder. You can also do this at any time with menu option **3**. The script remembers your choice for the next time. If no window can be opened, it asks you to paste the folder path instead.

### Command line

The script can also run without the menu:

```powershell
# Apply, revert, or only show the status
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1 -Action Apply
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1 -Action Revert
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1 -Action Status

# Point it at the add-on yourself (the folder, or any file inside it)
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1 -PackagePath "D:\MSFS\Community\navigraph-simbrief-dispatch-2020"

# Keep backups somewhere else (use the same value when reverting)
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1 -BackupRoot "D:\Backups"

# Ask for the add-on location in the console instead of opening a file window
powershell -ExecutionPolicy Bypass -File .\SimBriefDispatch-SignInFix.ps1 -NoDialog
```

## Tested with

| Component | Version |
|---|---|
| Microsoft Flight Simulator 2020 | 1.39.12.0, Microsoft Store edition |
| SimBrief Dispatch for MSFS | 1.3.2, package `navigraph-simbrief-dispatch-2020` |
| Windows | Windows 11 |
| PowerShell | Windows PowerShell 5.1 and PowerShell 7 |

## What goes wrong

The panel keeps your Navigraph login tokens in a small WebAssembly module that ships with the add-on (`modules/simbrief_igp_datastore.wasm`). The panel talks to it over the simulator's CommBus, and the module is supposed to save the tokens to a file in its `work` folder.

On affected PCs that module never answers. Its `work` folder stays empty, and every read from the panel times out after five seconds and returns nothing.

That breaks sign-in in a way that is easy to miss:

1. When the Navigraph SDK starts, it takes a small lock by writing a value to that store and reading it back.
2. The read-back comes back empty, so the SDK's start-up never finishes.
3. The listener that switches the panel to "signed in" is only attached after that start-up.
4. The actual sign-in with Navigraph succeeds, but nobody is listening, so the panel stays on the code screen.

It was observed on a PC whose Windows user folder name contains non-ASCII characters, such as accented letters. That is the suspected trigger, but it has not been proven.

## What the patch changes

The script edits exactly three files inside your installed add-on:

| File | Change |
|---|---|
| `html_ui/Pages/Navigraph/SimBrief/index.js` | One statement: the token storage adapter |
| `layout.json` | Size and date of `index.js`, so the simulator loads the new file correctly |
| `manifest.json` | `total_package_size` |

The new storage adapter uses the simulator's built-in DataStorage API (`GetStoredData` / `SetStoredData`), which many in-sim panels use. Values are stored in 500-character chunks under keys starting with `NG_SBD_STORE.`, and an in-memory copy acts as a fallback. Written out readably, it does this:

```js
const CHUNK = 500;
const memory = new Map();
const key = (name) => "NG_SBD_STORE." + name;

function read(name) {
  const k = key(name);
  try {
    const n = parseInt(GetStoredData(k + ".n") || "0", 10) || 0;
    if (n > 0) {
      let value = "";
      for (let i = 0; i < n; i++) value += GetStoredData(k + "." + i) || "";
      return value;
    }
  } catch (e) { console.error("[NG-SBD-STORE] read error:", e); }
  return memory.has(k) ? memory.get(k) : null;
}

function write(name, value) {
  const k = key(name);
  const v = value == null ? "" : String(value);
  memory.set(k, v);
  try {
    const n = Math.ceil(v.length / CHUNK);
    for (let i = 0; i < n; i++) SetStoredData(k + "." + i, v.slice(i * CHUNK, (i + 1) * CHUNK));
    SetStoredData(k + ".n", String(n));
  } catch (e) { console.error("[NG-SBD-STORE] write error:", e); }
}

const storage = {
  getItem: (name) => Promise.resolve(read(name)),
  setItem: (name, value) => Promise.resolve(write(name, value)),
};
```

The script finds the statement to replace by its structure, not by the minified variable names, so it keeps working if a rebuild of the same version renames them. If it cannot find the statement exactly once, it changes nothing and tells you so. After patching it checks the result, and if anything looks wrong it restores the backup on its own.

## Privacy and safety

- The script makes no network connections.
- Your tokens stay on your PC, in the simulator's local data storage. The original add-on also stored them locally.
- This repository contains **no Navigraph code**. The script edits the copy of the add-on that is already installed on your computer.

## Known limitations

- A Navigraph Hub update of the add-on removes the patch. Apply it again after updating.
- Navigraph has said that the simulator's data storage occasionally loses data. If the panel asks you to sign in again one day, just sign in again.
- Only version 1.3.2 in MSFS 2020 from the Microsoft Store has been tested. Other versions are patched only if the code matches exactly.

## Something else to try

On the PC where this was found, turning on Windows' **"Beta: Use Unicode UTF-8 for worldwide language support"** fixed other simulator problems caused by the non-ASCII user folder. It is under Settings > Time & language > Language & region > Administrative language settings > Change system locale, and needs a restart. It has not been tested against this particular bug.

## Disclaimer

This project is not affiliated with or endorsed by Navigraph. Navigraph and SimBrief are trademarks of Navigraph. Use this fix at your own risk. If you have this problem, please also report it to Navigraph on the [Dispatch for MSFS forum](https://forum.navigraph.com/c/simbrief/dispatch-for-msfs/63) so it can be fixed properly in the add-on.

## License

Copyright (C) 2026 huseyinymk

This project is licensed under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later). See [LICENSE](LICENSE) or the [official license text](https://www.gnu.org/licenses/gpl-3.0.html).

In short: you may use, study, change and share this project. If you share a changed version, you must share it under the same license, with its source code, so it stays open source.

The license covers only the files in this repository. It does not cover Navigraph's SimBrief Dispatch add-on, which the script edits on your own computer and which remains the property of Navigraph.
