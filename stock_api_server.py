"""
NSE/BSE Historical Stock Data API
- Tickers auto-fetched from official NSE & BSE sources at startup
- Hosted on Render (free tier) — called once/twice daily from Power Query
"""

from flask import Flask, request, jsonify
import yfinance as yf
import pandas as pd
import requests
import io
import time
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = Flask(__name__)

# ── Global ticker cache (loaded once at startup) ─────────────────────────────
TICKER_CACHE = {"NSE": [], "BSE": [], "loaded_at": None}


def fetch_nse_tickers() -> list:
    """
    Fetch all NSE equity symbols from NSE's official CSV.
    Returns list like ["RELIANCE.NS", "TCS.NS", ...]
    """
    url = "https://archives.nseindia.com/content/equities/EQUITY_L.csv"
    headers = {
        "User-Agent": "Mozilla/5.0",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.nseindia.com/",
    }
    try:
        resp = requests.get(url, headers=headers, timeout=30)
        resp.raise_for_status()
        df = pd.read_csv(io.StringIO(resp.text))
        symbols = df["SYMBOL"].dropna().str.strip().tolist()
        tickers = [f"{s}.NS" for s in symbols if s]
        log.info(f"NSE: fetched {len(tickers)} tickers")
        return tickers
    except Exception as e:
        log.error(f"NSE fetch failed: {e}")
        return []


def fetch_bse_tickers() -> list:
    """
    Fetch all BSE active equity scrip codes from BSE API.
    Returns list like ["500325.BO", "532540.BO", ...]
    """
    url = (
        "https://api.bseindia.com/BseIndiaAPI/api/ListofScripData/w"
        "?Group=&Scripcode=&industry=&segment=Equity&status=Active"
    )
    headers = {
        "User-Agent": "Mozilla/5.0",
        "Referer": "https://www.bseindia.com/",
    }
    try:
        resp = requests.get(url, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        scrip_list = data.get("Table", data) if isinstance(data, dict) else data
        codes = [
            str(item.get("SCRIP_CD", "")).strip()
            for item in scrip_list
            if item.get("SCRIP_CD")
        ]
        tickers = [f"{c}.BO" for c in codes if c]
        log.info(f"BSE: fetched {len(tickers)} tickers")
        return tickers
    except Exception as e:
        log.warning(f"BSE API failed ({e}), trying fallback...")
        return fetch_bse_fallback(headers)


def fetch_bse_fallback(headers: dict) -> list:
    """BSE fallback via their Bhavcopy ZIP."""
    import zipfile
    url = "https://www.bseindia.com/download/Bhavcopy/Equity/EQ_ISINCODE_csvs.zip"
    try:
        resp = requests.get(url, headers=headers, timeout=60)
        resp.raise_for_status()
        with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
            csv_name = [n for n in z.namelist() if n.endswith(".csv")][0]
            df = pd.read_csv(z.open(csv_name))
        col = next(
            (c for c in df.columns if "CODE" in c.upper() or "SCRIP" in c.upper()),
            df.columns[0],
        )
        codes = df[col].dropna().astype(str).str.strip().tolist()
        tickers = [f"{c}.BO" for c in codes if c.isdigit()]
        log.info(f"BSE fallback: {len(tickers)} tickers")
        return tickers
    except Exception as e:
        log.error(f"BSE fallback failed: {e}")
        return []


def load_tickers(force: bool = False):
    """Populate TICKER_CACHE. Skips if already loaded unless force=True."""
    if not force and TICKER_CACHE["loaded_at"] and TICKER_CACHE["NSE"]:
        return
    log.info("Loading tickers from NSE and BSE official sources...")
    TICKER_CACHE["NSE"] = fetch_nse_tickers()
    TICKER_CACHE["BSE"] = fetch_bse_tickers()
    TICKER_CACHE["loaded_at"] = datetime.utcnow().isoformat()
    log.info(
        f"Cache ready — NSE: {len(TICKER_CACHE['NSE'])}, BSE: {len(TICKER_CACHE['BSE'])}"
    )


def get_tickers_for(exchange: str) -> list:
    load_tickers()
    if exchange == "NSE":
        return TICKER_CACHE["NSE"]
    elif exchange == "BSE":
        return TICKER_CACHE["BSE"]
    return list(dict.fromkeys(TICKER_CACHE["NSE"] + TICKER_CACHE["BSE"]))


# ── Routes ───────────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    load_tickers()
    return jsonify({
        "status": "ok",
        "nse_tickers": len(TICKER_CACHE["NSE"]),
        "bse_tickers": len(TICKER_CACHE["BSE"]),
        "cache_loaded_at": TICKER_CACHE["loaded_at"],
    })


@app.route("/tickers", methods=["GET"])
def ticker_list():
    """
    GET /tickers?exchange=NSE|BSE|ALL
    Returns the full live ticker list (auto-fetched from NSE/BSE).
    """
    exchange = request.args.get("exchange", "ALL").upper()
    tickers  = get_tickers_for(exchange)
    return jsonify({
        "exchange": exchange,
        "count": len(tickers),
        "tickers": tickers,
        "cache_loaded_at": TICKER_CACHE["loaded_at"],
    })


@app.route("/tickers/refresh", methods=["POST"])
def refresh_tickers():
    """POST /tickers/refresh — force reload from NSE/BSE."""
    load_tickers(force=True)
    return jsonify({
        "status": "refreshed",
        "nse_tickers": len(TICKER_CACHE["NSE"]),
        "bse_tickers": len(TICKER_CACHE["BSE"]),
        "cache_loaded_at": TICKER_CACHE["loaded_at"],
    })


@app.route("/history", methods=["GET"])
def get_history():
    """
    GET /history?from=YYYY-MM-DD&to=YYYY-MM-DD&exchange=NSE|BSE|ALL

    Optional:
        batch_size : tickers per yfinance call  (default 50)
        limit      : cap total tickers          (for testing, e.g. limit=20)
    """
    from_date  = request.args.get("from")
    to_date    = request.args.get("to")
    exchange   = request.args.get("exchange", "ALL").upper()
    batch_size = int(request.args.get("batch_size", 50))
    limit      = request.args.get("limit")

    if not from_date or not to_date:
        return jsonify({"error": "'from' and 'to' date params required (YYYY-MM-DD)"}), 400
    try:
        datetime.strptime(from_date, "%Y-%m-%d")
        datetime.strptime(to_date,   "%Y-%m-%d")
    except ValueError:
        return jsonify({"error": "Dates must be YYYY-MM-DD"}), 400

    tickers = get_tickers_for(exchange)
    if limit:
        tickers = tickers[: int(limit)]

    log.info(f"History request: {len(tickers)} tickers | {from_date} → {to_date}")

    all_records, failed = [], []

    for i in range(0, len(tickers), batch_size):
        batch = tickers[i : i + batch_size]
        try:
            raw = yf.download(
                batch,
                start=from_date,
                end=to_date,
                group_by="ticker",
                auto_adjust=True,
                threads=True,
                progress=False,
            )

            if isinstance(raw.columns, pd.MultiIndex):
                for symbol in batch:
                    try:
                        df = raw[symbol].dropna(how="all").copy()
                        if df.empty:
                            continue
                        df["Symbol"] = symbol
                        df.reset_index(inplace=True)
                        all_records.extend(_serialize(df))
                    except Exception:
                        failed.append(symbol)
            else:
                df = raw.dropna(how="all").copy()
                df["Symbol"] = batch[0]
                df.reset_index(inplace=True)
                all_records.extend(_serialize(df))

        except Exception as e:
            log.error(f"Batch error: {e}")
            failed.extend(batch)

        time.sleep(0.3)

    return jsonify({
        "from": from_date,
        "to": to_date,
        "exchange": exchange,
        "tickers_requested": len(tickers),
        "records_returned": len(all_records),
        "failed_tickers": failed,
        "data": all_records,
    })


def _serialize(df: pd.DataFrame) -> list:
    records = []
    for rec in df.to_dict(orient="records"):
        clean = {}
        for k, v in rec.items():
            if hasattr(v, "strftime"):
                clean[k] = v.strftime("%Y-%m-%d")
            elif isinstance(v, float) and pd.isna(v):
                clean[k] = None
            else:
                clean[k] = v
        records.append(clean)
    return records


# Pre-load tickers at startup so first API call is fast
with app.app_context():
    load_tickers()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
