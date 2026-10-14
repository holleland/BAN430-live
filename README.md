# BAN430 live page

A self-updating page for the mandatory electricity assignment: NO5 prices, the seasonal naive
benchmark forecast and the distribution of the October average. A GitHub Actions workflow
runs `build_site.R` every 15 minutes around 13:00 (when tomorrow's prices are published) and
hourly otherwise, and publishes `site/` on GitHub Pages. The page itself reloads `data.json`
every two minutes, so open tabs update without a refresh.

## Files

| File | What it does |
|---|---|
| `build_site.R` | Fetches the prices, fits the benchmark and writes `site/data.json`, `site/status.png` and `site/index.html` |
| `status_plot.R` | The data and figure code, shared with the lecture slides (a copy of `../status_plot.R`) |
| `src/index.html` | The page (charts with Apache ECharts, loaded from a CDN) |
| `.github/workflows/update.yml` | The schedule and the deployment |
| `DESCRIPTION` | The R packages the workflow installs |

## One-time setup

1. On github.com, create a **public**, empty repository called `BAN430-live` (no README).
2. Prepare the files and push them (from this folder):
   ```bash
   bash prepare_repo.sh                  # creates ~/BAN430-live with the files committed
   cd ~/BAN430-live
   git remote add origin git@github.com:holleland/BAN430-live.git
   git push -u origin main
   ```
3. In the repository: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
4. Open the **Actions** tab, choose *Update live page* and press **Run workflow**. The first run
   takes a few minutes (it installs the R packages); later runs are faster because the packages are cached.
5. The page is then at `https://holleland.github.io/BAN430-live/`.

## Testing locally

```bash
cp ../status_plot.R .          # if the shared code has changed
Rscript build_site.R
python3 -m http.server 8765 --directory site     # open http://localhost:8765
```

## Notes

* Scheduled runs can be a few minutes late. Use *Run workflow* to update the page right away.
* GitHub switches scheduled workflows off after 60 days without activity in a public repository.
* The page shows only the number of groups that have submitted (read from the Apps Script
  endpoint), never names, members or forecasts.
* After 31 October the page shows the final average. The scoreboard section is a placeholder
  until the scoring is added.
