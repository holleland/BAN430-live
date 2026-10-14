# The "where are we now" figure for the mandatory assignment, used at the start of
# every lecture after the assignment was released, and as the data source of the
# live web page (see the folder live/).
#
# electricity_status_data()  computes everything: the price series, the seasonal
#                            naive forecast (benchmark) and the distribution of
#                            the monthly average.
# electricity_status()       draws the figure used on the slides:
#   Left panel : the NO5 daily price, with the days after the release in another
#                colour, and the seasonal naive forecast up to the end of the month.
#   Right panel: the distribution of the monthly average implied by that forecast.
#
# In a Quarto/Beamer deck (no code shown on the slide):
#
#   ```{r, echo = FALSE, fig.width = 9, fig.height = 4.2, out.width = 540, out.height = 252}
#   source("../Mandatory_electricity/status_plot.R")
#   electricity_status()
#   ```
#
# The prices are fetched with update_elprices() every time it is run. Without an
# internet connection, the snapshot in the ban430data package is used instead.
# Needs: fpp3, ban430data, patchwork.

electricity_status_data <- function(release = as.Date("2026-10-07"),
                                    month_start = as.Date("2026-10-01"),
                                    from = as.Date("2026-09-01"),
                                    area = "NO5",
                                    n_paths = 1000,
                                    seed = 1) {
  suppressPackageStartupMessages({
    library(fpp3)
    library(ban430data)
  })
  # tomorrow's prices are published at about 13:00 Norwegian time, so ask for them too
  # (days that are not published yet are skipped)
  oslo_today <- as.Date(format(Sys.time(), tz = "Europe/Oslo"))
  prices <- tryCatch(ban430data::update_elprices(to = oslo_today + 1),
                     error = function(e) ban430data::elprices_daily)
  no5 <- prices %>%
    dplyr::filter(area == !!area, date >= as.Date("2025-10-01")) %>%
    dplyr::select(date, price)
  last_day <- max(no5$date)
  month_end <- seq(month_start, by = "month", length.out = 2)[2] - 1
  n_days <- as.integer(month_end - month_start) + 1
  n_ahead <- as.integer(month_end - last_day)

  obs <- no5 %>%
    tibble::as_tibble() %>%
    dplyr::filter(date >= from) %>%
    dplyr::mutate(period = factor(dplyr::if_else(date > release, "After the release", "Before release"),
                                  levels = c("Before release", "After the release")))
  days_known <- no5 %>%
    tibble::as_tibble() %>%
    dplyr::filter(date >= month_start, date <= month_end)
  known_sum <- sum(days_known$price)
  avg_so_far <- if (nrow(days_known) > 0) mean(days_known$price) else NA_real_

  fan <- NULL
  month_sims <- NULL
  if (n_ahead > 0) {
    fit <- no5 %>% fabletools::model(snaive = fable::SNAIVE(price ~ lag("week")))
    set.seed(seed)
    paths <- fit %>%
      fabletools::generate(h = n_ahead, times = n_paths, bootstrap = TRUE) %>%
      tibble::as_tibble() %>%
      dplyr::select(.rep, date, .sim)
    fan <- paths %>%
      dplyr::group_by(date) %>%
      dplyr::summarise(q05 = quantile(.sim, 0.05), q25 = quantile(.sim, 0.25),
                       q50 = quantile(.sim, 0.5), q75 = quantile(.sim, 0.75),
                       q95 = quantile(.sim, 0.95), .groups = "drop")
    month_sims <- paths %>%
      dplyr::group_by(.rep) %>%
      dplyr::summarise(total = sum(.sim), .groups = "drop") %>%
      dplyr::mutate(month_mean = (known_sum + total) / n_days)
  }

  list(area = area, release = release, month_start = month_start, month_end = month_end,
       from = from, n_days = n_days, n_ahead = n_ahead, last_day = last_day,
       no5 = tibble::as_tibble(no5), obs = obs, days_known = days_known,
       avg_so_far = avg_so_far, fan = fan, month_sims = month_sims,
       updated = Sys.time())
}

electricity_status <- function(release = as.Date("2026-10-07"),
                               month_start = as.Date("2026-10-01"),
                               from = as.Date("2026-09-01"),
                               area = "NO5",
                               n_paths = 1000,
                               seed = 1,
                               data = NULL) {
  suppressPackageStartupMessages({
    library(fpp3)
    library(patchwork)
  })
  d <- if (is.null(data)) {
    electricity_status_data(release, month_start, from, area, n_paths, seed)
  } else data
  fan <- d$fan; month_sims <- d$month_sims; obs <- d$obs
  avg_so_far <- d$avg_so_far; days_known <- d$days_known
  month_end <- d$month_end; last_day <- d$last_day

  # month names that do not depend on the language settings of the computer
  mon <- function(x) month.abb[as.integer(format(x, "%m"))]
  lab_date <- function(x) paste(as.integer(format(x, "%d")), mon(x))
  navy <- "#00395A"
  orange <- "#D55E00"
  green <- "#009E73"
  purple <- "#CC79A7"

  # repeat the release day in the second colour, so that the line is continuous
  obs_plot <- dplyr::bind_rows(
    obs,
    obs %>% dplyr::filter(date == release) %>% dplyr::mutate(period = "After the release")
  )

  p1 <- ggplot2::ggplot() +
    ggplot2::geom_vline(xintercept = release, linetype = "dotted", colour = "grey40") +
    ggplot2::annotate("text", x = release, y = Inf, label = " Assignment published",
                      hjust = 0, vjust = 1.6, size = 3, colour = "grey30")
  if (!is.null(fan)) {
    p1 <- p1 +
      ggplot2::geom_ribbon(data = fan, ggplot2::aes(date, ymin = q05, ymax = q95), fill = navy, alpha = 0.15) +
      ggplot2::geom_ribbon(data = fan, ggplot2::aes(date, ymin = q25, ymax = q75), fill = navy, alpha = 0.3) +
      ggplot2::geom_line(data = fan, ggplot2::aes(date, q50), colour = navy, linetype = "dashed")
  }

  mname <- month.name[as.integer(format(month_start, "%m"))]
  lab_avg <- sprintf("%s average so far: %.2f", mname, avg_so_far)
  lab_proj <- if (!is.null(month_sims)) sprintf("Projected %s average: %.2f", mname,
                                                  median(month_sims$month_mean)) else NA_character_
  cols <- c("Before release" = "black", "After the release" = orange)
  cols[lab_avg] <- green
  if (!is.na(lab_proj)) cols[lab_proj] <- purple

  if (!is.na(avg_so_far)) {
    p1 <- p1 + ggplot2::geom_segment(
      data = data.frame(x = month_start, xend = max(days_known$date), y = avg_so_far, label = lab_avg),
      ggplot2::aes(x = x, xend = xend, y = y, yend = y, colour = label), linewidth = 1)
  }
  if (!is.na(lab_proj)) {
    p1 <- p1 + ggplot2::geom_segment(
      data = data.frame(x = month_start, xend = month_end, y = median(month_sims$month_mean), label = lab_proj),
      ggplot2::aes(x = x, xend = xend, y = y, yend = y, colour = label), linewidth = 1, linetype = "dashed")
  }

  p1 <- p1 +
    ggplot2::geom_line(data = obs_plot, ggplot2::aes(date, price, colour = period), linewidth = 0.7) +
    ggplot2::scale_colour_manual(values = cols, breaks = names(cols), name = NULL) +
    ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2, byrow = TRUE)) +
    ggplot2::scale_x_date(limits = c(d$from, month_end), labels = lab_date) +
    ggplot2::labs(x = NULL, y = "NOK/kWh, excluding VAT",
                  title = paste0(d$area, " daily price, known up to ", lab_date(last_day)),
                  subtitle = "Dashed line and shading: seasonal naive forecast (median, 50% and 90%)") +
    ggplot2::theme(legend.position = "bottom", legend.margin = ggplot2::margin(0, 0, 0, 0),
                   plot.subtitle = ggplot2::element_text(size = 8))

  if (is.null(month_sims)) {
    # the month is over: show the actual average
    actual <- sum(days_known$price) / d$n_days
    p2 <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0, y = 0, label = sprintf("Final average:\n%.2f NOK/kWh", actual), size = 5) +
      ggplot2::theme_void()
  } else {
    q <- quantile(month_sims$month_mean, c(0.05, 0.5, 0.95))
    p2 <- ggplot2::ggplot(month_sims, ggplot2::aes(month_mean)) +
      ggplot2::geom_histogram(bins = 30, fill = navy, alpha = 0.6, colour = "white") +
      ggplot2::geom_vline(xintercept = q[2], colour = purple, linewidth = 1, linetype = "dashed") +
      ggplot2::labs(x = "NOK/kWh, excluding VAT", y = NULL,
                    title = paste0(mname, " average"),
                    subtitle = sprintf("Median %.2f, 90%% interval [%.2f, %.2f]", q[2], q[1], q[3])) +
      ggplot2::theme(axis.text.y = ggplot2::element_blank(), axis.ticks.y = ggplot2::element_blank(),
                     plot.subtitle = ggplot2::element_text(size = 8))
  }

  p1 + p2 + patchwork::plot_layout(widths = c(2.2, 1))
}
