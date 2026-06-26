# 📦 Install required packages
required_packages <- c("dplyr", "readr", "stringr", "lubridate")
installed <- installed.packages()[, "Package"]
for (pkg in required_packages) {
  if (!pkg %in% installed) install.packages(pkg, dependencies = TRUE)
}

# 📚 Load libraries
library(dplyr)
library(readr)
library(stringr)
library(lubridate)

# 📁 Path to your ATP match data folder
data_folder <- "C:/Users/eshor/OneDrive/tennis/tennis_atp-master"
file_list <- list.files(data_folder, pattern = "atp_matches_\\d{4}\\.csv", full.names = TRUE)

# 🔁 Load valid matches from consistent tournaments
valid_levels <- c("G", "M", "A", "B", "F")
all_data <- list()

for (file in file_list) {
  tryCatch({
    df <- read_csv(file, show_col_types = FALSE)
    required_cols <- c("tourney_date", "tourney_name", "tourney_level", "winner_name", "loser_name", "score", "round")
    if (all(required_cols %in% names(df))) {
      df <- df %>%
        select(all_of(required_cols)) %>%
        filter(tourney_level %in% valid_levels,
               !is.na(winner_name), !is.na(loser_name),
               str_detect(tourney_date, "^\\d+$"),
               nchar(tourney_date) == 8) %>%
        mutate(tourney_date = as.integer(tourney_date))
      all_data[[file]] <- df
      message("✅ Loaded: ", basename(file), " with ", nrow(df), " matches.")
    } else {
      message("❌ Skipped (missing columns): ", basename(file))
    }
  }, error = function(e) {
    message("❌ Error reading: ", basename(file), " – ", e$message)
  })
}

# 🔢 Round ordering — tourney_date is the tournament START date, not the match
#    date, so every match in an event shares a date. To keep the lineal title
#    correct we must process earlier rounds before later ones (a final must not
#    be handled before the quarter-final that fed it).
round_order_map <- c(
  "RR"   = 1,   # round robin (group stage, e.g. Tour Finals)
  "R128" = 2,
  "R64"  = 3,
  "R32"  = 4,
  "R16"  = 5,
  "QF"   = 6,
  "SF"   = 7,
  "BR"   = 8,   # bronze / 3rd-place play-off (before the final)
  "F"    = 9
)

# 📊 Combine and order matches properly
atp_data <- bind_rows(all_data) %>%
  filter(tourney_date >= 19680422) %>%
  mutate(round_order = round_order_map[round],
         # any unrecognised round label sorts last within its tournament
         round_order = ifelse(is.na(round_order), 99L, round_order)) %>%
  arrange(tourney_date, tourney_name, round_order, winner_name, loser_name)

last_match_raw <- max(atp_data$tourney_date)
last_match_date <- as.Date(as.character(last_match_raw), format = "%Y%m%d")

# 🏆 Build the Ultimate World Champion lineage
champion <- "Owen Davidson"
lineage <- list()

for (i in 1:nrow(atp_data)) {
  match <- atp_data[i, ]
  if (champion %in% c(match$winner_name, match$loser_name)) {
    if (champion == match$loser_name) {
      new_champion <- match$winner_name
      lineage[[length(lineage) + 1]] <- data.frame(
        date = match$tourney_date,
        match_date = as.Date(as.character(match$tourney_date), format = "%Y%m%d"),
        from = champion,
        to = new_champion,
        tournament = match$tourney_name,
        score = match$score,
        stringsAsFactors = FALSE
      )
      champion <- new_champion
    }
  }
}

lineage_df <- do.call(rbind, lineage)

# ➕ Add start/end dates to compute reigns.
#    A reign begins when a player WINS the title (the `to` column) and ends when
#    the next title change happens. The opening reign belongs to the first
#    champion, Owen Davidson, from the first Open Era match until his first loss.
first_match_date <- as.Date("1968-04-22")

reigns <- data.frame(
  champion   = c("Owen Davidson", lineage_df$to),
  start_date = c(first_match_date, lineage_df$match_date),
  stringsAsFactors = FALSE
) %>%
  mutate(end_date = lead(start_date, default = last_match_date),
         reign_days = as.integer(end_date - start_date),
         reign_matches = NA_integer_)

# 🧮 Count number of matches played by each champion during their reign
# Precompute match_date once
atp_data <- atp_data %>%
  mutate(match_date = as.Date(as.character(tourney_date), format = "%Y%m%d"))

# Count matches in reigns without recomputing
for (i in 1:nrow(reigns)) {
  champ <- reigns$champion[i]
  start <- reigns$start_date[i]
  end <- reigns$end_date[i]
  
  reign_matches <- atp_data %>%
    filter(match_date >= start & match_date < end,
           winner_name == champ | loser_name == champ) %>%
    nrow()
  
  reigns$reign_matches[i] <- reign_matches
}

# 📊 Summary by player
summary_df <- reigns %>%
  group_by(champion) %>%
  summarise(
    reigns = n(),
    total_days = sum(reign_days),
    total_matches = sum(reign_matches),
    .groups = "drop"
  ) %>%
  arrange(desc(total_days))

# 🥇 Top reigns
top_days <- reigns %>% arrange(desc(reign_days)) %>% head(10)
top_matches <- reigns %>% arrange(desc(reign_matches)) %>% head(10)

# 💾 Export all
write_csv(lineage_df, "C:/Users/eshor/OneDrive/tennis/ultimate_world_champion_lineage.csv")
write_csv(reigns,     "C:/Users/eshor/OneDrive/tennis/reign_periods.csv")
write_csv(summary_df, "C:/Users/eshor/OneDrive/tennis/champion_summary.csv")
write_csv(top_days,   "C:/Users/eshor/OneDrive/tennis/top_reigns_by_days.csv")
write_csv(top_matches,"C:/Users/eshor/OneDrive/tennis/top_reigns_by_matches.csv")

# ✅ Final printout
cat("\n✅ Ultimate World Champion lineage saved.\n")
cat("📅 Last match date processed:", format(last_match_date, "%Y-%m-%d"), "\n")
cat("👑 Current Ultimate World Champion:", champion, "\n")
cat("\n📈 Top 5 Longest Title Reigns (by days):\n")
print(top_days[, c("champion", "start_date", "end_date", "reign_days")])
cat("\n📈 Top 5 Longest Title Reigns (by matches):\n")
print(top_matches[, c("champion", "start_date", "end_date", "reign_matches")])
