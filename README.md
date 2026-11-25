# CustomSkins

Adds custom skins to GTA SA / SA-MP **without replacing any vanilla skin**.
A small C++ DLL registers new ped model IDs (312-319) and loads your DFF/TXD
into them; a MoonLoader script provides the commands.

Target: GTA SA 1.0 US, SA-MP 0.3.7, MoonLoader. Client-side only
(other players still see the skin the server gave you).

## Build
Push to GitHub. Actions builds an **x86** DLL; download the `CustomSkins`
artifact from the run. Or locally:

    cmake -S . -B build -A Win32
    cmake --build build --config Release

## Install
Copy from the artifact into your GTA folder:

    moonloader/customskins.lua
    moonloader/lib/customskins_core.dll
    custom_models/            (put NAME.dff + NAME.txd pairs here)

## Commands
    /models          list skins
    /model <name>    wear (prefix/substring match ok)
    /model off       restore original skin
    /reloadmodels    rescan custom_models
    /autoskin        toggle auto-load on join

## Notes
- Raise `MAX_SLOTS` in `src/customskins_core.cpp` for more skins; IDs must be unused.
- DLL error codes: -2 no slots, -3/-4 txd, -5 AddPedModel, -6/-7 dff, -8 exception caught.
- Untested on other game versions; addresses are 1.0 US only.
