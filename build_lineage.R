# =============================================================================
# Ultimate World Champion - chain-integrity build
#
# Single-baton lineal title over a Sackmann historical backbone spliced to a
# TennisMyLife (TML) live tail. Produces the chain plus a flagged shortlist of
# every baton hop that is ordering-ambiguous, non-completed, or not corroborated
# by the independent source, each tagged with links to adjudicate it.
#
# Methodology toggles are at the top. Defaults: 1968 start, RET counts as a loss,
# W/O and DEF do not, Davis Cup and Olympics excluded.
# =============================================================================

suppressMessages({
  library(dplyr); library(readr); library(stringr)
})

# ----------------------------- CONFIG / TOGGLES ------------------------------
START_DATE        <- 19680422   # Open Era start (Bournemouth)
SEED_CHAMPION     <- "Owen Davidson"  # first holder, by the project's premise (winner of the first Open Era match)
SPLICE_YEAR       <- 2024       # Sackmann backbone through this year; TML tail after it
END_YEAR          <- 2026
RET_COUNTS        <- TRUE       # a retirement passes the title
WO_DEF_COUNT      <- FALSE      # walkovers and defaults do NOT pass the title
# Do round-robin losses pass the lineal title? RR ordering is unrecoverable from
# any dataset, so treating the round-robin as a non-eliminating pool stage (FALSE)
# removes that ambiguity. Overridable via env var for A/B measurement.
RR_PASSES_TITLE   <- as.logical(Sys.getenv("RR_PASSES_TITLE", "FALSE"))
INCLUDE_DAVIS_CUP <- FALSE      # tourney_level "D"
INCLUDE_OLYMPICS  <- FALSE      # tourney_level "O"
FRAGILE_BEFORE    <- 1985       # hops before this year are cross-checked and flagged as early-era

SACK_DIR     <- "C:/Users/eshor/OneDrive/Tennis/tennis_atp-master"
TML_DIR      <- "C:/Users/eshor/OneDrive/Tennis/tml_data"
DATAHUB_FILE <- "C:/Users/eshor/OneDrive/Tennis/datahub_match_scores_1968-1990.csv"
UTS_FILE     <- "C:/Users/eshor/OneDrive/Tennis/uts_matches.csv"
OUT_DIR      <- "C:/Users/eshor/OneDrive/Tennis"

valid_levels <- c("G", "M", "A", "F", "250", "500")
if (INCLUDE_DAVIS_CUP) valid_levels <- c(valid_levels, "D")
if (INCLUDE_OLYMPICS)  valid_levels <- c(valid_levels, "O")

round_order_map <- c(RR=1, R128=2, R64=3, R32=4, R16=5, QF=6, SF=7, BR=8, F=9)

# ------------------------------- HELPERS -------------------------------------

# Canonical player key: lowercases, strips accents and punctuation so the two
# sources' name conventions line up (e.g. "Auger-Aliassime" == "Auger Aliassime",
# "O'Connell" == "Oconnell", "J.J. Wolf" == "J J Wolf").
canon <- function(x) {
  x <- tolower(trimws(ifelse(is.na(x), "", x)))
  x <- stringi::stri_trans_general(x, "Latin-ASCII")   # robust accent folding (Nastase, etc.)
  x <- ifelse(is.na(x), "", x)
  x <- gsub("'", "", x)            # apostrophe -> nothing
  x <- gsub("[.\\-]", " ", x)      # period, hyphen -> space
  x <- gsub("[^a-z ]", "", x)      # drop transliteration artefacts
  x <- gsub("\\s+", " ", x)
  x <- trimws(x)
  x <- gsub("\\s+(sr|jr|ii|iii|iv)$", "", x)   # drop generational suffixes (Sr./Jr.)
  # Cross-source name aliases: same player, different conventions between sources.
  hit <- match(x, names(NAME_ALIASES))
  ifelse(is.na(hit), x, NAME_ALIASES[hit])
}

# Pancho Gonzalez: Sackmann "Richard Gonzalez" vs the ATP-archive sources'
# "Richard Pancho Gonzales" (middle name + z/s spelling) are the same player.
NAME_ALIASES <- c(
  "richard pancho gonzales" = "richard gonzalez",
  "pancho gonzales"         = "richard gonzalez",
  "richard gonzales"        = "richard gonzalez"
)

# Hops hand-verified against primary sources during manual adjudication. These are
# real matches the independent datahub scrape omits (WCT / minor events); recording
# the verification (keyed by year + winner + loser) stops them counting as
# unconfirmed. Only matches actually checked are listed; unverifiable ones stay flagged.
MANUAL_VERIFIED_RAW <- data.frame(
  year   = c(1971, 1971, 1973, 1973, 1974, 1974, 1975, 1976, 1976),
  winner = c("Bob Lutz", "Manuel Orantes", "Ove Bengtson", "Jaime Fillol", "Bob Lutz",
             "John Newcombe", "Bob Lutz", "Bob Lutz", "Harold Solomon"),
  loser  = c("Jeff Borowiak", "Bob Lutz", "Ilie Nastase", "Ove Bengtson", "Dick Stockton",
             "Bob Lutz", "John Alexander", "Roscoe Tanner", "Bob Lutz"),
  source = c("Wikipedia 1971 WCT circuit (Lutz won Cologne)",
             "Wikipedia 1971 WCT circuit (Orantes won Barcelona)",
             "Sackmann full draw; Jacksonville won by Connors (datahub/UTS corroborate the SF)",
             "Sackmann full draw; Jacksonville won by Connors (datahub/UTS corroborate the SF)",
             "ITF/Wikipedia New Orleans WCT 1974 (won by Newcombe)",
             "ITF/Wikipedia New Orleans WCT 1974 (won by Newcombe)",
             "Wikipedia 1975 Tokyo WCT (won by Lutz)",
             "Wikipedia 1976 Island Holidays Classic, Maui",
             "Wikipedia 1976 Island Holidays Classic (Solomon d. Lutz 6-3 5-7 7-5)"),
  stringsAsFactors = FALSE
)
manual_src <- setNames(MANUAL_VERIFIED_RAW$source,
                       paste(MANUAL_VERIFIED_RAW$year,
                             canon(MANUAL_VERIFIED_RAW$winner),
                             canon(MANUAL_VERIFIED_RAW$loser)))

# Classify a scoreline as a completed match, retirement, walkover, or default.
result_type <- function(s) {
  s <- toupper(ifelse(is.na(s), "", s))
  out <- rep("PLAYED", length(s))
  out[grepl("RET", s)] <- "RET"
  out[grepl("DEF", s)] <- "DEF"
  out[grepl("W/?O|WALKOVER", s)] <- "WO"
  out
}

need <- c("tourney_date", "tourney_name", "tourney_level", "winner_name", "loser_name", "score", "round")

load_year <- function(path, src) {
  if (!file.exists(path)) return(NULL)
  df <- suppressWarnings(read_csv(path, show_col_types = FALSE, progress = FALSE))
  if (!all(need %in% names(df))) return(NULL)
  df %>%
    select(all_of(need)) %>%
    mutate(tourney_date = as.character(tourney_date)) %>%
    filter(tourney_level %in% valid_levels,
           !is.na(winner_name), !is.na(loser_name),
           grepl("^[0-9]{8}$", tourney_date)) %>%
    # Belt-and-braces scope exclusion by name: one source codes the 2000 Olympics
    # as a regular "A" event, so the level filter alone would leak it in.
    { if (!INCLUDE_OLYMPICS)  filter(., !grepl("olympic", tolower(tourney_name))) else . } %>%
    { if (!INCLUDE_DAVIS_CUP) filter(., !grepl("davis cup", tolower(tourney_name))) else . } %>%
    mutate(tourney_date = as.integer(tourney_date), source = src)
}

prep <- function(df) {
  df %>%
    mutate(round_order = ifelse(round %in% names(round_order_map),
                                round_order_map[round], 99L),
           round_order = as.integer(round_order),
           match_date  = as.Date(as.character(tourney_date), format = "%Y%m%d"),
           year        = as.integer(substr(tourney_date, 1, 4)),
           w_canon     = canon(winner_name),
           l_canon     = canon(loser_name),
           restype     = result_type(score)) %>%
    arrange(tourney_date, tourney_name, round_order, winner_name, loser_name)
}

# ------------------------------- LOAD DATA -----------------------------------

# Backbone (Sackmann local) + tail (TML), spliced at SPLICE_YEAR.
backbone <- bind_rows(lapply(1968:SPLICE_YEAR, function(y)
  load_year(file.path(SACK_DIR, sprintf("atp_matches_%d.csv", y)), "backbone")))
tail_df <- bind_rows(lapply((SPLICE_YEAR + 1):END_YEAR, function(y)
  load_year(file.path(TML_DIR, sprintf("%d.csv", y)), "tail")))

atp <- prep(bind_rows(backbone, tail_df)) %>% filter(tourney_date >= START_DATE)

# Independent cross-check source: full TML, same filter, as a fast lookup set
# keyed on date + canonical winner + canonical loser.
tml_all <- prep(bind_rows(lapply(1968:END_YEAR, function(y)
  load_year(file.path(TML_DIR, sprintf("%d.csv", y)), "tml")))) %>%
  filter(tourney_date >= START_DATE)
tml_set <- new.env(hash = TRUE, parent = emptyenv())
invisible(apply(cbind(tml_all$tourney_date, tml_all$w_canon, tml_all$l_canon), 1,
                function(r) assign(paste(r[1], r[2], r[3]), TRUE, envir = tml_set)))
in_tml <- function(date, wc, lc) exists(paste(date, wc, lc), envir = tml_set, inherits = FALSE)

# Genuinely independent third source for the fragile early era (1968-1990):
# datahub's standalone ATP-site scrape. No dates, so keyed on year + names.
dh <- suppressWarnings(read_csv(DATAHUB_FILE, show_col_types = FALSE, progress = FALSE)) %>%
  transmute(year = as.integer(substr(tourney_year_id, 1, 4)),
            w_canon = canon(winner_name), l_canon = canon(loser_name))
dh_set <- new.env(hash = TRUE, parent = emptyenv())
invisible(apply(cbind(dh$year, dh$w_canon, dh$l_canon), 1,
                function(r) assign(paste(trimws(r[1]), r[2], r[3]), TRUE, envir = dh_set)))
# +/-1 year window absorbs calendar-vs-season filing (e.g. the 1975 Australian
# Open played in Dec 1974, and events filed under the prior season).
in_dh <- function(year, wc, lc) {
  if (year > 1991) return(FALSE)
  any(vapply(c(year - 1, year, year + 1),
             function(y) exists(paste(y, wc, lc), envir = dh_set, inherits = FALSE), logical(1)))
}

# Fourth source: UTS (Ultimate Tennis Statistics) export. Sackmann-derived but
# heavily corrected, so it corroborates (without adding independence) and helps
# tell a real-but-ATP-archive-omitted match from a genuinely isolated one.
uts <- suppressWarnings(read_csv(UTS_FILE, show_col_types = FALSE, progress = FALSE)) %>%
  transmute(year = as.integer(year), w_canon = canon(winner_name), l_canon = canon(loser_name))
uts_set <- new.env(hash = TRUE, parent = emptyenv())
invisible(apply(cbind(uts$year, uts$w_canon, uts$l_canon), 1,
                function(r) assign(paste(trimws(r[1]), r[2], r[3]), TRUE, envir = uts_set)))
uts_max_year <- max(uts$year, na.rm = TRUE)
in_uts <- function(year, wc, lc) {
  if (year > uts_max_year + 1) return(FALSE)
  any(vapply(c(year - 1, year, year + 1),
             function(y) exists(paste(y, wc, lc), envir = uts_set, inherits = FALSE), logical(1)))
}

cat(sprintf("Loaded %d qualifying matches (backbone+tail); cross-checks: TML=%d, datahub(1968-90)=%d, UTS=%d.\n",
            nrow(atp), nrow(tml_all), nrow(dh), nrow(uts)))

# --------------------------- BUILD THE BATON ---------------------------------

n  <- nrow(atp)
wc <- atp$w_canon; lc <- atp$l_canon
wn <- atp$winner_name; ln <- atp$loser_name
rt <- atp$restype; rd <- atp$round

# Seed: Owen Davidson holds the title from the first Open Era match. The opening
# order at Bournemouth is itself ambiguous, so the seed is flagged same-day below.
champ <- canon(SEED_CHAMPION); champ_disp <- SEED_CHAMPION
hops <- list()
hops[[1]] <- list(hop = 0L, tourney_date = atp$tourney_date[1], match_date = atp$match_date[1],
                  from = NA_character_, to = champ_disp, from_canon = NA_character_, to_canon = champ,
                  tournament = atp$tourney_name[1], round = atp$round[1], score = NA_character_,
                  result = "SEED", source = atp$source[1], year = atp$year[1])

for (i in seq_len(n)) {
  if (lc[i] == champ) {
    hold <- ((rt[i] %in% c("WO", "DEF")) && !WO_DEF_COUNT) ||
            (rt[i] == "RET" && !RET_COUNTS) ||
            (rd[i] == "RR" && !RR_PASSES_TITLE)
    if (hold) next                      # title successfully "defended" by a non-loss
    hops[[length(hops) + 1]] <- list(
      hop = length(hops), tourney_date = atp$tourney_date[i], match_date = atp$match_date[i],
      from = champ_disp, to = wn[i], from_canon = champ, to_canon = wc[i],
      tournament = atp$tourney_name[i], round = atp$round[i], score = atp$score[i],
      result = rt[i], source = atp$source[i], year = atp$year[i])
    champ <- wc[i]; champ_disp <- wn[i]
  }
}

lin <- bind_rows(lapply(hops, as.data.frame, stringsAsFactors = FALSE))

# ------------------------------- FLAGGING ------------------------------------

lin$round_order <- ifelse(lin$round %in% names(round_order_map),
                          round_order_map[lin$round], 99L)
prev_date <- c(NA, head(as.numeric(lin$match_date), -1))
prev_tour <- c(NA, head(lin$tournament, -1))
prev_ro   <- c(NA, head(lin$round_order, -1))
lin <- lin %>%
  mutate(
    # Genuine ordering ambiguity: a hop sharing its date with the previous hop is
    # only unsafe if round_order cannot sequence them, i.e. it is in a different
    # tournament or in the same/earlier round. A clean R32 -> SF -> F cascade
    # inside one event shares a date but is correctly ordered, so it is NOT flagged.
    f_same_day  = !is.na(prev_date) & as.numeric(match_date) == prev_date &
                  (tournament != prev_tour | round_order <= prev_ro),
    # Non-completed result that nonetheless moved (or was tested against) the title.
    f_nonplayed = result %in% c("RET", "WO", "DEF"),
    # Fragile early era, where compilations are known to disagree.
    f_early     = year < FRAGILE_BEFORE,
    in_tml_hit  = mapply(in_tml, tourney_date, to_canon, from_canon),
    in_dh_hit   = mapply(in_dh, year, to_canon, from_canon),
    in_uts_hit  = mapply(in_uts, year, to_canon, from_canon),
    # "confirmed" uses only the genuinely independent source (datahub, an ATP-site
    # scrape) for <=1990, and TML for later years. corrob lists every source that
    # carries the match: S=Sackmann backbone (always), TML, DH=datahub, UTS.
    mkey        = paste(year, to_canon, from_canon),
    in_manual   = mkey %in% names(manual_src),
    manual_source = unname(manual_src[mkey]),
    # "confirmed" = corroborated by the independent source, or hand-verified.
    confirmed   = ifelse(year <= 1990, in_dh_hit, in_tml_hit) | in_manual,
    f_disagree  = source != "tail" & !is.na(from_canon) & !confirmed,
    corrob = ifelse(is.na(from_canon), "seed",
              paste0("S",
                     ifelse(in_tml_hit, "+TML", ""),
                     ifelse(in_dh_hit,  "+DH",  ""),
                     ifelse(in_uts_hit, "+UTS", ""),
                     ifelse(in_manual,  "+man", "")))
  )
# Seed ordering is inherently ambiguous (many same-day opening-round matches).
lin$f_same_day[1] <- TRUE

# Disqualifying for "verified-sound": contested ordering or a source disagreement.
lin <- lin %>% mutate(contested = f_same_day | f_disagree)
worst_contested <- suppressWarnings(max(lin$year[lin$contested], na.rm = TRUE))
verified_since  <- if (is.finite(worst_contested)) worst_contested + 1 else min(lin$year)

# ----------------------------- RESOLUTION LINKS ------------------------------
enc <- function(x) utils::URLencode(x, reserved = TRUE)
wiki_link <- function(y, t) paste0("https://en.wikipedia.org/w/index.php?search=", enc(paste(y, t, "tennis")))
atp_link  <- function(y, t) paste0("https://www.google.com/search?q=", enc(paste0("site:atptour.com ", y, " ", t)))

flagged <- lin %>%
  filter(f_same_day | f_disagree | f_nonplayed) %>%
  mutate(
    flags = trimws(paste(
      ifelse(f_same_day,  "same-day", ""),
      ifelse(f_disagree,  "source-disagree", ""),
      ifelse(f_nonplayed, paste0("result:", result), ""),
      ifelse(f_early,     "early-era", ""))),
    flags = gsub("\\s+", " ", flags),
    wikipedia = mapply(wiki_link, year, tournament),
    atp_archive = mapply(atp_link, year, tournament)
  ) %>%
  select(hop, match_date, from, to, tournament, round, score, result, source,
         corrob, flags, year, wikipedia, atp_archive)

# ------------------------------- OUTPUTS -------------------------------------
lineage_out <- lin %>%
  transmute(hop, date = tourney_date, match_date, from, to, tournament, round, score,
            result, source, corrob, year,
            same_day = f_same_day, source_disagree = f_disagree,
            non_played = f_nonplayed, early_era = f_early, manual_source)

write_csv(lineage_out, file.path(OUT_DIR, "uwc_lineage.csv"), na = "")
write_csv(flagged,     file.path(OUT_DIR, "uwc_baton_flags.csv"), na = "")

provenance <- tibble::tibble(
  key = c("start_date", "splice_year", "end_year", "backbone_source", "tail_source",
          "independent_cross_check", "corroborating_cross_check", "ret_counts", "wo_def_count",
          "rr_passes_title", "include_davis_cup", "include_olympics", "fragile_before", "valid_levels",
          "verified_since", "current_champion", "current_since", "total_baton_hops",
          "flagged_hops", "manually_verified_hops", "truly_isolated_hops", "generated"),
  value = c(START_DATE, SPLICE_YEAR, END_YEAR, "Jeff Sackmann tennis_atp (local frozen 1968-2024)",
            "TennisMyLife (live 2025-2026)", "datahub ATP-archive scrape (1968-1990)",
            "UTS / Ultimate Tennis Statistics (<=2021)", RET_COUNTS, WO_DEF_COUNT, RR_PASSES_TITLE,
            INCLUDE_DAVIS_CUP, INCLUDE_OLYMPICS, FRAGILE_BEFORE, paste(valid_levels, collapse = ","),
            verified_since, champ_disp, format(max(lin$match_date)), nrow(lin), nrow(flagged),
            sum(lin$in_manual), sum(lin$corrob == "S"), as.character(Sys.Date()))
)
write_csv(provenance, file.path(OUT_DIR, "uwc_provenance.csv"))

# ------------------------------- SUMMARY -------------------------------------
cat("\n================ CHAIN-INTEGRITY SUMMARY ================\n")
cat(sprintf("Baton hops (incl. seed): %d\n", nrow(lin)))
cat(sprintf("Current champion: %s (since %s)\n", champ_disp, format(max(lin$match_date))))
cat(sprintf("Empirical verified-sound since: %d\n", verified_since))
cat(sprintf("Flagged hops to adjudicate: %d  (same-day=%d, source-disagree=%d, non-played=%d)\n",
            nrow(flagged), sum(lin$f_same_day), sum(lin$f_disagree), sum(lin$f_nonplayed)))
cat(sprintf("  of which pre-%d (fragile era): %d\n", FRAGILE_BEFORE, sum(flagged$year < FRAGILE_BEFORE)))
cat("\nEarly-era triangulation (baton hops 1968-1990, by which sources carry the match):\n")
early <- lin %>% filter(year <= 1990, !is.na(from_canon))
print(as.data.frame(table(early$corrob)), row.names = FALSE)
cat(sprintf("  -> %d of %d confirmed by the independent datahub scrape; %d truly isolated (Sackmann only, no cross-source).\n",
            sum(grepl("DH", early$corrob)), nrow(early), sum(early$corrob == "S")))
cat("\nLast 8 baton hops:\n")
print(tail(lineage_out[, c("match_date", "from", "to", "tournament", "round", "score", "source")], 8), row.names = FALSE)
cat("\nFirst 12 flagged hops (the early-era shortlist):\n")
print(head(flagged[, c("match_date", "from", "to", "tournament", "round", "flags")], 12), row.names = FALSE)
