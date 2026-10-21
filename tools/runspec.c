/* Headless 48K frame runner for the dino binary. Not part of the game. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "z80.h"

static uint8_t mem[65536];
static int space_down;
static int border_col;
static Z80Context ctx;
static int watchdog;

static byte mem_read(size_t param, ushort addr) {
    (void)param;
    return mem[addr];
}

static void mem_write(size_t param, ushort addr, byte data) {
    (void)param;
    if (addr >= 16384)
        mem[addr] = data;
}

static byte io_read(size_t param, ushort addr) {
    (void)param;
    if ((addr & 0xFF) != 0xFE)
        return 0xFF;
    byte v = 0xFF;
    if ((addr & 0x8000) == 0 && space_down)
        v &= (byte)~1;
    return v;
}

static void io_write(size_t param, ushort addr, byte data) {
    (void)param;
    if ((addr & 0xFF) == 0xFE) {
        border_col = data & 7;
    }
}

static int run_slice(int with_int) {
    int ops = 0;
    ctx.tstates = 0;
    if (with_int)
        Z80INT(&ctx, 0xFF);
    for (;;) {
        if (ctx.halted && !ctx.int_req)
            return ctx.tstates;
        Z80Execute(&ctx);
        if (++ops > watchdog) {
            fprintf(stderr, "TIMEOUT pc=%04X halted=%d iff=%d\n", ctx.PC, ctx.halted, ctx.IFF1);
            return -1;
        }
        if (ctx.PC < 0x4000) {
            fprintf(stderr, "CRASH pc=%04X\n", ctx.PC);
            return -1;
        }
    }
}

static int load_file(const char *path, uint8_t *dst, int maxn) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror(path);
        return -1;
    }
    int n = (int)fread(dst, 1, maxn, f);
    fclose(f);
    return n;
}

static int watch_addr(const char *watch, const char *name) {
    FILE *f = fopen(watch, "r");
    if (!f) {
        perror(watch);
        exit(1);
    }
    char n[64];
    unsigned addr;
    while (fscanf(f, "%63s %x", n, &addr) == 2) {
        if (strcmp(n, name) == 0) {
            fclose(f);
            return (int)addr;
        }
    }
    fclose(f);
    fprintf(stderr, "missing label %s\n", name);
    exit(1);
}

static int sword(int addr) {
    return (int)(int16_t)(mem[addr] | (mem[addr + 1] << 8));
}

static int uword(int addr) {
    return mem[addr] | (mem[addr + 1] << 8);
}

static int pixels_set(void) {
    int n = 0;
    for (int i = 0; i < 6144; i++) {
        uint8_t b = mem[16384 + i];
        while (b) {
            n += b & 1;
            b >>= 1;
        }
    }
    return n;
}

int main(int argc, char **argv) {
    if (argc < 7) {
        fprintf(stderr, "usage: runspec rom bin watch outdir mode frames\n");
        return 1;
    }
    const char *rom_path = argv[1];
    const char *bin_path = argv[2];
    const char *watch = argv[3];
    const char *outdir = argv[4];
    const char *mode = argv[5];
    int frames = atoi(argv[6]);
    watchdog = 2000000;

    int nrom = load_file(rom_path, mem, 16384);
    if (nrom != 16384) {
        fprintf(stderr, "rom size %d\n", nrom);
        return 1;
    }
    uint8_t bin[32768];
    int nbin = load_file(bin_path, bin, sizeof bin);
    if (nbin < 100) {
        fprintf(stderr, "bin size %d\n", nbin);
        return 1;
    }
    memcpy(mem + 0x8000, bin, nbin);

    int a_state = watch_addr(watch, "state");
    int a_frame = watch_addr(watch, "frame");
    int a_y = watch_addr(watch, "dino_y");
    int a_vy = watch_addr(watch, "dino_vy");
    int a_score = watch_addr(watch, "score");
    int a_speed = watch_addr(watch, "speed");
    int a_night = watch_addr(watch, "night");
    int a_obs = watch_addr(watch, "obs");
    int a_spawn = watch_addr(watch, "spawn_t");

    memset(&ctx, 0, sizeof ctx);
    ctx.memRead = mem_read;
    ctx.memWrite = mem_write;
    ctx.ioRead = io_read;
    ctx.ioWrite = io_write;
    Z80RESET(&ctx);
    ctx.PC = 0x8000;
    ctx.R1.wr.SP = 0xFCF0;
    ctx.R1.wr.IY = 0x5C3A;
    ctx.IFF1 = 0;
    ctx.IFF2 = 0;
    ctx.IM = 1;

    char logpath[512];
    snprintf(logpath, sizeof logpath, "%s/log.txt", outdir);
    FILE *log = fopen(logpath, "w");
    if (!log) {
        perror(logpath);
        return 1;
    }

    int ts = run_slice(0);
    fprintf(log, "init tstates=%d pc=%04X halted=%d iff=%d im=%d i=%02X isr=%02X%02X\n",
            ts, ctx.PC, ctx.halted, ctx.IFF1, ctx.IM, ctx.I, mem[0xFEFE], mem[0xFEFF]);
    if (ts < 0)
        return 1;

    int death_frame = -1;
    for (int f = 1; f <= frames; f++) {
        int st = mem[a_state];
        int y = mem[a_y];
        int vy = (int8_t)mem[a_vy];
        int speed = mem[a_speed];
        space_down = 0;
        if (strcmp(mode, "wait") == 0) {
            space_down = 0;
        } else if (strcmp(mode, "die") == 0) {
            space_down = (st == 0);
        } else if (strcmp(mode, "play") == 0) {
            if (st == 0)
                space_down = 1;
            else if (st == 2)
                space_down = (f % 40) > 20;
            else if (st == 1 && y >= 150 && vy == 0) {
                int threat = 0;
                int block = 0;
                int jump_at = 36 + speed * 18;
                for (int i = 0; i < 3; i++) {
                    int base = a_obs + i * 7;
                    int typ = mem[base + 2];
                    int x = sword(base);
                    if (!typ || x < 16 || x > 160)
                        continue;
                    if (typ == 5) {
                        if (x < jump_at + 30)
                            block = 1;
                        continue;
                    }
                    if (x < jump_at)
                        threat = 1;
                }
                if (threat && !block)
                    space_down = 1;
            }
        } else {
            fprintf(stderr, "bad mode %s\n", mode);
            return 1;
        }

        ts = run_slice(1);
        if (ts < 0)
            return 1;
        st = mem[a_state];
        if (st == 2 && death_frame < 0)
            death_frame = f;
        fprintf(log,
                "f=%d st=%d y=%d vy=%d sc=%d spd=%d night=%d fr=%d spawn=%d key=%d ts=%d px=%d border=%d",
                f, st, mem[a_y], (int)(int8_t)mem[a_vy], uword(a_score), mem[a_speed], mem[a_night],
                mem[a_frame], mem[a_spawn], space_down, ts, pixels_set(), border_col);
        for (int i = 0; i < 3; i++) {
            int base = a_obs + i * 7;
            fprintf(log, " o%d=%d:%d", i, mem[base + 2], sword(base));
        }
        fprintf(log, "\n");

        int save = (f <= 3) || (f % 25 == 0) || (st == 2 && f == death_frame) || (f == death_frame + 8);
        if (save) {
            char scr[512];
            snprintf(scr, sizeof scr, "%s/f%04d.scr", outdir, f);
            FILE *sf = fopen(scr, "wb");
            if (!sf) {
                perror(scr);
                return 1;
            }
            fwrite(mem + 16384, 1, 6912, sf);
            fclose(sf);
        }
        if (death_frame > 0 && f > death_frame + 30 && strcmp(mode, "die") == 0)
            break;
        if (death_frame > 0 && f > death_frame + 80 && strcmp(mode, "play") == 0)
            break;
    }
    fclose(log);
    printf("death_frame=%d\n", death_frame);
    return 0;
}
