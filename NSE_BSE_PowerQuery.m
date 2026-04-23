// ============================================================
// NSE / BSE Historical Stock Data — Power Query M Script
// Calls your Render-hosted API (or localhost for local dev)
// ============================================================
//
// SETUP — Create these 3 Power Query Parameters first:
//   Name          | Type   | Example value
//   --------------|--------|-----------------------------
//   PQ_FromDate   | Text   | 2020-01-01
//   PQ_ToDate     | Text   | 2025-01-01
//   PQ_Exchange   | Text   | ALL   (NSE | BSE | ALL)
//
// HOW TO CREATE PARAMETERS (Excel / Power BI):
//   Home → Manage Parameters → New Parameter → fill Name + Type + Value
//
// Then paste this query in Advanced Editor.
// The three parameters above will be picked up automatically.
// ============================================================

let
    // ── ① READ FROM POWER QUERY PARAMETERS ──────────────────────────────────
    //    Change values in Manage Parameters — no need to edit this query.
    FromDate = PQ_FromDate,
    ToDate   = PQ_ToDate,
    Exchange = PQ_Exchange,

    // ── ② API BASE URL ───────────────────────────────────────────────────────
    //    Local dev  → "http://localhost:5000"
    //    Render     → "https://your-app-name.onrender.com"   ← replace this
    BaseUrl = "https://your-app-name.onrender.com",

    // ── ③ BUILD HISTORY URL ──────────────────────────────────────────────────
    HistoryUrl = BaseUrl
        & "/history"
        & "?from="     & FromDate
        & "&to="       & ToDate
        & "&exchange=" & Exchange,

    // ── ④ CALL THE API ───────────────────────────────────────────────────────
    RawResponse = Web.Contents(
        HistoryUrl,
        [
            Timeout = #duration(0, 2, 0, 0),     // 2-hour timeout (large dataset)
            Headers = [Accept = "application/json"]
        ]
    ),

    // ── ⑤ PARSE JSON → EXTRACT DATA ARRAY ───────────────────────────────────
    JsonDoc  = Json.Document(RawResponse),
    DataList = JsonDoc[data],

    // ── ⑥ CONVERT LIST → TABLE ───────────────────────────────────────────────
    RawTable = Table.FromList(
        DataList,
        Splitter.SplitByNothing(),
        {"Row"},
        null,
        ExtraValues.Error
    ),

    // ── ⑦ EXPAND ALL RECORD FIELDS ───────────────────────────────────────────
    Expanded = Table.ExpandRecordColumn(
        RawTable, "Row",
        {"Date", "Symbol", "Open", "High", "Low", "Close", "Volume"},
        {"Date", "Symbol", "Open", "High", "Low", "Close", "Volume"}
    ),

    // ── ⑧ SET DATA TYPES ─────────────────────────────────────────────────────
    Typed = Table.TransformColumnTypes(
        Expanded,
        {
            {"Date",   type date},
            {"Symbol", type text},
            {"Open",   type number},
            {"High",   type number},
            {"Low",    type number},
            {"Close",  type number},
            {"Volume", Int64.Type}
        }
    ),

    // ── ⑨ DERIVE Exchange + Clean Ticker columns ─────────────────────────────
    WithExchange = Table.AddColumn(
        Typed, "Exchange",
        each if Text.EndsWith([Symbol], ".NS") then "NSE"
             else if Text.EndsWith([Symbol], ".BO") then "BSE"
             else "Unknown",
        type text
    ),

    WithTicker = Table.AddColumn(
        WithExchange, "Ticker",
        each Text.BeforeDelimiter([Symbol], "."),
        type text
    ),

    // ── ⑩ FINAL COLUMN ORDER + SORT ──────────────────────────────────────────
    Reordered = Table.ReorderColumns(
        WithTicker,
        {"Date", "Ticker", "Exchange", "Symbol", "Open", "High", "Low", "Close", "Volume"}
    ),

    Sorted = Table.Sort(
        Reordered,
        {{"Date", Order.Ascending}, {"Ticker", Order.Ascending}}
    )

in
    Sorted


// ============================================================
// BONUS QUERY A — Live Ticker List (paste in a NEW blank query)
// Shows all tickers the API currently knows, with exchange label
// ============================================================
//
// let
//     BaseUrl    = "https://your-app-name.onrender.com",
//     Exchange   = PQ_Exchange,
//     Url        = BaseUrl & "/tickers?exchange=" & Exchange,
//     Response   = Web.Contents(Url),
//     Json       = Json.Document(Response),
//     TickerList = Json[tickers],
//     AsTable    = Table.FromList(
//                     TickerList,
//                     Splitter.SplitByNothing(),
//                     {"Symbol"}, null, ExtraValues.Error
//                  ),
//     WithExch   = Table.AddColumn(
//                     AsTable, "Exchange",
//                     each if Text.EndsWith([Symbol], ".NS") then "NSE" else "BSE",
//                     type text
//                  ),
//     WithTicker = Table.AddColumn(
//                     WithExch, "Ticker",
//                     each Text.BeforeDelimiter([Symbol], "."),
//                     type text
//                  )
// in
//     WithTicker
//
// ============================================================
// BONUS QUERY B — API Health Check (paste in a NEW blank query)
// ============================================================
//
// let
//     Url      = "https://your-app-name.onrender.com/health",
//     Response = Web.Contents(Url),
//     Json     = Json.Document(Response),
//     AsTable  = Record.ToTable(Json)
// in
//     AsTable
