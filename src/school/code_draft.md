# Just Another Simple Platforming Game

> Ignore all files outside of the `src/` and `assets/` directory, everything else is just to set up my environment

If you don't have a way to render markdown on your machine then take a look at [this page](https://t1mbits.github.io/blog/school/code_draft.html) as this README is fully rendered there.

# Usage

Check [Dependencies](#Dependencies) for required project dependencies.

Make sure your current working directory/command prompt is set to the root of the project directory. When listing the contents of your current directory, it should contain the following files and directories:

-   assets/
-   src/
-   flake.lock
-   flake.nix
-   README.md
-   TODO.md

Then, run the following command:

```bash
python src/main.py
```

# Dependencies

This project was written in Python 3.12.7, I don't think there will be any issues with using a newer version of python but I can't be sure.

The `pygame` and `orjson` packages are required for this program. Run one of the following commands to install the required dependencies. If you have a different way of installing the required python packages, do that instead.

```bash
python -m pip install pygame==2.6.0 orjson==3.10.7
# or
pip install pygame==2.6.0 orjson==3.10.7
```

This project also uses the `abc`, `enum`, `os`, `sys`, and `typing` modules from the default python package.

# Project Layout

```
jaspg
├── assets      # game resources
│   ├── levels      # Map data
│   │   └── ...
│   ├── readme      # Assets used for this document
│   │   └── ...
│   └── sprites     # Sprite assets
│       └── ...
├── src         # game source code
│   ├── core        # Modules used in both the editor and main game, as well as modules used by other modules in this directory
│   │   ├── assets.py   # asset handlers
│   │   ├── base.py     # base classes that must be loaded before other modules
│   │   ├── hitbox.py   # hitbox related code
│   │   ├── level.py    # level state manager
│   │   └── tile.py     # tile related code
│   ├── game        # Modules only used when running the game
│   │   ├── entity.py   # Entity related code. Anything that can move will likely derive from classes in this module
│   │   └── player.py   # The player class
│   ├── editor.py   # Code for the rudimentary editor
│   └── main.py     # Main game loop and program entry point
├── flake.lock  # Lockfile for Nix flake inputs
├── flake.nix   # Nix flake configuration
├── README.md   # This document
└── TODO.md     # TODO list

```
