---
title: "_fzf-open_: a fuzzy file search with a sensible opener"
date: 2020-09-26T20:59:00-07:00
draft: false
cover: "img/fzf_open_demo.gif"
---

**_Just like macOS Spotlight, but different!_**


One of my most sorely missed features from macOS was the Spotlight search. It can be incredibly
helpful to open the search, type a few characters, and be viewing/editing the file I want within
just moments.

This, unfortunately, does not exist in Linux outside of similar features integrated in desktop
environments such as Gnome. What to do if your favorite DE does not have such a feature or you only
have a window manager?

`fzf` alone comes close to filling this niche. But there are still some features I am looking for
that are out of `fzf`'s scope. For example, lets say I want to open some file in `vim`, but it's
deep in my file system and I don't feel like typing right now. I can open a terminal, type `vim
$(fzf)`, and proceed to edit my file. This actually works pretty well, but it still could be
faster. It starts to get a little sloppy with non-terminal programs. If I were to do the same thing
but open a video in `mpv` instead, I would now have both the terminal I just created, and the video
player. Chances are, I really don't care about that terminal. But, if I close it, there goes the
program I just opened. This problem is especially bad with tiling window managers.

`fzf-open` attempts to solve this problem by creating its own terminal and not attaching
applications to it when they're opened. It also includes a custom opener that can be used instead
of, say, `xdg-open` that can open files in terminal applications (`vim`). It's also pretty
configurable, so it should work with any terminal.

I use it in my window manager by binding it to _super+o_ and floating the window. The resulting
effect is shown at the top of the article.

# Some information from the repository #

## Features ##
- Customizable: supports configuration of terminals and openers
- Designed to be launched easily from a hotkey
- Comes with a simple opener: `xdg-open` **not** required
- Fast: uses the fantastic [fzf](https://github.com/junegunn/fzf)

## Installation ##

### Arch based ###

For Arch based distros, `fzf-open` is [on the AUR](https://aur.archlinux.org/packages/fzf-open/).

```
yay -S fzf-open
```

### Other distros ###

**Requirements**:
- python
- fzf

For other distros, installation is still simple:

```
git clone https://github.com/trmckay/fzf-open.git
cd fzf-open
sudo ./install.sh
cd ..
rm -rf fzf-open
```
Don't forget to configure!

## Configuration ##

Install and run `fzf-open` at least once for it to create config files.
Configuration is located at `$HOME/.config/fzf-open/config`.
An example configuration file is also included in `/usr/share/fzf-open/example_config`.

**Configuration keys** (absolute paths only, no environment variables):

| KEY | DEFUALT VALUE |
| --- | --- |
| `OPENER` | `~/.config/lopen.sh` |
| `TERMINAL` | `xterm` |
| `STARTING_DIR` | `~/` |
| `WIN_TITLE` | `fzf-open-run` |
| `WIN_TITLE_FLAG` | `--title` |
| `SPAWN_TERM` | `False` |

Most of these can be overwitten by flags:

| FLAG | EFFECT |
| --- | --- |
| `-n` | Spawn a new terminal with `fzf-open` |
| `-o "opener"` | Use this as the opener |
| `-d "dir"` | Start in this directory |
| `-t` "term" | Use this terminal program |

If you choose to keep, `lopen.sh` as the opener. You should customize it at `$HOME/.config/fzf-open/lopen.sh`, especially if the following
default applications do not look sane:

| FILETYPE | APPLICATION |
| --- | --- |
| Images | `feh` |
| Videos | `mpv` |
| Text | `vim` |
| PDF | `zathura` |
| Web | `firefox` |
| Terminal | `urxvt` |

