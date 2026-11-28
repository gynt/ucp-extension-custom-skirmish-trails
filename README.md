# Custom Skirmish Trails

Module authors are gynt, Monsterfish, Heroesflorian, and Krarilotus.
Adds Custom Skirmish Trails to Stronghold Crusader and Stronghold Crusader Extreme

This tool is recommended to manipulate the csv files https://edit-csv.net/

## Working features
1. Disable recruitability of archer units
2. Disable producibility of weapons
3. Start gold per player and mission (gold_player_1 for the human, gold_player_2 .. gold_player_8 for each AI); an empty cell keeps the game's start gold; scenario missions get the gold Play a Map gives their map (docs/trail-files.md)
4. For each mission, configure which AI starts on which spot on the map
5. Change the map
6. Specify which castle the AI builds
7. Specify the starting resources
8. Disable tradeability of certain goods
9. Mission-specific player names, the human player's lord (also for the starting troops) and skipping the human's starting troops (`player1_name` .. `player8_name`, `player1_lord`, `player1_skip_start_units`)
10. A trail settings file per trail: title, summary, starting year, button pictures, background, trail screen buttons, mission button positions and count, own names for the AI keys (resources/trail-settings.schema.json)
11. Mission data from a CSV or a trail settings JSON with mission files
12. Language files with only the texts per game language
13. Scenario missions: a mission can be a custom scenario map, started as Play a Map starts it, with its own events, goals and players; a win moves the trail on (`mission_type`: `scenario` or `skirmish_scenario`)
14. Troop limits per mission, for example Crusader's limits in an Extreme trail (`unit_limit`)
15. Door pictures per mission: locked, available and won, each optional (the game's marker where one is left out), with locked missions not clickable (`mission_icons`, `icon`)
16. Player colours per mission: an AI player's skirmish colour (`player2_color` .. `player8_color`)
17. A trail route: missions as named nodes that require each other, so a trail can branch into parallel paths, join again and have side missions; unlock conditions on a win's result and chicken rewards (`trail_route`)

See `docs/trail-files.md` for the details.

## Support
Do you like what you are seeing? Consider donating to support my work.

### Bad Review Hall Of Fame
Sometimes I get bad reviews of course. Some people don't like it.  Here is a short hall of fame.

#### "A half-baked and inconsequential plugin"
Reviewer: Krarilotus  
Module version: 1.2.1


## Author a trail

1. In the launcher's Custom Skirmish Trails options, choose a source file for First Edition, Warchest or Extreme. Select a CSV or a trail settings JSON that names its mission files.
2. Edit the CSV, or edit the settings JSON and the mission JSON files it names. Restart the game to load your edits.
3. To switch formats, run the converter with Python 3.10 or later, then choose its output in the launcher.

```sh
python tools/convert_trail.py my-trail.csv my-trail-settings.json --trail-type Extreme
python tools/convert_trail.py my-trail-settings.json my-trail-converted.csv
```

Choose `First`, `Warchest` or `Extreme` when converting a CSV. The converter uses the game's mission positions, or positions from an existing settings JSON supplied with `--settings`. Keep the converted settings next to the original when it refers to other files by relative path. CSV stores mission rows in play order. Keep the settings JSON for the route, positions, language files and other trail-wide settings.

Place trail files inside the game folder. The framework resolves UCP aliases and absolute paths inside that folder.
