# ZX Dino

A dinosaur runner in the style of the Chrome offline game, for the ZX Spectrum 48K. The game is Z80 assembly. Sprites are ASCII pictures in `art.py`.

## Play

Open `dino.tap` or `dino.z80` in a 48K emulator.

The TAP file starts with a BASIC loader. It loads the code at address 32768 (`$8000`) and runs it. The Z80 snapshot starts at the same address.

## Controls

SPACE or Q jumps. After a collision, release the key, then press it again to start the next run.

The score counts up while you run. The high score lasts until you reset the machine. The screen flips between day and night as the score climbs.

## Build

You need Python 3 and [z88dk](https://github.com/z88dk/z88dk) `z80asm`.

```sh
python3 build.py
```

The script rebuilds `sprites.inc` from `art.py`, assembles `dino.asm`, and writes `dino.bin`, `dino.tap`, and `dino.z80`.

To change a sprite, edit its picture in `art.py`. Every row of a sprite must be the same width, and the width must be a multiple of 8.

The same command can render preview frames. That step needs a Spectrum 48K ROM and [libz80](https://github.com/ggambetta/libz80). Both paths are set at the top of `build.py`. If the ROM is not there, the TAP and Z80 images are still written.

## License

MIT. See [LICENSE](LICENSE).
