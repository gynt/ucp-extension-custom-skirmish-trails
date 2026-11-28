# Trail files

Trail settings files, mission files and language files were added in 1.4 by Monsterfish. The
JSON schemas are in `resources/`.

## Player names and the human player's lord
Optional csv columns, best placed at the end:
- `player1_name` to `player8_name`: the name a player has in this mission, in the briefing and in the game. Empty keeps the usual human or AI name.
- `player1_lord`: `Arab` or `Europ` gives the human player the Arabian or the European lord for this mission, and the starting troops of that lord. Empty keeps the player's own choice.
- `player1_skip_start_units`: `1` gives the human player no starting troops in this mission (the lord still comes). Empty or `0` keeps them.

## Start gold
`gold_player_1` (the human player) to `gold_player_8` (`gold` of a player in a mission file) set a player's start gold in this mission; `0` is no gold. Empty keeps the game's start gold for the mission's advantage and start mode. The briefing shows the human player's gold and, when an AI player has its own gold, one value per AI player in player order, for example `4000 / 3000 / 4000`, or the lowest and highest (`3000 - 4000`) where those don't fit beside the label. As in every game, each player's keep pays the start gold out bit by bit at the start; the gold still to come shows as `Starting goods`.
For scenario missions see [Start gold in scenario missions](#start-gold-in-scenario-missions).
Below the gold, the briefing shows the skirmish menu's button picture of the mission's start mode (normal, crusader or deathmatch).

## Start gold in scenario missions
A `scenario` or `skirmish_scenario` mission starts with the gold the game gives its map in Custom Scenarios → Play a Map. It is never tripled, not even on an Extreme-type trail. Each lord gets:
1. the treasury saved in the map, or the starting gold the map's scenario options set instead;
2. paid into the treasury over the first seconds: for a map saved from a skirmish, the game's skirmish start gold for the start mode and advantage saved in the map (not the mission's `start_mode` and `advantage`); for a map made as a scenario in the editor, the gold among the map's own starting goods.

Goods come from the map only: its stock and its starting goods. The mission's `gold_player_N` and `resource_` columns don't apply, and the trail's briefing leaves the gold amounts blank for these missions (the labels and coins still show).

To give the lords of a map saved from a skirmish exactly their saved gold (amount 1), set amount 2 to 0 in startResources: `startGold.<start mode>.<advantage>.human` for the human lord and `.computer` for every AI lord, for the map's start mode and advantage. Human and AI each read their own entry, which differ with an advantage. This changes every game that uses that table entry: every skirmish, and every Play a Map launch of a map saved from a skirmish, with that start mode and advantage. Starting gold set by the map's scenario options still applies.

For comparison, in a plain `skirmish` mission each lord's start gold is the same skirmish table value, tripled on an Extreme-type trail, and `gold_player_N` replaces it without tripling.

Example: a map saved from a skirmish on Normal with no advantage, with treasuries of 560 for the human and 241 for an AI lord. The game's table gives every lord 2000 there, so the human ends up with 2560 and the AI lord with 2241. With startResources' `startGold.normal.noAdvantage.human` and `.computer` at 0, they keep 560 and 241.

## Player colours
A player's skirmish colour is its player slot: red (the human player's), orange, yellow, blue, black, purple, lightblue and green. The optional columns `player2_color` to `player8_color` (`color` of an AI player in a mission file) put that AI player into the slot of a colour name or slot number (2-8). The other AI players keep their slot, or take the first free one when it is taken. Empty keeps the player's own slot. A colour that is red, unknown or already given to another player is reported in the log and not used.

## Scenario missions
Trail missions with a custom map name can only start when the game can open that map. The optional csv column `mission_type` (`"mission_type"` in a mission file) says how a mission starts:
- `skirmish` (or empty): as before, the trail sets up a skirmish on the map with the mission's players, teams, gold and goods.
- `scenario`: the mission's map is a custom scenario made as one, for example an Invasion map made in the map editor. It starts the way Custom Scenarios → Play a Map starts it, so its events, goals, invasions, placed units and AI lords run as the map has them. For an Invasion map the game then shows its own briefing, as it does for Play a Map.
- `skirmish_scenario`: the mission's map is a skirmish game saved and turned into a map, then edited as a scenario. It starts as a `scenario` does and then plays as a skirmish mission of the trail (see below).

A `scenario` or `skirmish_scenario` mission only needs `map_name`, `mission_name` and the 8 description lines of the trail's briefing; the other columns are not used. The game stores in the map whether it was saved from a skirmish; when that doesn't match the `mission_type`, the log says so, and the trail keeps the mission as it keeps a `scenario`. Other values of `mission_type` are reported in the log, and such a mission doesn't start.
  - **The map** is looked up like any other map: in the game's `maps` folder, the Documents `Maps` folder, or an extra map folder a plugin registered with the files module. `map_name` is a file name without folders, with or without `.map`, of at most 200 bytes. Letters such as `ü` are fine (they are written in their Latin-1 form, as the files module reads them); letters outside Latin-1 are not. Choose a map that Play a Map can start.
  - **The briefing's lords:** the trail's briefing shows the AI lords and teams the map sets, as the skirmish briefing does. They fill `player2` .. `player8` and `team1` .. `team8` where the mission leaves them empty or the slot lies past `num_players` (the mission's own values win), and `num_players` grows to the map's last AI lord. The map is read when the trail's missions are loaded, only once its date has come, and only when the map stores its lords uncompressed. These columns don't change the scenario itself.
  - **Briefing text:** the optional column `scenario_briefing` (`"scenario_briefing"` in a mission file) is the game's briefing text for this mission, shown instead of the map's own description in the game's briefing. A language file can give it in each game language, so one map serves every language. It is written in the game's text encoding and cut to 999 bytes. The objectives come from the map as before and follow the game language. Empty keeps the map's text.
  - **Difficulty and troops:** the engine difficulty stays Normal, as for Play a Map, and so does what Play a Map does at Normal: on a map without invasion events it removes part of the player's starting army (every 4th military unit, until about a quarter of their value is gone). The optional column `difficulty_scaling` (`"difficulty_scaling"` in a mission file) sets this: `vanilla` (or empty) keeps the game's cut, `none` keeps the whole placed army when the trail starts this mission and on its Restart. Other values are reported in the log and work as `vanilla`.
  - **The end** works as for a skirmish mission: a win or a loss shows the game's skirmish end screen with its statistics, and leaving it opens the trail map; after a win the trail moves on. A win counts for the scenario the trail started, while the trail remembers it (see below). Winning a map that is a mission of two trails counts for the trail that was open last. Only maps that end on the mission finished screen can be won this way (Invasion and siege maps); economic and build-only maps end with the game's quit dialog instead. The game also records the trail's months and its Skirmish Masters entry as for a skirmish mission; set the trail's `starting_year` no later than the scenarios' own years. For a map saved from a skirmish game the recorded months can be wrong: the game counts them from the start month stored in the map.
  - Restart and Quit in the game work as for a map started from Play a Map; Quit leads to Custom Scenarios. A `skirmish_scenario` keeps the skirmish rules (for example, it is won when every enemy lord is dead) and plays as a skirmish mission of the trail: Restart starts it again from the trail, Quit leads to the trail map, and its saves keep the mission, its `unit_limit` and its win, as a skirmish mission's saves do.
  - For a `scenario`, the trail remembers the scenario it started until the next trail Start, until the Play a Map list is opened, until a save of another map is loaded or until the game is closed. While it does, Restart and loaded saves of that map count as this mission (also a save of another game on that map); a save that names no map ends it. A save loaded after the game was started again plays without the mission's `difficulty_scaling` on Restart and without its `unit_limit`, and winning it doesn't count for the trail.
  - **Dates:** a map with a date in an `availability.json` of the files module (files 1.5.0) can be started only from its date on. Until then the briefing shows the trail settings file's `mission_locked_text` (a language file can give its own), in which `{date}` becomes the date. Without that text the mission's own description is shown, and Start does nothing. With an older files module no map has a date.

A plugin can give a mission of a trail's mission data (csv or mission files) another map, for example the map in the language a player chose, from its `init.lua`: `modules["custom-skirmish-trails"]:setMissionMap("Warchest", 5, "Türchen05")` (trail `First`, `Warchest` or `Extreme`, the mission number or, for a route of mission files, the node id, the map name). Call it while extensions are enabled; it applies when the trail's missions are loaded, and a mission the data doesn't have is reported in the log.

## Troop limits (`unit_limit`)
The game limits each player's troops: in Crusader to 2400 / living lords - 40, in Extreme to 9900 / living lords - 40, and not at all in custom scenarios. The optional column `unit_limit` sets the limit for this mission:
- `native`: the game's own limit (also when the column is empty);
- `formula BASE OFFSET`: BASE / living lords - OFFSET. `formula 2400 40` gives Crusader's limits in Extreme; in a scenario mission it gives a limit where the game has none. BASE 1–100000, OFFSET 0–100000.
- `by_alive LORDS=LIMIT ...`: a limit per number of living lords, for example `by_alive 8=250 4=500 2=1000 1=2000`; counts between two listed ones are interpolated and rounded down (6 living lords: 375), counts outside them take the nearest listed limit. Each count 1–8 at most once, each limit at most 100000.

In a mission file `unit_limit` is an object, and left out for `native`:

```json
"unit_limit": { "formula": { "base": 2500, "offset": 40 } }
"unit_limit": { "by_alive": [ { "lords": 8, "limit": 250 }, { "lords": 1, "limit": 2000 } ] }
```

The limit is never higher than the game's skirmish formula for the living lords (also in scenario missions, where the game has none), for example at most 2360 with one living lord in Crusader. In a scenario mission the living lords are the lords of the map's players that are still alive. Placed and AI units share the game's unit pool, so a limit doesn't guarantee room for the player's troops. The limit is worked out each tick from the mission being played (a skirmish mission: the game's trail state; a scenario mission: the scenario the trail started, see above); outside trail missions the game's own limit is used. A mission with a limit doesn't start when the game code for it is not found. The AI's troops are not limited by it.

## Files the game writes
The game writes only into the module's user data folder, `ucp/userdata/custom-skirmish-trails/` in the game's user folder (UCP framework 3.0.8 or later), never into a trail's folder. Each file is written to a temporary file first, which then replaces it, so a failed write keeps the previous file. A character other than letters, digits, `.`, `_`, `~` and `-` in a file name is written as `-`.

## Trail settings file
Choose a trail settings JSON as the trail source to use mission JSONs. The settings file needs `trail_missions.base_name`. See `resources/trail-settings.schema.json` for the other fields. The templates in `resources/trails/` show the game's standard positions.
- `trail_type`: `First`, `Warchest` or `Extreme`.
- `trail_id`: names the files that keep the trail's progress (`progress-<trail_id>.txt` in the user data folder), passed missions and results (see Trail route), so its progress stays apart from the game's own and from every other `trail_id`. 1 to 64 lowercase letters, digits, `-` or `_`. Without it the progress is the game's own, and the other files take the trail's `trail_type` in lowercase in place of `<trail_id>`: `first`, `warchest` or `extreme` (`sides-extreme.txt` for the Extreme trail). These three can't be a `trail_id`.
- `trail_missions`: the trail's mission data, see below.
- `trail_text_files`: the trail's language files, see below.
- `trail_title`, `trail_summary`: the texts under the trail's button in the skirmish menu. A summary wider than 540 pixels wraps into a second line; both texts then sit 10 pixels higher.
- `mission_locked_text`: the briefing of a scenario mission whose map isn't open yet (see Scenario missions); `{date}` becomes the date.
- `starting_year`: the year the first mission starts in.
- `trail_visuals`: `trail_button_idle` and `trail_button_highlighted` (pictures, for example .png, for the trail's button in the skirmish menu), and `trail_background` (the trail screen's background: a .tgx file, or a .png/.jpg/.bmp; use the size of the game's own file). The game opens the background as a .tgx file, so the module converts it at startup and writes the result into the user data folder. Use `mission_icons` for door pictures (see below). The trail screen's buttons take pictures in pairs, `_idle` at rest and `_highlighted` under the mouse: `chicken_` (skips a mission, 185 x 185), `skirmish_masters_` (96 x 88), `back_` (back to the trail menu) and `next_` (the selected mission's briefing), the two hands at 180 x 180. They show only on this trail's screen; a button without a picture keeps the game's.
- `trail_mission_positions`: a list of `{ "x": .., "y": .. }` points on the 800 x 600 trail screen, one per mission. Their number is the trail's number of missions (at most 50 for the first trail, 30 for the Warchest and the Extreme trail). A route of mission files (see Trail route) gives the positions and the number of missions instead.
- `trail_route`: the trail's missions as a graph of nodes, see Trail route.
- `ai_character_mapping`: your own names for the AI keys (`"SK_RICHARD": "Robert"`). Mission files use them, and the csv file may use them in player1 to player8.

Relative paths in the file are taken from the file's own folder.

## Mission data: csv file and mission files
The csv templates in `resources/trails/` have every csv column, one line per mission of the game's trails. `text_description_line_01` to `_08` are the briefing's lines; a `trade_` column with a good's name (for example `trade_spear`) turns trading that good off or on.

**Write mission files; no csv is needed.** With `"trail_missions": { "base_name": "missions/my_trail", "data_mode": "json_folder" }`, a trail needs only its trail settings file and the mission files `missions/my_trail/my_trail_mission_01.json`, `..._02.json`, ... (numbered without gaps; a route's `mission` is that number). A route of mission files names each file itself instead (see Trail route). The game loads the mission files at every start.

A mission file (format 1, `resources/mission.schema.json`) holds the same data as one csv line, laid out for reading and editing:
- `mission_name` and `text_description` (a list of the 8 lines) at the top;
- `advantage` (`human_large`, `human_small`, `neutral`, `ai_small`, `ai_large`; the csv's fairness 1-5) and `start_mode` (`normal`, `crusader`, `deathmatch`; the csv's start_levels 1-3). Numbers work too;
- `players`: one entry per player, so their number is the mission's number of players. `players[0]` is the human player: it may have `lord` and `skip_start_units`, never `ai`. The others always have `ai`, never `lord`. All have `name`, `start_position`, `team`, `aiv_type` and `gold` as needed, and AI players `color`;
- `producible`, `recruitable`, `resources`, `tradeable`: the csv's prefixed columns as objects;
- `icon`: `locked`, `available` and `won`, the csv's `icon_locked`, `icon_available` and `icon_won` (door pictures, each optional, see below);
- `unit_limit`: an object, see Troop limits;
- `extra`: any csv value that has no place above, so that nothing gets lost. A conflicting value in `extra` takes precedence and logs a warning before it can be written to CSV.

A JSON source uses `json_folder` mission data, including when `data_mode` is omitted. For a route of files, each node names its mission file and position. Use `tools/convert_trail.py` to switch formats. See [Author a trail](../README.md#author-a-trail).

For one release, an empty source field lets old profiles load their settings and CSV paths as before. The legacy `csv` and `automatic` modes apply only to those profiles.

## Language files
The mission data holds one set of texts, the default language. Each further language is one small JSON file with only its texts: `"trail_text_files": "texts/"` points to a folder with one file per game language as UCP names it: `english.json`, `german.json`, `russian.json` and so on (or give an object of languages to files). A language file:

```json
{
  "trail_title": "Der Kreuzzug",
  "trail_summary": "...",
  "mission_locked_text": "...",
  "missions": {
    "1": { "mission_name": "Die Küste", "text_description_line_01": "...", "player2_name": "..." }
  }
}
```

Validate language files with [the language-file schema](../resources/trail-language.schema.json). Missions are found by their number, or by their node id when the trail's route names its missions by file (`"door05": { ... }`). A text a language file does not have shows the mission data's text; strict mode lists those.

## Strict mode
Set `custom-skirmish-trails.csv.strict_format` in your profile or preset to see detailed startup diagnostics for CSV, mission, language and trail settings files. Leave it off for summary warnings.

### Skip tokens

Set `chickens` in the trail settings JSON to change its total skip budget. The
game subtracts spent tokens when it opens the trail screen. Without it the trail
has the game's 3. `"unlimited"` supplies enough tokens to skip every mission on
that trail.

```json
"chickens": 6
```

### Door pictures

`trail_visuals.mission_icons` names a .gm1 file of the GM1 type of the game's
`skirmish_trail_icons.gm1`, with as many pictures of 100 x 100 as the trail needs. A mission's
`icon` names its pictures (counted from 0), one per state, each centred on the
mission's position, where its click is taken. Every line of a picture spans its 100
pixels, transparent runs included, as in the game's sheet; a picture whose lines end
early is drawn shifted. Each picture is optional:

- `locked`: the mission can't be clicked yet. Leave it out to draw nothing while the
  mission is locked, so the trail background shows.
- `available`: the mission can be clicked. Leave it out to show the game's own marker
  of the next mission. A mission with an available picture is also locked until its
  date has come (see Scenario missions) and its map is installed.
- `won`: drawn over the available picture once the mission is won (not when a chicken
  skipped it). Leave it out to show the game's own flag of a won mission.

For a state without a picture the game draws its own marker, so a mission without
`icon` looks as it does without a sheet. A picture number outside the sheet is
reported in the log and leaves that state to the game's marker. The game's markers follow the trail's
order: every mission before the next one is drawn won (or skipped), the next one
available. In a trail with a route (below) that is right only for a *chain mission*:
a main mission without `unlock` that needs only main missions before it, and that
every main mission before it leads to through `requires`. Every other mission (side
missions, the missions of parallel paths) is drawn only by its own pictures and needs
at least an `available` picture to be played.

Pictures are drawn over the trail background: transparent parts of a picture show it.
The game's chicken stays on the selected mission.

```json
"trail_visuals": { "mission_icons": "doors.gm1" }
"icon": { "locked": 0, "available": 1, "won": 2 }
"icon": { "available": 7 }
```

### Trail route (`trail_route`)

`trail_route` in the trail settings file names the trail's missions as nodes, each under an id of
your own (letters, digits, `_` and `-`). Nodes require other nodes, so a trail can branch into
parallel paths and join again, and have side missions. Without `trail_route` the trail plays its
missions in their order as before.

```json
"trail_route": {
  "door01": { "file": "missions/door01.json", "position": { "x": 50, "y": 166 } },
  "door02": { "file": "missions/door02.json", "position": { "x": 81, "y": 170 }, "requires": ["door01"] },
  "forest": { "file": "missions/forest.json", "position": { "x": 120, "y": 220 }, "requires": ["door02"] },
  "river":  { "file": "missions/river.json",  "position": { "x": 140, "y": 120 }, "requires": ["door02"] },
  "castle": { "file": "missions/castle.json", "position": { "x": 200, "y": 170 },
              "requires": ["forest", "river"], "end": true },
  "pigs":   { "file": "missions/pigs.json",   "position": { "x": 90, "y": 260 }, "kind": "side",
              "unlock": { "won": { "mission": "door02", "lords_alive": ["yellow", "blue", "black"] } },
              "reward": { "chickens": 1 } }
}
```

A node has:

- `file`: its mission file (relative to the trail settings file), and `position`: `{ "x": .., "y": .. }`
  on the 800 x 600 trail screen. Or, in a route by number, `mission` instead (see below). A route
  uses either files or numbers for all its nodes.
- `kind`: `main` (also when it is not set) or `side`. Side missions are extra missions: they don't
  move the trail on, chickens don't skip them, and they can't be the end.
- `requires`: the nodes that must all be passed first; `requires_any`: the nodes of which one must
  be passed. A node is passed once it is won; a main node also when a chicken skipped it.
- `unlock`: a condition on the results of wins, see below.
- `reward`: `{ "chickens": n }`, see below.
- `end`: `true` for the node whose win finishes the trail. Without it, the end is the one main node
  that no other node requires (a route by number: its last mission). Nothing can require the end.
- Other fields of a node are not used.

A node can be played once its `requires` and `requires_any` are passed, its `unlock` holds and its
door is open (date and map), and played again after that. After a win or a chicken, the trail map
selects the first main mission in the trail's order that can be played.

**The order.** The game keeps a trail as rows in order and ends it when its last row is won. With
files, Trails gives every node its row: the main nodes in the order their `requires` allow (by id
where several could go), then the side nodes, and the end last. The game loads the node files in
that order. The route gives the positions;
`trail_mission_positions` is not used. A mission file holds the mission as in a numbered folder,
`icon` included.

**The game's furthest mission** is the first main mission in that order that isn't passed. Every
mission before it is passed or a side mission, so the game's own displays, the chicken count and
the progress file of `trail_id` keep working. A chicken skips that mission (also when its `requires` or
`unlock` don't hold yet); it can't skip the end.

**Door pictures** (`mission_icons`, see above) are needed for a route with side missions or
parallel paths, and every mission that isn't a chain mission needs its `available` picture. Without
the sheet, or when the game can't use it, such a route plays its missions in their order as the game
plays a trail, from the game's furthest mission on, one mission per win or chicken (reported in the
log); its wins and rewards still count. A route of only
chain missions and rewards needs no pictures.

**A route by number.** A node can name its mission by its number in the mission data (`"mission": 5`,
its csv line or numbered mission file) instead of a file; such a route keeps the trail's mission data,
positions and language keys. Missions it doesn't name are main missions. A main mission without
`requires` and `requires_any` follows the main mission before it, so a route that only adds side
missions reads as before. The end is the trail's last mission, which must be a main mission.

```json
"trail_route": {
  "door05": { "mission": 5 },
  "ambush": { "mission": 6, "kind": "side", "requires": ["door05"] },
  "door06": { "mission": 7 }
}
```

A route with a problem (a mission outside the trail, two nodes on one mission, an id in `requires`
that is not a node, a circle of `requires`, a side mission or a node that something requires as the
end, files and numbers mixed, a node of files without file or position, more nodes than the trail
can have) is reported in the log. A route by number then plays its missions in their order; a route
of files loads no missions.

Passed nodes are kept in `sides-<trail_id>.txt` in the user data folder (see `trail_id` for the
name without one), one node id per line. While that file names no main node, every main mission before the game's furthest mission
counts as passed, so progress from before the trail had its route is kept.

#### Unlocks and rewards

```json
"pigs": { "file": "missions/pigs.json", "position": { "x": 90, "y": 260 }, "kind": "side",
          "unlock": { "won": { "mission": "door05", "lords_alive": ["yellow", "blue", "black"] } },
          "reward": { "chickens": 1 } },
"keep": { "file": "missions/keep.json", "position": { "x": 300, "y": 400 }, "kind": "side",
          "unlock": { "any": [
            { "won": { "mission": "door15", "lords_alive": ["orange"] } },
            { "won": { "mission": "door16", "players_alive": ["red", "orange"] } } ] } }
```

- `unlock` (any node): one condition (`resources/condition.schema.json`). A condition is an object with one key, its type:
  - `won`: `mission` (needed) is a node, and the condition holds once one win of it met every
    other key: `lords_alive`, these players' lords were alive at the win; `players_alive`, these
    players were still in the game (lord alive and keep standing).
  - `all`: a list of conditions that must all hold; `any`: a list of conditions of which one must
    hold. They can be nested.

  Players are a list of colours: `red` is you, and `orange`, `yellow`, `blue`, `black`, `purple`,
  `lightblue` and `green` are the AI slots 2-8 (see Player colours; in a scenario mission the
  map's slots). Each win counts on its own: two wins with a different lord alive each don't make
  "both alive". A later win doesn't take an unlock back.

  A condition type or key this version doesn't know, or a value it can't read, is reported in the
  log and makes that condition false, so an older version never opens a door it can't judge.
- `reward`: `chickens` (1-1000) more chickens on this trail, given at the node's first win and
  shown when the trail map opens. They count on top of the trail's `chickens` (or the game's 3);
  with `"unlimited"` nothing changes.
- Every win of a route node, a replay too, is kept in `results-<trail_id>.txt` in the user data folder (named as
  the passed nodes' file), one line per different win:
  `door05 lords=1,3,4,5 players=1,3,4,5`, the node and the players whose lord, and who
  themselves, were alive at the win. Other words after the node, such as a difficulty, are
  skipped. A skip with a chicken is not a win. Delete the
  file to start the trail's unlocks and rewards over.
