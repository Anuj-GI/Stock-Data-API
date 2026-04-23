// ============================================================
// NSE / BSE Historical Stock Data — Power Query M Script
// Handles large datasets by fetching in yearly chunks
// ============================================================
//
// PARAMETERS NEEDED (Home → Manage Parameters → New Parameter):
//   PQ_FromDate  | Text | 2020-01-01
//   PQ_ToDate    | Text | 2025-01-01
//   PQ_Exchange  | Text | NSE   ← start with NSE only, not ALL
// ============================================================

let
    // ── ① PARAMETERS ────────────────────────────────────────────────────────
    FromDate  = PQ_FromDate,
    ToDate    = PQ_ToDate,
    Exchange  = PQ_Exchange,
    BaseUrl   = "https://stock-data-api-b8jt.onrender.com",

    // ── ② GENERATE YEARLY DATE CHUNKS ───────────────────────────────────────
    // Instead of one giant request, we split into 1-year chunks
    // e.g. 2020-2025 becomes 5 separate API calls
    FromYear  = Date.Year(Date.FromText(FromDate)),
    ToYear    = Date.Year(Date.FromText(ToDate)),

    YearList  = List.Numbers(FromYear, ToYear - FromYear + 1),

    // Build list of {from, to} pairs per year
    DateChunks = List.Transform(
        YearList,
        each {
            Date.ToText(#date(_, 1, 1),  "yyyy-MM-dd"),
            Date.ToText(#date(_, 12, 31), "yyyy-MM-dd")
        }
    ),

    // Clamp first chunk start to actual FromDate
    // Clamp last chunk end to actual ToDate
    ClampedChunks = List.Transform(
        List.Positions(DateChunks),
        (i) =>
            let
                chunk     = DateChunks{i},
                chunkFrom = if i = 0 then FromDate else chunk{0},
                chunkTo   = if i = List.Count(DateChunks) - 1 then ToDate else chunk{1}
            in
                {chunkFrom, chunkTo}
    ),

    // ── ③ FETCH ONE YEAR AT A TIME ───────────────────────────────────────────
    FetchChunk = (fromD as text, toD as text) =>
        let
            Url = BaseUrl
                & "/history"
                & "?from="     & fromD
                & "&to="       & toD
                & "&exchange=" & Exchange,

            Raw  = Web.Contents(
                Url,
                [
                    Timeout = #duration(0, 1, 30, 0),  // 90-min timeout per chunk
                    Headers = [Accept = "application/json"]
                ]
            ),
            Json     = Json.Document(Raw),
            DataList = Json[data],
            AsTable  = Table.FromList(
                            DataList,
                            Splitter.SplitByNothing(),
                            {"Row"}, null, ExtraValues.Error
                        ),
            Expanded = Table.ExpandRecordColumn(
                            AsTable, "Row",
                            {"Date","Symbol","Open","High","Low","Close","Volume"},
                            {"Date","Symbol","Open","High","Low","Close","Volume"}
                        )
        in
            Expanded,

    // ── ④ COMBINE ALL CHUNKS ─────────────────────────────────────────────────
    AllChunks = List.Transform(
        ClampedChunks,
        (chunk) => FetchChunk(chunk{0}, chunk{1})
    ),

    Combined = Table.Combine(AllChunks),

    // ── ⑤ SET DATA TYPES ─────────────────────────────────────────────────────
    Typed = Table.TransformColumnTypes(
        Combined,
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

    // ── ⑥ ADD Exchange + Ticker COLUMNS ──────────────────────────────────────
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

    // ── ⑦ REORDER + SORT ─────────────────────────────────────────────────────
    Reordered = Table.ReorderColumns(
        WithTicker,
        {"Date","Ticker","Exchange","Symbol","Open","High","Low","Close","Volume"}
    ),

    Sorted = Table.Sort(
        Reordered,
        {{"Date", Order.Ascending}, {"Ticker", Order.Ascending}}
    )

in
    Sorted
