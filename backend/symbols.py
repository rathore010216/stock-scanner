"""NSE universe symbol list.

For the $0 MVP we bundle a curated list of liquid NSE large/mid-cap names
(no runtime scraping needed). This is a representative subset of the Nifty 500;
expand toward the full 500 later, or load dynamically from an NSE CSV.

Symbols are plain NSE tickers; data_fetcher appends '.NS' for Yahoo.
"""

NIFTY_500 = [
    # --- Nifty 50 core ---
    "RELIANCE", "TCS", "HDFCBANK", "ICICIBANK", "INFY", "HINDUNILVR",
    "ITC", "SBIN", "BHARTIARTL", "KOTAKBANK", "LT", "AXISBANK",
    "BAJFINANCE", "ASIANPAINT", "MARUTI", "HCLTECH", "SUNPHARMA",
    "TITAN", "ULTRACEMCO", "WIPRO", "NESTLEIND", "ONGC", "NTPC",
    "POWERGRID", "M&M", "TATAMOTORS", "TATASTEEL", "JSWSTEEL",
    "ADANIENT", "ADANIPORTS", "COALINDIA", "HINDALCO", "GRASIM",
    "BAJAJFINSV", "TECHM", "DRREDDY", "CIPLA", "DIVISLAB", "EICHERMOT",
    "BRITANNIA", "HEROMOTOCO", "BAJAJ-AUTO", "INDUSINDBK", "APOLLOHOSP",
    "TATACONSUM", "BPCL", "SBILIFE", "HDFCLIFE", "LTIM", "SHRIRAMFIN",
    # --- Liquid mid/large caps ---
    "DMART", "PIDILITIND", "GODREJCP", "DABUR", "MARICO", "COLPAL",
    "SIEMENS", "HAVELLS", "BOSCHLTD", "ABB", "BEL", "HAL",
    "IRCTC", "IRFC", "PNB", "BANKBARODA", "CANBK", "UNIONBANK",
    "IDFCFIRSTB", "FEDERALBNK", "AUBANK", "BANDHANBNK",
    "GAIL", "IOC", "PETRONET", "TATAPOWER", "ADANIGREEN", "ADANIPOWER",
    "JINDALSTEL", "SAIL", "VEDL", "NMDC", "NATIONALUM",
    "DLF", "GODREJPROP", "OBEROIRLTY", "PRESTIGE", "PHOENIXLTD",
    "LUPIN", "AUROPHARMA", "BIOCON", "ALKEM", "TORNTPHARM", "ZYDUSLIFE",
    "MPHASIS", "PERSISTENT", "COFORGE", "OFSS", "LTTS",
    "MOTHERSON", "BALKRISIND", "MRF", "APOLLOTYRE", "BHARATFORG",
    "ASHOKLEY", "TVSMOTOR", "ESCORTS",
    "PIIND", "SRF", "DEEPAKNTR", "AARTIIND", "TATACHEM", "UPL",
    "AMBUJACEM", "ACC", "SHREECEM", "DALBHARAT", "RAMCOCEM",
    "TRENT", "PAGEIND", "ABFRL", "VBL", "UBL", "PGHH",
    "BERGEPAINT", "KANSAINER", "SUPREMEIND", "ASTRAL", "POLYCAB",
    "DIXON", "AMBER", "VOLTAS", "BLUESTARCO", "CROMPTON", "WHIRLPOOL",
    "MUTHOOTFIN", "CHOLAFIN", "LICHSGFIN", "PFC", "RECLTD", "M&MFIN",
    "ICICIPRULI", "ICICIGI", "SBICARD", "HDFCAMC", "BAJAJHLDNG",
    "INDIGO", "CONCOR", "ADANITRANS", "TORNTPOWER", "JSWENERGY",
    "ZOMATO", "PAYTM", "NYKAA", "POLICYBZR", "DELHIVERY",
    "MAXHEALTH", "FORTIS", "METROPOLIS", "LALPATHLAB", "SYNGENE",
    "INDUSTOWER", "TATACOMM", "PERSISTENT", "CGPOWER", "THERMAX",
    "CUMMINSIND", "ABBOTINDIA", "GLAND", "IPCALAB", "LAURUSLABS",
    # --- Expanded Nifty 500 constituents (broader coverage) ---
    "ADANIENSOL", "ATGL", "AWL", "BAJAJHFL", "BANKINDIA", "BDL",
    "BHARATFORG", "BHEL", "BIOCON", "BSE", "CAMS", "CDSL", "CESC",
    "CHAMBLFERT", "CHENNPETRO", "COCHINSHIP", "CONCORDBIO", "CREDITACC",
    "CROMPTON", "CYIENT", "DEEPAKFERT", "DELTACORP", "DEVYANI",
    "DRLAB", "EIDPARRY", "ELGIEQUIP", "EMAMILTD", "ENDURANCE",
    "ENGINERSIN", "EXIDEIND", "FACT", "FINEORG", "FIVESTAR", "FSL",
    "GESHIP", "GICRE", "GILLETTE", "GLAXO", "GLENMARK", "GMRINFRA",
    "GNFC", "GODFRYPHLP", "GODREJIND", "GPPL", "GRANULES", "GRINDWELL",
    "GSPL", "GUJGASLTD", "HATSUN", "HFCL", "HINDCOPPER", "HINDPETRO",
    "HONAUT", "HUDCO", "IDBI", "IEX", "IIFL", "INDIAMART", "INDIANB",
    "INDHOTEL", "IOB", "IRB", "ISEC", "JBCHEPHARM", "JKCEMENT",
    "JKLAKSHMI", "JSL", "JSWINFRA", "JUBLFOOD", "JUBLINGREA",
    "KAJARIACER", "KALYANKJIL", "KEC", "KEI", "KFINTECH", "KIMS",
    "KPITTECH", "KPRMILL", "LICI", "LINDEINDIA", "LLOYDSME", "LTF",
    "MANAPPURAM", "MANKIND", "MAPMYINDIA", "MAZDOCK", "MCX", "MEDANTA",
    "MFSL", "MGL", "MINDACORP", "MOTILALOFS", "MRPL", "NAM-INDIA",
    "NAVINFLUOR", "NBCC", "NCC", "NETWEB", "NHPC", "NLCINDIA",
    "NUVAMA", "OIL", "PATANJALI", "PAYTM", "PEL", "PFIZER", "PGEL",
    "PNBHOUSING", "POONAWALLA", "POWERINDIA", "PPLPHARMA", "PRAJIND",
    "PSB", "RADICO", "RAILTEL", "RAJESHEXPO", "RATNAMANI", "RBLBANK",
    "RHIM", "RITES", "RVNL", "SAILIFE", "SAPPHIRE", "SCHAEFFLER",
    "SJVN", "SOBHA", "SOLARINDS", "SONACOMS", "STARHEALTH", "SUMICHEM",
    "SUNTV", "SUPREMEIND", "SUZLON", "SWSOLAR", "SYRMA", "TATAELXSI",
    "TATAINVEST", "TATATECH", "TIINDIA", "TITAGARH", "TRIDENT",
    "TRITURBINE", "TTML", "UCOBANK", "UJJIVANSFB", "UNOMINDA",
    "USHAMART", "UTIAMC", "VGUARD", "VINATIORGA", "VIPIND", "WELCORP",
    "WELSPUNLIV", "YESBANK", "ZEEL", "ZENSARTECH", "ZFCVINDIA",
    "ZYDUSWELL", "APLAPOLLO", "AEGISLOG", "AFFLE", "ANGELONE",
    "APLLTD", "APTUS", "ASAHIINDIA", "ASTERDM", "ATUL", "BASF",
    "BATAINDIA", "BAYERCROP", "BLUEDART", "BSOFT", "CARBORUNIV",
    "CASTROLIND", "CEATLTD", "CENTURYPLY", "CHOLAHLDNG", "COROMANDEL",
    "DCMSHRIRAM", "EIHOTEL", "FINCABLES", "FLUOROCHEM", "FORTIS",
    "GODIGIT", "HAPPSTMNDS", "IGL", "INDIACEM", "IPCA", "JYOTHYLAB",
    "LEMONTREE", "MASTEK", "METROPOLIS", "NH", "OLECTRA", "PVRINOX",
    "RAYMOND", "REDINGTON", "SCHNEIDER", "SHYAMMETL", "SUNDRMFAST",
    "SWANENERGY", "TANLA", "TEJASNET", "TIMKEN", "TRENT", "TVSHLTD",
    "WESTLIFE", "WOCKPHARMA",
]

# De-duplicate while preserving order.
_seen = set()
NIFTY_500 = [s for s in NIFTY_500 if not (s in _seen or _seen.add(s))]


def get_universe() -> list[str]:
    """Return the scan universe. Tries NSE's public Nifty 500 CSV so the list
    stays current; falls back to the bundled curated list on any failure.
    """
    url = ("https://nsearchives.nseindia.com/content/indices/"
           "ind_nifty500list.csv")
    try:
        import csv
        import io
        import requests
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Accept": "text/csv,*/*",
        }
        r = requests.get(url, headers=headers, timeout=20)
        r.raise_for_status()
        reader = csv.DictReader(io.StringIO(r.text))
        syms = [row["Symbol"].strip().upper()
                for row in reader if row.get("Symbol")]
        # Sanity: NSE Nifty 500 should have ~500 names.
        if len(syms) >= 400:
            print(f"Loaded {len(syms)} symbols from NSE Nifty 500 CSV")
            return syms
        print(f"NSE CSV returned only {len(syms)} symbols; using fallback")
    except Exception as e:
        print(f"NSE CSV fetch failed ({e}); using bundled list")
    return NIFTY_500

