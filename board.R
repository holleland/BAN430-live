# The scoreboard data for the live page.
#
# scoreboard_data() scores every submission on the days with a known price, and adds the
# benchmark forecasts (naive, seasonal naive, 7-day mean) made on the deadline day as
# "groups" of their own. The result is a plain list that build_site.R writes into data.json,
# and the page does the rest (the toggle between the official and the best submission,
# the ranking, the charts).
#
# Scores follow the assignment page: the quantile score of the 19 quantiles averaged
# over the p-levels (CRPS = sum of the quantile scores / 20), RMSE of the point forecast
# over the days, and the coverage of the 90% interval (q05 to q95).

probs <- seq(0.05, 0.95, by = 0.05)
qn <- sprintf("q%02d", round(probs * 100))

qscore_mat <- function(Q, y) {          # Q: n x 19 matrix, y: n outcomes
  P <- matrix(probs, nrow = nrow(Q), ncol = length(probs), byrow = TRUE)
  Y <- matrix(y, nrow = nrow(Q), ncol = length(probs))
  rowSums(ifelse(Y < Q, 2 * (1 - P) * (Q - Y), 2 * P * (Y - Q))) / 20
}

benchmark_forecasts <- function(no5, deadline_day = as.Date("2026-10-22"),
                                scored_days = as.Date("2026-10-23") + 0:8,
                                month_start = as.Date("2026-10-01"), n_paths = 2000, seed = 2026) {
  train <- no5 %>% dplyr::filter(date <= deadline_day, date > deadline_day - 365) %>%
    tsibble::as_tsibble(index = date)
  month_days <- as.integer(format(seq(month_start, by = "month", length.out = 2)[2] - 1, "%d"))
  known_sum <- sum(no5$price[no5$date >= month_start & no5$date <= deadline_day])
  fit <- train %>% fabletools::model(
    naive = fable::NAIVE(price),
    snaive = fable::SNAIVE(price ~ lag("week")),
    mean7 = fable::MEAN(price ~ window(size = 7)))
  set.seed(seed)
  one_model <- function(m) {      # one model at a time: generating all three together gives wrong innovations
    fit %>% dplyr::select(dplyr::all_of(m)) %>%
      fabletools::generate(h = length(scored_days), times = n_paths, bootstrap = TRUE) %>%
      tibble::as_tibble() %>% dplyr::select(.model, .rep, date, .sim)
  }
  paths <- dplyr::bind_rows(lapply(c("naive", "snaive", "mean7"), one_model))
  labels <- c(naive = "Benchmark: naive", snaive = "Benchmark: seasonal naive", mean7 = "Benchmark: 7-day mean")
  lapply(names(labels), function(m) {
    p <- paths %>% dplyr::filter(.model == m)
    days <- lapply(scored_days, function(dd) {
      v <- p$.sim[p$date == dd]
      c(point = mean(v), setNames(as.numeric(quantile(v, probs)), qn))
    })
    mm <- p %>% dplyr::group_by(.rep) %>% dplyr::summarise(s = sum(.sim), .groups = "drop") %>%
      dplyr::mutate(m = (known_sum + s) / month_days)
    list(group = labels[[m]], display = labels[[m]], benchmark = TRUE, sid = paste0("bench_", m),
         received_at = format(as.POSIXct(paste(deadline_day, "10:00:00"), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
         days = days,
         month = c(point = mean(mm$m), setNames(as.numeric(quantile(mm$m, probs)), qn)))
  })
}

scoreboard_data <- function(no5, subs_file = "submissions_clean.csv", display_file = "display_names.csv",
                            deadline_utc = "2026-10-22T10:00:00Z",
                            scored_days = as.Date("2026-10-23") + 0:8,
                            month_start = as.Date("2026-10-01")) {
  subs <- readr::read_csv(subs_file, show_col_types = FALSE,
                          col_types = readr::cols(.default = readr::col_double(), group = "c",
                                                  received_at = "c", target = "c"))
  disp <- readr::read_csv(display_file, show_col_types = FALSE, col_types = "cc")
  display <- setNames(disp$display, disp$group)
  actual <- setNames(rep(NA_real_, length(scored_days)), as.character(scored_days))
  known <- no5 %>% dplyr::filter(date %in% scored_days)
  actual[as.character(known$date)] <- known$price

  # the actual monthly average is only known when every day of the month has a price
  month_end <- seq(month_start, by = "month", length.out = 2)[2] - 1
  month_prices <- no5$price[no5$date >= month_start & no5$date <= month_end]
  month_actual <- if (length(month_prices) == as.integer(month_end - month_start) + 1) mean(month_prices) else NA_real_

  # one record per submission: the nine daily forecasts and the monthly one
  make_record <- function(rows) {
    daily <- rows[rows$target != "month_mean", ]
    daily <- daily[match(as.character(scored_days), daily$target), ]
    mrow <- rows[rows$target == "month_mean", ]
    list(group = rows$group[1], display = unname(display[rows$group[1]]), benchmark = FALSE,
         sid = as.character(rows$sid[1]), received_at = rows$received_at[1],
         days = lapply(seq_len(nrow(daily)), function(i) unlist(daily[i, c("point", qn)])),
         month = if (nrow(mrow) == 1) unlist(mrow[1, c("point", qn)]) else NULL,
         month_all = if (nrow(mrow) == 1) unlist(mrow[1, c("point", qn)]) else NULL)
  }
  recs <- lapply(split(subs, subs$sid), make_record)
  recs <- c(recs, benchmark_forecasts(no5, scored_days = scored_days))

  r3 <- function(x) round(x, 3)
  score_record <- function(rec) {
    D <- do.call(rbind, rec$days)                      # 9 x 20
    ok <- !is.na(actual)
    crps <- rep(NA_real_, nrow(D))
    if (any(ok)) crps[ok] <- qscore_mat(D[ok, qn, drop = FALSE], actual[ok])
    err <- D[, "point"] - actual
    inside <- D[, "q05"] <= actual & actual <= D[, "q95"]
    list(
      group = rec$group, display = rec$display, benchmark = rec$benchmark, id = rec$sid,
      t = rec$received_at,
      p = r3(D[, "point"]), q05 = r3(D[, "q05"]), q25 = r3(D[, "q25"]), q50 = r3(D[, "q50"]),
      q75 = r3(D[, "q75"]), q95 = r3(D[, "q95"]),
      crps = ifelse(is.na(crps), NA, r3(crps)),
      n = sum(ok),
      rmse = if (any(ok)) r3(sqrt(mean(err[ok]^2))) else NA,
      mean_crps = if (any(ok)) r3(mean(crps[ok])) else NA,
      bias = if (any(ok)) r3(mean(err[ok])) else NA,
      cover90 = if (any(ok)) round(mean(inside[ok]), 3) else NA,
      month = if (!is.null(rec$month)) as.list(r3(rec$month[c("point", "q05", "q50", "q95")])) else NULL,
      m_abs = if (!is.na(month_actual) && !is.null(rec$month_all)) r3(abs(rec$month_all[["point"]] - month_actual)) else NA,
      m_crps = if (!is.na(month_actual) && !is.null(rec$month_all))
        r3(qscore_mat(matrix(rec$month_all[qn], nrow = 1), month_actual)) else NA)
  }
  scored <- lapply(recs, score_record)

  # the official submission of a group: the last one made before the deadline
  groups <- unique(vapply(scored, `[[`, "", "group"))
  for (g in groups) {
    idx <- which(vapply(scored, function(s) s$group == g && s$t <= deadline_utc, NA))
    if (length(idx) == 0) next
    last <- idx[order(vapply(scored[idx], `[[`, "", "t"))][length(idx)]
    for (i in idx) scored[[i]]$official <- (i == last)
  }
  for (i in seq_along(scored)) if (is.null(scored[[i]]$official)) scored[[i]]$official <- FALSE   # after the deadline
  after <- vapply(scored, function(s) s$t > deadline_utc && !s$benchmark, NA)
  if (any(after)) message(sum(after), " submissions after the deadline are ignored on the page.")
  scored <- scored[!after]

  list(scored_days = as.character(scored_days),
       actual = unname(r3(actual)),
       n_known = sum(!is.na(actual)), deadline = deadline_utc,
       month_actual = if (is.na(month_actual)) NA else r3(month_actual),
       n_groups = length(unique(vapply(Filter(function(s) !s$benchmark, scored), `[[`, "", "group"))),
       subs = unname(scored))
}
