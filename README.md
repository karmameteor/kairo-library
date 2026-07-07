# KairoMS Premium Library

Searchable item library generated from KairoMS server WZ XML and client Data files.

## What It Includes

- Search by item name, ID, description, type, or category
- A-Z item browser
- Type and category filters
- Hover/select item detail panel
- Item ID, description, client asset status, and server XML status
- Static GitHub Pages compatible build

## Run Locally

Double-click:

```text
launch-library.bat
```

Then open:

```text
http://127.0.0.1:8765/
```

## Publish On GitHub Pages

1. Create a new GitHub repository.
2. Upload everything in this folder to the repository root.
3. Go to repository **Settings**.
4. Go to **Pages**.
5. Under **Build and deployment**, choose **GitHub Actions**.
6. Push/upload the files.
7. GitHub will deploy the library automatically.

Your website will appear at a URL like:

```text
https://YOUR_USERNAME.github.io/YOUR_REPOSITORY/
```

## Refresh The Database After Future Imports

Run:

```powershell
& "C:\Users\DELL\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" "tools\generate_library.py"
```

Then commit/upload the updated:

```text
data/items.json
```

## Source Data

Generated from:

```text
C:\Users\DELL\Desktop\MapleRoot Full Repack\Server\wz
C:\Users\DELL\Desktop\KairoMS\Data
```
