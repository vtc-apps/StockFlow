# VTC StockFlow

A static web app for recording goods received at each branch, where they are dispatched or transferred next, and how much stock remains — product by product, branch by branch. It runs entirely in the browser and deploys to **GitHub Pages** with no server.

---

## ⚠️ Read first: where the data is stored

This version stores records in the **browser's local storage** on the computer that is using it.

- Data survives page refreshes and browser restarts **on the same browser and device**.
- It is **not** a shared database. Opening the site on another computer, another browser, or in a private window shows an empty workspace.
- Clearing browser data ("cookies and site data") erases the records.
- GitHub Pages only hosts the app files; it never receives your data.

**Protect your data:** download a JSON backup from *Backup & Restore* regularly. To move to a new computer, download a backup on the old one and restore it on the new one.

If several branches need to enter data into one live, shared database, see [Adding a cloud database](#adding-a-cloud-database-later).

---

## Sign-in

The app opens on a sign-in screen.

- **Username:** `Vtc2026`
- **Password:** `Vtc@2026@123`

Only a SHA-256 hash of the credentials is in the code (`src/auth.js`), never the password itself. Five wrong attempts pause sign-in for 30 seconds. "Keep me signed in" lasts 7 days on that device; otherwise the session ends when the tab closes. Use **Sign out** in the top bar on shared computers.

This is a front-door lock for a static site, not server security: someone with technical skill and access to the computer could still read the browser's stored data. For real per-user accounts, add a backend such as Supabase Auth (see below).

To change the credentials, compute the new hash and replace `CRED_HASH` in `src/auth.js`:

```bash
node -e "console.log(require('crypto').createHash('sha256').update('NEWUSER\nNEWPASSWORD').digest('hex'))"
```

## Features

| Area | What it does |
|---|---|
| Dashboard | Products tracked, total received / dispatched, available stock, branches, today's entries, stock alerts, monthly inward vs dispatch chart, branch-wise and product-wise stock, recent activity. Date and branch filters. |
| Product Inward | Auto-generated ID, DD-MM-YYYY date, searchable product (add a new product inline), branch, quantity, supplier, invoice/challan, remarks. Also records **opening stock**. |
| Product Dispatch | Live "available at this branch on this date" check; dispatch types: branch transfer, employee/person, customer, other. Over-dispatch is blocked. |
| Branch Transfers | Moves stock from one branch to another; has its own Transfer Register. |
| Inventory & Stock | Every product × branch with received, dispatched, available, last transaction, status (in / low / out). Filters by product, branch, date range, status. |
| Registers | Inward, Dispatch, Branch Transfer, Complete Transaction History — search, date range, product & branch filters, sorting, pagination, view and edit (every edit is logged), CSV export, print. Newest first. Nothing can be deleted. |
| Product Movement History | Timeline for one product: where it arrived, where it went, references and remarks, and the stock left at each branch and in total after every step. Branch view shows everything that entered and left a branch. |
| Products / Branches | Master records feeding every dropdown. Products can be archived and branches made inactive; neither can be deleted. Edits are logged. |
| Reports & Analytics | Daily / monthly inward and dispatch, product-wise and branch-wise stock, product movement (opening → closing), date-range listing, totals, branch transfer summary. Charts, tables, CSV, print. |
| Backup & Restore | Full JSON backup (includes the change log); restore with a preview that shows new / duplicate / conflicting records. Restore only **adds** missing records — it never overwrites or removes anything. CSV exports for every register. |
| Change Log | Locked, append-only audit trail: every edit to an entry, product, branch or setting with date, time, user, field, old value and new value. Search, filter, CSV, print. Also shown as "Edit history" on each record. |
| Settings | Organisation name, logo, default low-stock threshold, light / dark theme, storage usage. |

### Stock rules (enforced in `src/data/ledger.js`)

```
Available = Opening + Inward + Transfers in − Dispatches − Transfers out
```

- Calculated separately for every product at every branch, always from the stored transactions (never stored as a number that could drift).
- Transactions are replayed in date order, so a **back-dated** dispatch is checked against the stock that existed on that date.
- Any save, edit or import that would make **any** balance negative at **any** point in time is rejected with a clear message.
- **No deletes.** The data service has no delete operations at all. Mistakes are corrected by editing, and each edit is written to the change log (`state.changeLog`) with old and new values.
- Every transaction has a unique ID like `INW-261029-K7Q2` (type – date – random code). The random part means backups from two computers can be merged without ID clashes.

---

## Run it on your computer

Requirements: [Node.js](https://nodejs.org) 18 or newer.

```bash
npm install
npm run dev        # opens http://localhost:5173
```

Other commands:

```bash
npm test           # stock-engine tests (Node's built-in test runner)
npm run build      # production build into dist/
npm run preview    # serve the production build at http://localhost:4173
```

Optional browser test of the ten acceptance scenarios (needs Python):

```bash
pip install playwright && playwright install chromium
npm run build && npx vite preview --port 4173 &
python tests/e2e_scenarios.py http://localhost:4173
```

---

## Deploy to GitHub Pages

### Option A — GitHub Actions (recommended)

1. Create a new repository on GitHub (e.g. `inventory-tracker`) and push this folder to the `main` branch:
   ```bash
   git init
   git add .
   git commit -m "StockFlow inventory tracker"
   git branch -M main
   git remote add origin https://github.com/<your-user>/inventory-tracker.git
   git push -u origin main
   ```
2. On GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. The workflow in `.github/workflows/deploy.yml` runs tests, builds, and publishes. After a minute or two the site is live at
   `https://<your-user>.github.io/inventory-tracker/`.
4. Every later push to `main` redeploys automatically.

### Option B — one command from your computer

```bash
npm run deploy
```

This builds and pushes `dist/` to a `gh-pages` branch. Then set **Settings → Pages → Source: Deploy from a branch → `gh-pages` / root**.

### About the base path

The app uses hash routing (`/#/inventory`), and `vite.config.js` sets `base: './'`, so assets load correctly from any project sub-path (`/<repo-name>/`) without changes and page refreshes never 404. If you prefer an absolute base, build with:

```bash
VITE_BASE=/inventory-tracker/ npm run build
```

---

## First-time setup in the app

1. Sign in, then **Branches** → add each warehouse / store (two or more for transfers).
2. **Products** → add products with SKU, unit and optional minimum stock (or add them on the fly from the Inward form).
3. If branches already hold stock, record it once with **Product Inward → Opening stock**.
4. Record inward entries and dispatches as goods move.
5. **Backup & Restore → Download backup** at the end of each day or week.

To correct a wrong entry, open it from any register and choose **Edit**; the change appears in the **Change Log**.

---

## Project structure

```
├── index.html
├── vite.config.js               # base path for GitHub Pages
├── .github/workflows/deploy.yml # build + deploy on push
├── public/                      # favicon, .nojekyll
├── src/
│   ├── main.jsx                 # creates the store with the storage adapter
│   ├── App.jsx                  # hash routes
│   ├── context.jsx              # store hooks, toasts, confirm dialog, router
│   ├── data/
│   │   ├── models.js            # record shapes, constants, ID generation
│   │   ├── ledger.js            # stock engine (pure functions)
│   │   ├── validation.js        # field validation
│   │   ├── store.js             # data service: every read/write goes through here
│   │   ├── storage.js           # storage adapters (localStorage, memory)
│   │   ├── selectors.js         # dashboard / inventory / report calculations
│   │   ├── exporters.js         # CSV + file download helpers
│   │   └── dates.js             # DD-MM-YYYY formatting
│   ├── components/              # layout, forms, registers, charts, UI kit
│   ├── pages/                   # one file per screen group
│   └── styles/app.css           # theme tokens, glass UI, 3D effects, print styles
└── tests/
    ├── stock.test.js            # engine + store tests (npm test)
    └── e2e_scenarios.py         # browser test of the 10 acceptance scenarios
```

### Data model

All stock movements live in one `transactions` list:

| Field | Notes |
|---|---|
| `id` | `OPN-` / `INW-` / `DSP-` / `TRF-` + `YYMMDD` + random code |
| `type` | `opening`, `inward` or `dispatch` |
| `dispatchType` | `branch_transfer`, `person`, `customer`, `other` (dispatch only) |
| `date` | ISO `YYYY-MM-DD` (shown as DD-MM-YYYY) |
| `productId`, `branchId` | links to masters |
| `destinationBranchId` | branch transfers only |
| `quantity` | positive number |
| `receivedFrom`, `dispatchedTo`, `reference`, `remarks` | text |
| `createdAt`, `updatedAt`, `isDemo` | metadata |

Products: `id, name, sku, category, unit, minStock, description, archived`. Branches: `id, name, code, location, contactPerson, contactDetails, active`.

---

## Adding a cloud database later

The UI never touches `localStorage` directly. `src/data/storage.js` defines a small adapter interface (`load`, `save`, `loadPrefs`, `savePrefs`, `onExternalChange`, `saveSnapshot`, `loadSnapshot`), and `src/main.jsx` picks the adapter:

```js
const store = createStore(createLocalStorageAdapter());
```

To share live data between branches (for example with [Supabase](https://supabase.com)):

1. Create tables `products`, `branches`, `transactions` matching the data model above, with Row Level Security and a login for each staff member.
2. Write `createSupabaseAdapter()` implementing the same methods (load all rows on start, write changes, subscribe to realtime changes in `onExternalChange`).
3. Keep the stock validation on the server too (a Postgres function or check), because several people may save at the same moment.
4. Swap the adapter in `main.jsx`, then import your latest JSON backup to seed the database.

Use the Supabase *anon* key only (never the service key) in a static site, and rely on Row Level Security for access control.

---

## Browser support

Current Chrome, Edge, Firefox and Safari on desktop and mobile. Local storage holds roughly 5 MB per site — enough for tens of thousands of transactions. Settings shows how much is used.
