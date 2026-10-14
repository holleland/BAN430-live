# Builds the live page for the mandatory assignment.
#
# It fetches the latest prices, refits the seasonal naive benchmark, and writes
#   site/data.json   the data the page draws its charts from
#   site/status.png  the static figure (also used as a link preview)
#   site/index.html  the page (copied from src/index.html)
# The GitHub Actions workflow runs this and publishes the folder `site/`.

suppressPackageStartupMessages({
  library(fpp3)
  library(jsonlite)
})
source("status_plot.R")

out <- "site"
dir.create(out, showWarnings = FALSE)

d <- electricity_status_data()

r3 <- function(x) round(x, 3)
day_row <- function(date, price) list(d = as.character(date), p = r3(price))

latest <- d$no5[which.max(d$no5$date), ]
prev <- d$no5[d$no5$date == latest$date - 1, ]
month_days <- d$days_known
lo <- month_days[which.min(month_days$price), ]
hi <- month_days[which.max(month_days$price), ]

month <- list(
  avg_so_far = r3(d$avg_so_far),
  known_days = nrow(month_days),
  n_days = d$n_days,
  days_left = d$n_ahead
)
hist_out <- NULL
if (!is.null(d$month_sims)) {
  m <- d$month_sims$month_mean
  q <- quantile(m, c(0.05, 0.25, 0.5, 0.75, 0.95))
  month <- c(month, list(proj_q05 = r3(q[[1]]), proj_q25 = r3(q[[2]]), proj_median = r3(q[[3]]),
                         proj_q75 = r3(q[[4]]), proj_q95 = r3(q[[5]])))
  h <- hist(m, breaks = 30, plot = FALSE)
  hist_out <- list(x = r3(h$mids), n = h$counts, width = r3(diff(h$breaks)[1]))
}

payload <- list(
  updated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  area = d$area,
  release = as.character(d$release),
  month_start = as.character(d$month_start),
  month_end = as.character(d$month_end),
  deadline = "2026-10-22T12:00:00+02:00",
  last_day = as.character(d$last_day),
  latest = day_row(latest$date, latest$price),
  previous = if (nrow(prev) == 1) day_row(prev$date, prev$price) else NULL,
  lowest = if (nrow(lo)) day_row(lo$date, lo$price) else NULL,
  highest = if (nrow(hi)) day_row(hi$date, hi$price) else NULL,
  month = month,
  prices = lapply(seq_len(nrow(d$obs)), function(i) day_row(d$obs$date[i], d$obs$price[i])),
  forecast = if (!is.null(d$fan)) lapply(seq_len(nrow(d$fan)), function(i) {
    f <- d$fan[i, ]
    list(d = as.character(f$date), q05 = r3(f$q05), q25 = r3(f$q25), q50 = r3(f$q50),
         q75 = r3(f$q75), q95 = r3(f$q95))
  }) else list(),
  hist = hist_out
)
write_json(payload, file.path(out, "data.json"), auto_unbox = TRUE, null = "null", pretty = FALSE)

# static figure
theme_set(theme_bw() + theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank()))
ggplot2::ggsave(file.path(out, "status.png"), electricity_status(data = d),
                width = 9, height = 4.2, dpi = 120)

file.copy("src/index.html", file.path(out, "index.html"), overwrite = TRUE)
message("Built the live page: prices up to ", d$last_day, ".")
