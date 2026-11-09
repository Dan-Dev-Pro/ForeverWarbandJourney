# Forever Warband Journey

A WoW Forever addon that keeps a warband of characters on pace: level goals with deadlines, live levelling pace, profession routes with an Auction House shopping list, and a small pace tracker on screen.

## Install

1. Download the latest release zip (or this repo as a zip).
2. Put the `ForeverWarbandJourney` folder in `World of Warcraft\_forever_\Interface\AddOns\`.
3. Log in and type `/fwj`.

## What it does

| Area | What you get |
|---|---|
| Pace tracker | Draggable HUD: level time vs estimate, tonight's target, week hours, goal date |
| Goals | Ordered level goals across characters, with forecasts from your own pace and playing hours |
| Levelling | Per-level estimates (XP-weighted), pace learned from /played and your last levels |
| Professions | Live recipe colours, skill-up route to a level-based target, lockable routes |
| Shopping | Auction House price scan; cheapest route including ore vs bars; owned mats used first |
| Gathering | Gather / Optional / Ignore verdict on node tooltips |
| Warband | Roles, professions, gold, rested, 7-day play chart |
| Journey | Optional: shows your current Journey guide step on the HUD (reads progress only) |

## Commands

`/fwj` open · `/fwj goals` · `/fwj hud` · `/fwj lock` · `/fwj hours 2 4` · `/fwj target 2026-12-02` · `/fwj profs` · `/fwj debug`

## Data

Recipe skill levels and reagents come from the 1.12 game tables; FWJ reads your profession window so WoW Forever's own values always win. Skill-up routes are FWJ's own.
