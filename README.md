# NSE/BSE Stock API → Power Query Setup Guide

## Architecture

```
NSE official CSV  ──┐
BSE official API  ──┤──► stock_api_server.py (Render / localhost)
                    │         ↑ auto-fetches ALL tickers at startup
                    └──► Power Query (Excel / Power BI)
                              ↑ date range controlled by PQ Parameters
```

---

## Files

| File | Purpose |
|------|---------|
| `stock_api_server.py` | Flask API — auto-fetches tickers, serves OHLCV history |
| `NSE_BSE_PowerQuery.m` | M script — paste into Power Query Advanced Editor |
| `requirements.txt` | Python dependencies |
| `render.yaml` | One-click Render deployment config |

---

## Option A — Deploy to Render (Recommended, Free)

### 1. Push to GitHub
```bash
git init
git add stock_api_server.py requirements.txt render.yaml
git commit -m "NSE BSE stock API"
git remote add origin https://github.com/YOUR_USERNAME/stock-api.git
git push -u origin main
```

### 2. Create Render Web Service
1. Go to [render.com](https://render.com) → **New** → **Web Service**
2. Connect your GitHub repo
3. Render auto-detects `render.yaml` — click **Deploy**
4. Wait ~2 minutes for first deploy
5. Your URL will be: `https://nse-bse-stock-api.onrender.com`

### ⚠️ Render Free Tier — Cold Start
Free tier spins down after 15 minutes of inactivity.
First request after idle takes ~30–60 seconds to wake up.
Since you call it once/twice daily, just allow extra time on the first call.

---

## Option B — Run Locally

```bash
pip install -r requirements.txt
python stock_api_server.py
# → http://localhost:5000
```

---

## Power Query Setup

### Step 1 — Create 3 Parameters

In Excel: **Data → Get Data → Launch Power Query Editor → Home → Manage Parameters → New Parameter**

| Parameter Name | Type | Current Value |
|----------------|------|---------------|
| `PQ_FromDate`  | Text | `2020-01-01`  |
| `PQ_ToDate`    | Text | `2025-01-01`  |
| `PQ_Exchange`  | Text | `ALL`         |

`PQ_Exchange` accepts: `NSE`, `BSE`, or `ALL`

### Step 2 — Create the Main Query

1. **Home → New Source → Blank Query**
2. **View → Advanced Editor**
3. Delete all existing text
4. Paste the contents of `NSE_BSE_PowerQuery.m`
5. Replace `your-app-name` in `BaseUrl` with your actual Render URL
6. Click **Done** → **Close & Load**

### Step 3 — Refresh Data

- **Right-click the table → Refresh** (or Data → Refresh All)
- Change dates anytime via **Home → Manage Parameters** — no query editing needed

---

## API Endpoints

| Endpoint | Method | Params | Description |
|----------|--------|--------|-------------|
| `/health` | GET | — | Server status + ticker counts |
| `/tickers` | GET | `exchange=NSE\|BSE\|ALL` | Live ticker list from NSE/BSE |
| `/tickers/refresh` | POST | — | Force re-fetch tickers from NSE/BSE |
| `/history` | GET | `from`, `to`, `exchange`, `batch_size`, `limit` | OHLCV data for all stocks |

### Example URLs
```
https://your-app.onrender.com/health
https://your-app.onrender.com/tickers?exchange=NSE
https://your-app.onrender.com/history?from=2023-01-01&to=2024-01-01&exchange=NSE
https://your-app.onrender.com/history?from=2023-01-01&to=2024-01-01&exchange=ALL&limit=50
```

---

## Output Columns in Power Query

| Column   | Type   | Example      | Description                     |
|----------|--------|--------------|---------------------------------|
| Date     | date   | 2024-03-15   | Trading date                    |
| Ticker   | text   | TCS          | Clean symbol (no exchange suffix)|
| Exchange | text   | NSE          | NSE or BSE                      |
| Symbol   | text   | TCS.NS       | Full yfinance symbol            |
| Open     | number | 3921.50      | Opening price (INR)             |
| High     | number | 3978.00      | Day high (INR)                  |
| Low      | number | 3905.25      | Day low (INR)                   |
| Close    | number | 3965.80      | Adjusted close (INR)            |
| Volume   | Int64  | 2847300      | Shares traded                   |

---

## How Ticker Auto-Fetch Works

At startup, the server calls:
- **NSE**: `https://archives.nseindia.com/content/equities/EQUITY_L.csv` → ~2,000 symbols → appends `.NS`
- **BSE**: `https://api.bseindia.com/BseIndiaAPI/api/ListofScripData/w?...` → ~5,000 scrip codes → appends `.BO`

Tickers are cached in memory for the server's lifetime. Use `POST /tickers/refresh` to force a reload without restarting.

---

## Tips

**Test with a small date range first** — use `&limit=20` param to fetch just 20 tickers:
```
/history?from=2024-01-01&to=2024-03-01&exchange=NSE&limit=20
```

**Render timeout** — `render.yaml` sets `--timeout 7200` (2 hours) for large full fetches.

**Reduce payload size** — fetch NSE and BSE separately in two PQ queries if ALL is too large.
