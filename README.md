# The Ultimate World Champion

A fictional **lineal "world champion" title** for men's tennis, in the spirit of boxing's
lineal championship. There is one champion at a time, and the title only ever changes hands
**on the court**: when the reigning champion loses a match, the winner becomes the new champion.

- **First holder:** Owen Davidson, as winner of the first Open Era match (Bournemouth, 22 April 1968).
- **Current champion:** **Pete Sampras**, since 26 August 2002 (see [Dormancy](#the-rules) below).
- **Live site:** an interactive page (`index.html`) with the lineage, reign records, a timeline,
  and a full data-integrity audit. Intended for hosting on GitHub Pages.

This is a recreational data project, not an official record. It is built to be **auditable**:
every title-changing match is cross-checked against independent data sources, and the matches
that can't be cleanly corroborated are flagged and listed for manual review.

---

## Contents

| File | Purpose |
| --- | --- |
| `index.html` | The interactive website (lineage, reigns, timeline, integrity panel, downloads). |
| `build_lineage.R` | **Authoritative pipeline.** Builds the audited four-source chain and the `uwc_*` outputs. |
| `tennis.R` | Original single-source pipeline. Produces the reign/summary CSVs the site's display tables read. |
| `refresh.ps1` | One-command refresh: pull the latest data, rebuild, commit, push. |
| `uwc_lineage.csv` | The audited title lineage: every baton hop, its source, and corroboration tags. |
| `uwc_baton_flags.csv` | The shortlist of title changes needing review, each with links to primary sources. |
| `uwc_provenance.csv` | Run metadata: sources, toggles, the verified-since year, generation date. |
| `ultimate_world_champion_lineage.csv` | Lineage feed for the site's main table (from `tennis.R`). |
| `reign_periods.csv`, `champion_summary.csv`, `top_reigns_by_*.csv` | Reign records for the site's tables and timeline. |

Large input datasets (`tennis_atp-master/`, `tml_data/`, `datahub_*.csv`, `uts_matches.csv`)
are **git-ignored**; they are reproducible from their sources (see [Reproducing the build](#reproducing-the-build)).

---

## The website

Open `index.html` through a local server or GitHub Pages (it loads CSVs via JavaScript, so it
will not work from a bare `file://` path). It shows:

- the current champion and a **"verified-sound since 1983"** badge;
- a **reign timeline** drawn to scale, with the longest-holding champions colour-coded;
- **most days as champion**, **longest single reigns** (by days and by matches defended);
- the **full title lineage** and **every individual reign**, all searchable and sortable;
- a **Data sources and chain integrity** panel: the provenance, a triangulation headline, and an
  interactive table of every flagged title change with links out to Wikipedia and the ATP archive.

To serve it locally:

```sh
cd /path/to/Tennis
python -m http.server 8000
# then open http://localhost:8000/index.html
```

---

## Methodology

### The rules

1. **Seed.** The first champion is Owen Davidson, defined as the holder from the first Open Era
   match (Bournemouth, 22 April 1968).
2. **Succession.** The title passes whenever the reigning champion loses a qualifying match. The
   winner of that match becomes champion until they, in turn, lose.
3. **Walkovers and retirements.** A **retirement (RET)** counts as a loss and passes the title (the
   champion failed to finish). A **walkover (W/O)** or **default (DEF)** does **not** pass the title
   (no contested match took place). These are toggles; the defaults are RET = pass, W/O and DEF = no.
4. **Round-robin is a non-eliminating pool stage.** A loss in a round-robin group (e.g. the Tour
   Finals) does **not** pass the title; only knockout losses do. This is a toggle (`RR_PASSES_TITLE`,
   default off). The justification is twofold: a round-robin loss does not eliminate a player, and —
   decisively — no dataset records the actual day each round-robin match was played, so their order can
   never be recovered. Treating the round-robin as a pool stage dissolves an otherwise permanent
   ambiguity rather than guessing at it.
5. **No vacancy rule (dormancy).** A champion who never loses again keeps the title indefinitely.
   Pete Sampras won the 2002 US Open, which proved to be his last match; he retired without losing,
   so the title has been **dormant** with him ever since. His reign is counted up to his last actual
   match rather than rolling on through the rest of the dataset.

### Which competitions qualify

Only consistent tour-level events are included, by `tourney_level` code:

| Code | Event type | Included? |
| --- | --- | --- |
| `G` | Grand Slams | Yes |
| `M` | Masters / top-tier | Yes |
| `A` | Other tour events (United Cup, Laver Cup, etc.) | Yes |
| `250` / `500` | ATP 250 / 500 | Yes |
| `F` | Tour Finals | Yes |
| `D` | Davis Cup | No |
| `O` | Olympics | No |
| Challengers / qualifying | — | No |

Davis Cup and the Olympics are excluded both by level code **and by tournament name**, because one
source mislabels the 2000 Sydney Olympics as a regular event.

### Match ordering

The datasets record `tourney_date` as the tournament's **start** date, so every match in an event
shares one date. To keep the lineal order correct, matches are sorted by date, then tournament, then
a **round order** (`RR → R128 → R64 → R32 → R16 → QF → SF → BR → F`) before the baton is traced.
This guarantees a final is never processed before the rounds that feed it.

### Data sources

The chain is deliberately built from a stable base plus independent checks:

| Role | Source | Span | Why |
| --- | --- | --- | --- |
| **Backbone** | Jeff Sackmann `tennis_atp` (frozen local copy) | 1968–2024 | The de-facto standard for public tour-level results. |
| **Live tail** | [TennisMyLife](https://stats.tennismylife.org) | 2025–2026 | Keeps the chain current; same format as Sackmann. |
| **Independent cross-check** | datahub ATP-archive scrape | 1968–1990 | A genuinely separate ATP-site scrape, used to corroborate the fragile early era. |
| **Corroborating cross-check** | UTS / Ultimate Tennis Statistics | ≤ 2021 | A corrected, Sackmann-derived compilation; separates editorial omissions from errors. |

The backbone and tail are **spliced at the end of 2024**. Post-1985 the sources agree match-for-match,
so the splice is on settled ground.

### Triangulation and the verified-since year

For every title-changing match, the pipeline checks whether independent sources also carry it. Player
names are reconciled across sources by a canonicalisation step (lower-cased, accents folded, generational
suffixes and punctuation removed, with a hand alias for Pancho Gonzalez). Cross-source lookups use a
±1-year window to absorb calendar-versus-season filing (e.g. the 1975 Australian Open played in December
1974).

Each hop is tagged with which sources carry it (`S` = Sackmann backbone, plus `TML` / `DH` / `UTS`, and
`man` where hand-verified), and flagged if it is:

- **same-day** — genuinely ambiguous ordering (a tie the round order can't break across tournaments);
- **source-disagree** — not corroborated by the independent source and not hand-verified;
- **non-played** — a RET / W/O / DEF result.

A handful of pre-1985 hops that the independent source omits (WCT and minor events) have been
**hand-verified against primary records**; these are recorded with their citing source so they no longer
count as unconfirmed. Three early hops remain genuinely unverifiable and are left flagged.

The **verified-since year** is derived empirically: it is the earliest year from which the champion's path
to the present touches no contested (same-day or unconfirmed) match. For the current build that is **1983**.
With the round-robin treated as a pool stage, the only remaining cap is the independent ATP-archive source's
patchy coverage of minor events into the early 1980s — not a dispute, just a coverage gap.

### Current results

- **988** baton hops from 1968 to the present; current champion **Pete Sampras**.
- **34** flagged hops in total; **9** early-era hops hand-verified against primary records.
- **3** hops appear in Sackmann's data alone and could not be independently confirmed (1974 Tucson, 1975
  Houston). Every other isolated hop was checked and found to be a **real** match the official ATP archive
  simply omits, not an error.

---

## Limitations

In the interest of transparency, the known limitations of this methodology and its data:

1. **The early Open Era is genuinely incomplete in every source.** 1968–c.1975 had overlapping circuits
   (WCT, the Grand Prix, the NTL pro tour) with patchy record-keeping. No public dataset is a complete match
   record for that period, so the earliest part of the lineage is inherently approximate and source-dependent.
   This is precisely why the chain is only **verified-sound from 1983**; treat everything before then as
   best-effort.

2. **No dataset records actual match dates.** Every source — Sackmann, TennisMyLife, datahub and UTS — stores
   only the tournament's start date, so all matches in an event share one date. Round order fixes the sequence
   *within* a knockout draw, but the true order of matches in the **same round** (a round-robin) or in
   **different tournaments the same week** is unrecoverable from any data, and even primary sources rarely
   publish it. The round-robin case is handled by the pool-stage rule; the rare same-week cross-tournament case
   is flagged, not resolved.

3. **The seed is itself ambiguous.** Owen Davidson is assigned as the first champion by the project's premise,
   but the true order of the opening-round matches at Bournemouth is unknowable from the data. The seed is
   flagged accordingly.

4. **Walkover/retirement handling is a judgement call.** Counting a retirement as a loss but not a walkover is a
   defensible convention, not an objective truth. A different choice would change a handful of hops; the rule is
   made explicit so its effect can be reasoned about.

5. **Cross-checks are not fully independent.** Of the three checks, only the datahub ATP-archive scrape is
   genuinely independent of Sackmann; TennisMyLife and UTS are both Sackmann-derived. So a hop confirmed only by
   TML or UTS has corroboration but not true independence.

6. **Name reconciliation is imperfect.** Canonicalisation handles accents, suffixes, hyphenation and one alias,
   but cannot bridge differing name *orders* (e.g. some transliterated names) or middle-name differences. A few
   early-era hops are flagged purely because of naming, not a real data conflict.

7. **The site uses two pipelines.** The display tables (reigns, summaries, timeline, main lineage) are produced
   by the original `tennis.R` (Sackmann-only, 1968–2024), while the integrity panel is produced by the audited
   four-source `build_lineage.R`. Both seed Owen Davidson and end with Sampras and are consistent in practice,
   but they are not the same code path. Unifying them is a known future cleanup.

8. **Scope is a definitional choice, not completeness.** Excluding Davis Cup, the Olympics, Challengers and the
   pre-1990 alternative circuits is a decision about what "counts," not a claim that those matches did not happen.
   A different scope yields a different (equally valid) lineage.

9. **Data licensing is non-commercial.** All upstream sources are intended for non-commercial use. This project
   is recreational and must be treated the same way.

---

## Reproducing the build

Requires **R** (with `dplyr`, `readr`, `stringr`, `stringi`) and, for the cross-check datasets, network access
and (for UTS) Docker.

1. **Backbone** — a local copy of Jeff Sackmann's [`tennis_atp`](https://github.com/JeffSackmann/tennis_atp)
   yearly `atp_matches_YYYY.csv` files in `tennis_atp-master/`.
2. **Live tail + full TML** — TennisMyLife's "download all" archive, extracted into `tml_data/` as `YYYY.csv`.
3. **datahub** — `match_scores_1968-1990_UNINDEXED.csv` from the datahub ATP dataset, saved as
   `datahub_match_scores_1968-1990.csv`.
4. **UTS** — exported from the `mcekovic/uts-database` Docker image:
   ```sh
   docker run -d --name uts -p 55432:5432 mcekovic/uts-database:latest
   # then COPY the joined match table to uts_matches.csv (see build_lineage.R header)
   ```
5. **Run:**
   ```sh
   Rscript build_lineage.R   # writes uwc_lineage.csv, uwc_baton_flags.csv, uwc_provenance.csv
   Rscript tennis.R          # writes the reign/summary CSVs for the site's display tables
   ```

Methodology toggles (start date, walkover/retirement rules, Davis Cup / Olympics inclusion, the splice year)
are set at the top of `build_lineage.R`.

### Refreshing with new results

`refresh.ps1` automates pulling the latest data and rebuilding. It takes a `-SourceUrl` so a working data
mirror can be supplied if an upstream location moves.

---

## Attribution

- Match data © their respective sources: Jeff Sackmann (`tennis_atp`), TennisMyLife, the datahub ATP archive,
  and Ultimate Tennis Statistics. All for **non-commercial** use.
- "Ultimate World Champion" is a fictional, unofficial title invented for this project.
