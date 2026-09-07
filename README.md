# NSE Swing Screener (stock-scanner)

A $0 Android app + backend that runs a daily technical screen of NSE stocks and
shows the matches with interactive charts. **Research/screener tool — not
investment advice.** Backtesting showed no reliable edge over buy-and-hold after
costs; use it to surface candidates for your own chart-based judgment.

## Architecture
- **backend/** — Python screener. A scheduled GitHub Action (`.github/workflows/
  scan.yml`) runs it daily after NSE close and publishes results to Firebase
  Realtime Database under `/stock/`:
  - `/stock/latest` — matches list (symbol, price, RSI, which screeners fired)
  - `/stock/charts/{symbol}` — per-stock 120-day chart series (fetched on tap)
- **app/** — Flutter Android app (package `com.pawan.stockanalysis`). Signs in
  anonymously, reads `/stock/latest`, shows a filterable matches list (screener
  toggle chips + min-hits), and a chart screen (price+EMA+Bollinger, volume,
  MACD, RSI) via fl_chart.
- Cloud-built APK via `.github/workflows/build-apk.yml`.

Everything runs on the Firebase Spark (free) plan, shared with the family-locator
project but namespaced under `/stock/`.

## One-time setup (Firebase + GitHub)
1. In Firebase (family-locator project) → **Authentication → Anonymous → Enable**.
2. Add the `/stock` rules from `FIREBASE_RULES.md` to the database rules.
3. Get a **Database secret**: Firebase → Project settings → Service accounts →
   Database secrets.
4. In the GitHub repo → Settings → Secrets and variables → Actions, add:
   - `FIREBASE_DB_URL` = `https://family-locator-a5106-default-rtdb.firebaseio.com`
   - `FIREBASE_DB_SECRET` = the database secret
   - `GOOGLE_SERVICES_JSON` = full contents of the stockanalysis app's
     `google-services.json`
5. Run the **Daily stock scan** workflow once (Actions → Run workflow) to
   populate `/stock/`.
6. Run the **Build Stock APK** workflow → download the `stock-scanner-apk`
   artifact → install.

## Backend locally (optional)
```
cd backend
pip install -r requirements.txt
python publish.py --dry-run     # builds payload previews without publishing
```
