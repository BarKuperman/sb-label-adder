# Subway Builder Label Adder: Complete User Guide

This tool adds OpenStreetMap labels for Cities, Suburbs, and Neighborhoods to a base `.pmtiles` map file for use in *Subway Builder*.

For Windows users, a graphical user interface (GUI) is provided. Command-line execution is also supported for both Windows and Linux environments.

---

## 1. Download the Tool

To use this tool, download the repository contents:

1. Go to the project's repository page.
2. Click the **Code** button.
3. Select **Download ZIP**.
4. Extract the ZIP file in your preferred directory (e.g., `C:\modding\label_adder\`).

*Note: The scripts and files must remain in the same folder to function correctly.*

---

## 2. Windows Set-Up & Prerequisites

*If you are running Linux natively, skip to Section 4.*

The map-generation engine runs on Linux. To use this tool on Windows, **WSL (Windows Subsystem for Linux)** must be installed.

> **Note:** If you do not have WSL installed and do not know what it is, it is recommended that you do not use this tool. This tool requires a functioning WSL environment to process the maps.

---

## 3. Running the App (Windows GUI)

Once WSL is configured, you can launch the GUI.

1. Open the folder where the tool was extracted.
2. Double-click **`GUI.bat`**.

### How to use the GUI:
*   **Base Map**: Click the **Browse...** button to select your unlabeled `.pmtiles` base map file.
*   **BBox (Optional)**: If you need to restrict the mapping data to a specific area, input a custom bounding box in the format `south,west,north,east`. In most cases, this can be left blank, and the script will automatically determine the bounds from the map file.
*   **Generate Map**: Click the generation button. A terminal window will appear, and the tool will download the OpenStreetMap data and merge it into a new file.

### Custom Setting Checkboxes:
These optional flags adjust how the labels are processed:

*   **`--prefer-english`**: Uses English text for labels where available on OpenStreetMap, falling back to local names if not.
*   **`--force-english`**: Strictly requires English labels. Any label without an English translation is ignored and removed. This can resolve in-game crashes caused by unsupported alphabets (such as Hebrew).
*   **`--san` (Combine suburbs into neighborhoods)**: OpenStreetMap physically separates "Suburbs" from "Neighborhoods." Check this box to merge them into a single `neighborhood_labels` layer. This is useful if the local terminology considers OpenStreetMap "suburbs" to be neighborhoods.

*(When the generation finishes, press any key to close the terminal.)*

---

## 4. Running the App (Linux Terminal)

If you are using Linux, execute the tool through the command line.

**Install the base requirements first:**
```bash
sudo apt update
sudo apt install -y python3 curl build-essential libsqlite3-dev zlib1g-dev git
```

**Run the generator:**
Navigate to the directory containing the scripts and execute the shell script, providing your base map path via the `--base-map` argument:

```bash
# Automatic bounding box detection
./build_labeled_map.sh --base-map /path/to/base_map.pmtiles

# Explicit bounding box definition
./build_labeled_map.sh \
  --base-map /path/to/base_map.pmtiles \
  --bbox "-38.22489374,144.444061,-37.48191108,145.55079102"
```

The flags `--prefer-english`, `--force-english`, and `--san` can be appended to the command line execution as needed.

---

## 5. Retrieve the Final Map

1. **One-Time Install Prompt**: On the first execution, you may be prompted: `tippecanoe/tile-join are not installed. Install now? [y/n]`. Type `y`, press Enter, and input your password to install the required map processing tools.
2. Once the operation completes, the generated map will be saved in the same directory as the original map, named **`final_map.pmtiles`**. 
3. *Previewing Output:* The script generates a `working_files/` subfolder next to your maps containing intermediate files. You can drag and drop the `labels_only.pmtiles` file from this folder into [https://pmtiles.io/](https://pmtiles.io/) in your web browser to preview the generated label layer before using the combined map in-game.

---

## Troubleshooting

### `Failed to infer bbox ... Pass --bbox manually`
**Cause**: The selected PMTiles map lacks a valid internal boundary definition.
**Fix**: Provide the `--bbox` argument manually (or via the BBox text box in the GUI) so the script targets the correct geographic area. The format must be comma-separated: `south,west,north,east` (e.g., `-38.22,144.44,-37.48,145.55`).

### Overpass API Timeouts or Errors
**Cause**: The OpenStreetMap API servers enforce rate limits and may occasionally time out on dense requests.
**Fix**: The script includes a retry mechanism with a fallback mirror. If requests continue to fail, wait a few minutes and try the generation process again.
