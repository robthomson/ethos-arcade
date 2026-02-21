# Ethos Arcade

Ethos Arcade bundles a set of classic Lua games for FrSky Ethos into a single front menu, so you can launch any game from one place.

## Screenshots

| Menu | LuaPong | TxTris |
| --- | --- | --- |
| ![Menu](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/menu.png) | ![LuaPong](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/luapong.png) | ![TxTris](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/txtris.png) |

| LuaSnake | LuaFrog | LuaDefender |
| --- | --- | --- |
| ![LuaSnake](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/luasnake.png) | ![LuaFrog](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/frogger.png) | ![LuaDefender](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/defender.png) |

| LuaBlocks | Gates | MissileCmd |
| --- | --- | --- |
| ![LuaBlocks](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/luablocks.png) | ![Gates](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/gates.png) | ![MissileCmd](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/misilecommand.png) |

| GaLuaxian |
| --- |
| ![GaLuaxian](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/galuaxian.png) |

Merged FrSky Ethos game suite with a single front menu:

- LuaPong
- TxTris
- LuaSnake
- LuaFrog
- LuaDefender
- LuaBreaks
- Gates
- MissileCmd
- Dojo
- GaLuaxian

## Layout

- `src/ethos-arcade/main.lua` - unified system tool + game menu router
- `src/ethos-arcade/games/luapong` - LuaPong module/assets
- `src/ethos-arcade/games/txtris` - TxTris module/assets
- `src/ethos-arcade/games/luasnake` - LuaSnake module/assets
- `src/ethos-arcade/games/luafrog` - LuaFrog module/assets
- `src/ethos-arcade/games/luadefender` - LuaDefender module/assets
- `src/ethos-arcade/games/luabreaks` - LuaBreaks module/assets
- `src/ethos-arcade/games/gates` - Gates module/assets
- `src/ethos-arcade/games/missilecmd` - MissileCmd module/assets
- `src/ethos-arcade/games/retrofight` - Dojo module/assets
- `src/ethos-arcade/games/gulaxian` - GaLuaxian module/assets
- `.vscode` - deploy scripts/tasks/launch configuration
- `deploy.json` - deploy target config (`tgt_name = ethos-arcade`)

## Runtime Path

Deploy copies:

- `src/ethos-arcade/*` -> `/scripts/ethos-arcade/*`

Entry point:

- `/scripts/ethos-arcade/main.lua`

## VS Code Deploy

Use the same workflow as the original game repos:

- `Deploy & Launch [SIM]`
- `Deploy Radio`
- `Deploy Radio [Fast]`
- `Deploy Radio + Serial Debug`

Language config key:

- `ethosarcade.deploy.language`

## Menu Controls

In the arcade front menu:

- `Up/Down` (or rotary): select game
- `Enter`: launch game
- `Exit`: close tool

While in a game:

- game-native controls are passed through unchanged
- if a game does not handle `Exit`, control returns to the arcade menu

-----
Like what you see.  Consider donating..

[![Donate](https://raw.githubusercontent.com/robthomson/ethos-arcade/main/.github/gfx/paypal-donate-button.png)](https://www.paypal.com/donate/?hosted_button_id=SJVE2326X5R7A)
