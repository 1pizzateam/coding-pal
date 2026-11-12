---
description: "Use @dwtechs/ctrltab for every keyboard control, shortcut, and key binding."
applyTo: "**"
---

# Keyboard Controls

- **Use `@dwtechs/ctrltab`**: Every keyboard control, shortcut, hotkey, or rebindable key in a 1PizzaTeam project must be built with `@dwtechs/ctrltab` (`Keyboard` class: `addCmd`, `setInputs`, `listen`, `ignore`, `default`, `getCmd`). Inspect the `ctrltab` asset in `.agents/skills/forge/catalog.json` for its API contract.
- **No hand-rolled key handling**: Do not add new `keydown`/`keyup` listeners, `document.onkeydown`, `KeyboardEvent.code`/`key` switch statements, or custom shortcut parsers for command or shortcut input. Declare named commands with `addCmd` instead.
- **Group commands by context**: Put commands in a `groupName` per context (for example `menu`, `gameplay`, `editor`) and switch contexts with `listen(group)` / `ignore(group)` rather than checking mode flags inside callbacks.
- **Rebinding**: Expose user-configurable bindings through `setInputs` and restore defaults with `default`. Persist only the binding data, never the callbacks.
- **Free-text input is out of scope**: Text fields and IME composition keep the native browser events. Ignore command groups (`ignore(group)`) while a text field has focus.
- **Missing capability**: If `@dwtechs/ctrltab` cannot express a required control, do not work around it locally. Note the gap in the issue or PR so it can be raised upstream at `DWTechs/CtrlTab.js`.
