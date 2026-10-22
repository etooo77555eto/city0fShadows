# MISSION_CATALOG — City of Shadows

All missions are data in `StoryData.swift` and run on the mission engine in
`GameViewController.swift`. Step types: goTo, talkTo, driveTo, escapeWanted,
collectPoints, timedGoTo, followCar, surviveChase. Rewards are granted once
(completion is recorded in the save).

| # | ID | Title | Chapter | Steps | Reward |
|---|---|---|---|---|---|
| 1 | m01_return | Shadows on the Promenade | 1 | goTo promenade → talk Marcus → drive to garage | $300 |
| 2 | m02_old_debts | Old Debts | 1 | talk Lena → collect 3 caches → return | $450 |
| 3 | m03_night_run | Night Run | 2 | timed drive to dealership (95s) → escape wanted | $600 |
| 4 | m04_paper_trail | Paper Trail | 2 | talk Cross → collect 2 evidence → return midtown | $700 |
| 5 | m05_convoy | The Convoy | 3 | follow route to port road → timed drive to safehouse (130s) | $900 |
| 6 | m06_heat | Heat | 3 | survive chase 45s → escape | $1000 |
| 7 | m07_the_offer | The Offer | 4 | talk Victor → drive downtown | $1100 |
| 8 | m08_broken_trust | Broken Trust | 4 | talk Marcus → collect 3 pages → escape | $1300 |
| 9 | m09_last_ledger | The Last Ledger | 5 | talk Lena → drive warehouse → timed delivery to coast (110s) | $1600 |
| 10 | m10_city_of_shadows | City of Shadows | 5 | survive 60s → escape → return → final talk (ending) | $2500 |

Failure: timed steps reset and can be retried; arrest during survive/escape
steps restarts the current step. Dialogue choices in m02/m04/m07/m08 write
decisions + relationship changes to the save and select the m10 ending.

## Side content
- **Coastal Run** race: 6 checkpoints along the coast road, $500.
- **Downtown Loop** race: 7 checkpoints around the centre, $800.
- **Deliveries**: from the Fuel & Mart job board to a random landmark,
  130 seconds, $250. Best race times are saved.
