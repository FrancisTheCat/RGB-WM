Warning: This is a small and young toy project, it might eat your windows
Warning: At the moment multi monitor setups are _not_ supported
# RGB WM
RGB WM is a dynamic tiling window manager for Windows 11 that does not sacrifice on its RGB

## Installation

### Prebuilt binaries
Prebuilt binaries are available in the releases

### Build from source
You need to have the Odin compiler installed on your system
1. Clone the repo
2. `$ ./build.bat`

## Configuration
Both configuration files have to be located next to RGB WM executable, wich will probably change at some point
If a configuration file is missing a default one will be generated

### Keybinds
Keybinds are configured within keybinds.txt
The format is "Modifiers + Key : Command"
The names of the keys mostly follow Microsofts Virtual Keycodes
Everything is case insensitive

### Config
Window Borders, the Bar, Workspaces etc are configured in config.json
NOTE: Some options may require a restart, this will be fixed at some point

# Alternatives
These are some fantastic window managers for windows that serve as inspirations, learning materials and alternatives to this one, go check them out they are all quite nice (none of them have RGB tho)
- GlazeWM
- Komorebi
- dwm-win32
