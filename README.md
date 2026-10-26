# BAN430 live page and scoreboard

A self-updating page for the mandatory electricity assignment. It has two tabs: the **scoreboard**
(the groups' submissions scored on the days with a known price, with a toggle between each group's
official last submission and its best submission) and the **price tracker** (NO5 prices, the seasonal
naive benchmark forecast and the distribution of the October average). A GitHub Actions workflow
runs `build_site.R` every 15 minutes around 13:00 (when tomorrow's prices are published) and
hourly otherwise, and publishes `site/` on GitHub Pages. The page itself reloads `data.json`
every two minutes, so open tabs update without a refresh.

## Files

| File | What it does |
|---|---|
| `build_site.R` | Fetches the prices, fits the benchmark and writes `site/data.json`, `site/status.png` and `site/index.html` |
| `status_plot.R` | The data and figure code, shared with the lecture slides (a copy of `../status_plot.R`) |
| `board.R` | Scores every submission on the days with a known price and makes the benchmark forecasts (naive, seasonal naive, 7-day mean) |
| `submissions_clean.csv` | The submissions (group name, time, forecast; no member names). Made by `../prepare_submissions.R` from the downloaded sheet. The submissions are locked, so it does not change |
| `display_names.csv` | How each group is named on the page. Edit it to rename or anonymise a group, then rebuild |
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
* The page shows the group names (as chosen in the submission), never the members. Change
  `display_names.csv` to rename a group.
* While the month runs, the ranking is provisional: the sum of the ranks in daily RMSE and daily CRPS
  on the days known so far. When all prices of the month are known (31 October), the page adds the absolute
  error and CRPS of the October average, and the ranking uses all four categories of the assignment.
* The page does not depend on how often the workflow runs: it fetches the prices of the scored days straight from
  hvakosterstrommen.no (the service allows it) and rescores every submission in the browser, so a new price shows up
  within about two minutes of its publication (13:00). The workflow only has to produce the page and the (fixed)
  forecasts, and refreshes the price tracker. Scheduled runs on GitHub are best effort and are often hours late.
* A push to `main` also runs the workflow. To run it by hand: Actions > Update live page > **Run workflow**
  (not "Re-run jobs", which repeats an old run with the old code).
* The benchmarks are made with the data of the deadline day (22 October), with 2000 bootstrapped paths.
* To use another month or deadline, change the defaults in `board.R` and `build_site.R`.
