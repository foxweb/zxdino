; ZX Spectrum 48K — «динозаврик» в духе офлайн-игры Chrome.
; Прыжок: SPACE или Q. Приседание: A или CAPS SHIFT.
; Забег начинается с любой клавиши. Если 5 секунд не начинать, и так же после
; GAME OVER, динозавр бежит сам. Любая клавиша прерывает демонстрацию.
; Точка входа: $8000. Сборка: python3 build.py

        org $8000

STATE_WAIT:  equ 0
STATE_RUN:   equ 1
STATE_DEAD:  equ 2
; 50 Гц × 5 с без старта — демонстрация.
DEMO_IDLE:   equ 250
; Кадры GAME OVER внутри демонстрации, затем новый забег.
DEMO_RETRY:  equ 100

GROUND_Y:    equ 168
DINO_H:      equ 18
DINO_Y0:     equ 150
DINO_X:      equ 32
DINO_COL:    equ 4
CAC_S_H:     equ 16
CAC_T_H:     equ 22
BIRD_H:      equ 10
BIRD_LOW_Y:  equ 148
BIRD_HIGH_Y: equ 116
CLOUD_H:     equ 8
CLOUD_N:     equ 4
STACK:       equ $FCF0

start:
        di
        ld sp, STACK
        ld iy, $5C3A
        call setup_im2
        call init_game
        ei

main_loop:
        halt
        call flush_attrs
        call early_clouds
        call update_world
        call render_world
        jr main_loop

; IM 2: любой вектор указывает на крошечный обработчик, без ПЗУ.
setup_im2:
        ld hl, $FD00
        ld de, $FD01
        ld bc, 256
        ld (hl), $FE
        ldir
        ld a, $FE
        ld ($FE00), a
        ld a, $FB
        ld ($FEFE), a
        ld a, $C9
        ld ($FEFF), a
        ld a, $FD
        ld i, a
        im 2
        ret

;------------------------------------------------------------
; Состояние кадра
;------------------------------------------------------------

update_world:
        ld hl, frame
        inc (hl)
        ld a, (state)
        cp STATE_WAIT
        jp z, update_wait
        cp STATE_DEAD
        jp z, update_dead
        ld a, (demo)
        or a
        jr z, uw_play
        call read_any
        jp z, abort_demo
uw_play:
        call update_run
        ret

update_wait:
        call read_any
        jr nz, uw_idle
        ld a, (can_start)
        or a
        ret z
        xor a
        ld (demo), a
        ld hl, 0
        ld (idle_t), hl
        ld a, STATE_RUN
        ld (state), a
        ret
uw_idle:
        ld a, (can_start)
        or a
        jr nz, uw_tick
        call read_any
        ret z
        ld a, 1
        ld (can_start), a
uw_tick:
        ld hl, (idle_t)
        inc hl
        ld (idle_t), hl
        ld de, DEMO_IDLE
        or a
        sbc hl, de
        ret c
        xor a
        ld (demo_dead), a
        ld a, 1
        ld (demo), a
        ld a, STATE_RUN
        ld (state), a
        ret

update_dead:
        ld a, (demo)
        or a
        jr z, dead_human
        call read_any
        jp z, abort_demo
        ld hl, demo_dead
        inc (hl)
        ld a, (hl)
        cp DEMO_RETRY
        ret c
        xor a
        ld (demo_dead), a
        call init_round
        ld a, 1
        ld (demo), a
        ld a, STATE_RUN
        ld (state), a
        ret
dead_human:
        call read_any
        jr z, dead_held
        ld a, 1
        ld (released), a
        jr dead_idle
dead_held:
        ld a, (released)
        or a
        ret z
        xor a
        ld (released), a
        ld (demo), a
        call init_round
        ld a, STATE_RUN
        ld (state), a
        ret
dead_idle:
        ld hl, (idle_t)
        inc hl
        ld (idle_t), hl
        ld de, DEMO_IDLE
        or a
        sbc hl, de
        ret c
        call init_round
        xor a
        ld (demo_dead), a
        ld a, 1
        ld (demo), a
        ld a, STATE_RUN
        ld (state), a
        ret

; Демонстрация прервана: снова заставка, через 5 секунд она включится опять.
abort_demo:
        xor a
        ld (demo), a
        ld (can_start), a
        ld (demo_dead), a
        ld (ducking), a
        ld (idle_t), a
        ld (idle_t+1), a
        call init_round
        xor a
        ld (state), a
        ret

update_run:
        call update_dino
        call update_obs
        call scroll_pebbles
        call try_spawn
        call update_score
        call update_speed
        call update_night
        call check_hit
        ret

; Z = клавиша прыжка зажата (SPACE или Q).
read_jump:
        ld a, $7F
        in a, ($FE)
        and 1
        ret z
        ld a, $FB
        in a, ($FE)
        and 1
        ret

; Z = приседание (A или CAPS SHIFT). CAPS SHIFT входит в стрелку вниз.
read_duck:
        ld a, $FE
        in a, ($FE)
        and 1
        ret z
        ld a, $FD
        in a, ($FE)
        and 1
        ret

; Z = нажата любая клавиша.
read_any:
        ld bc, $FEFE
ra_loop:
        in a, (c)
        and $1F
        cp $1F
        jr nz, ra_yes
        rlc b
        jr c, ra_loop
        or 1
        ret
ra_yes:
        xor a
        ret

; Демонстрация. Z = прыгнуть. Иначе при необходимости ставит ducking.
; Кактус — только в позднем окне, где одного прыжка хватает.
; Низкая птица — приседание. Высокая — не прыгать, под ней проход.
demo_act:
        xor a
        ld (demo_want), a
        ld (demo_block), a
        ld ix, obs
        ld b, 3
da_loop:
        push bc
        ld a, (ix+2)
        or a
        jp z, da_next
        ld l, (ix+0)
        ld h, (ix+1)
        ld de, 16
        call signed_lt
        jp c, da_next
        ld de, 220
        call signed_lt
        jp nc, da_next
        ld a, (ix+2)
        cp 4
        jr z, da_low
        cp 5
        jr z, da_high
        call cactus_window
        jr nz, da_next
        ld a, 1
        ld (demo_want), a
        jr da_next
da_low:
        ld de, 58
        call signed_lt
        jr nc, da_low_blk
        ld de, 18
        call signed_lt
        jr c, da_low_blk
        ld a, 1
        ld (ducking), a
da_low_blk:
        ld a, (ix+6)
        cp 3
        jr z, da_low3
        ld b, 26
        ld c, 47
        call x_between
        jr z, da_blk
        ld b, 66
        ld c, 89
        call x_between
        jr z, da_blk
        jr da_next
da_low3:
        ld b, 27
        ld c, 50
        call x_between
        jr z, da_blk
        ld b, 87
        ld c, 113
        call x_between
        jr z, da_blk
        jr da_next
da_blk:
        ld a, 1
        ld (demo_block), a
        jr da_next
da_high:
        ld a, (ix+6)
        cp 3
        ld de, 78
        jr c, da_hi_top
        ld de, 96
da_hi_top:
        call signed_lt
        jr nc, da_next
        ld a, (ix+6)
        cp 3
        ld de, 36
        jr c, da_hi_bot
        ld de, 42
da_hi_bot:
        call signed_lt
        jr c, da_next
        ld a, 1
        ld (demo_block), a
da_next:
        ld de, 7
        add ix, de
        pop bc
        dec b
        jp nz, da_loop
        ld a, (demo_block)
        or a
        jr nz, da_no
        ld a, (demo_want)
        or a
        jr z, da_no
        xor a
        ld (ducking), a
        ret
da_no:
        ld a, 1
        or a
        ret

; Z = x кактуса в окне одного прыжка для текущей скорости и типа ix+2.
; HL = x. IX сохраняется.
cactus_window:
        push hl
        push ix
        ld a, (speed)
        sub 2
        ld c, a
        add a, a
        add a, c
        ld c, a
        ld a, (ix+2)
        dec a
        add a, c
        add a, a
        ld e, a
        ld d, 0
        ld hl, jump_tbl
        add hl, de
        ld c, (hl)
        inc hl
        ld b, (hl)
        pop ix
        pop hl
        ld a, c
        inc a
        ld e, a
        ld d, 0
        call signed_lt
        jr c, cw_low
        or 1
        ret
cw_low:
        ld a, b
        ld e, a
        ld d, 0
        call signed_lt
        jr c, cw_out
        xor a
        ret
cw_out:
        or 1
        ret

; Z = B <= x <= C. HL = x, IX сохраняются.
x_between:
        ld a, c
        inc a
        ld e, a
        ld d, 0
        call signed_lt
        jr c, xb_lo
        or 1
        ret
xb_lo:
        ld e, b
        ld d, 0
        call signed_lt
        jr c, xb_out
        xor a
        ret
xb_out:
        or 1
        ret

update_dino:
        ld a, (dino_y)
        cp DINO_Y0
        jr c, dino_air
        ld a, DINO_Y0
        ld (dino_y), a
        xor a
        ld (dino_vy), a
        ld (ducking), a
        ld a, (demo)
        or a
        jr z, ud_human
        call demo_act
        jr ud_gate
ud_human:
        call read_duck
        jr nz, ud_key
        ld a, 1
        ld (ducking), a
        ret
ud_key:
        call read_jump
ud_gate:
        ret nz
        ld a, -6
        ld (dino_vy), a
        xor a
        ld (grav_phase), a
        call jump_snd
dino_air:
        ld a, (dino_vy)
        ld hl, dino_y
        add a, (hl)
        ld (hl), a
        ld a, (grav_phase)
        xor 1
        ld (grav_phase), a
        jr z, dino_land
        ld hl, dino_vy
        inc (hl)
dino_land:
        ld a, (dino_y)
        cp DINO_Y0
        ret c
        ld a, DINO_Y0
        ld (dino_y), a
        xor a
        ld (dino_vy), a
        ret

; Кактусы едут влево с общей speed.
; Птица тоже только влево, к динозавру: свой шаг в ix+6, 2 или 3 пикселя.
update_obs:
        ld ix, obs
        ld b, 3
uo_loop:
        push bc
        ld a, (ix+2)
        or a
        jr z, uo_next
        ld l, (ix+0)
        ld h, (ix+1)
        ld a, (ix+2)
        cp 4
        jr c, uo_cactus
        ld a, (ix+6)
        cp 2
        jr nc, uo_sub
        ld a, 2
        jr uo_sub
uo_cactus:
        ld a, (speed)
uo_sub:
        ld e, a
        ld d, 0
        or a
        sbc hl, de
        ld (ix+0), l
        ld (ix+1), h
        ld de, -24
        call signed_lt
        jr nc, uo_next
        ld (ix+2), 0
uo_next:
        ld de, 7
        add ix, de
        pop bc
        djnz uo_loop
        ret

; Четыре слота по 6 байт: x, y, старый x, старый y.
; y = 0 — слот пуст. На экране обычно 2, 3 или 4 облака.
update_clouds:
        ld ix, clouds
        ld b, CLOUD_N
uc_loop:
        push bc
        ld l, (ix+0)
        ld h, (ix+1)
        dec hl
        ld de, -16
        call signed_lt
        jr nc, uc_keep
        call cloud_respawn
        jr uc_next
uc_keep:
        ld (ix+0), l
        ld (ix+1), h
uc_next:
        ld de, 6
        add ix, de
        pop bc
        djnz uc_loop
        ret

; Ушедшее влево облако появляется справа: дальше от уже видимых,
; и на свободной высоте. Если видимых меньше двух — сразу с правого края.
cloud_respawn:
        push ix
        pop hl
        ld (cloud_self), hl
        call cloud_count_vis
        cp 2
        jr c, cr_enter
        call cloud_right_vis
        ld b, 5
cr_try:
        push bc
        call cloud_rnd
        and 63
        add a, 56
        ld e, a
        ld d, 0
        ld hl, (cloud_max)
        add hl, de
        call cloud_clear_of
        pop bc
        jr z, cr_y
        djnz cr_try
        ld hl, (cloud_max)
        ld de, 96
        add hl, de
        jr cr_y
cr_enter:
        ld hl, 224
        call cloud_clear_of
        jr z, cr_y
        ld hl, 156
        call cloud_clear_of
        jr z, cr_y
        ld hl, 88
        call cloud_clear_of
        jr z, cr_y
        ld hl, 28
cr_y:
        ld (ix+0), l
        ld (ix+1), h
        call cloud_pick_y
        ld (ix+2), a
        ret

; A = сколько других облаков сейчас в кадре. cloud_self задан, IX сохраняется.
cloud_count_vis:
        xor a
        ld (cloud_nvis), a
        push ix
        ld ix, clouds
        ld b, CLOUD_N
ccv_loop:
        push bc
        push ix
        pop hl
        ld de, (cloud_self)
        or a
        sbc hl, de
        jr z, ccv_next
        ld e, (ix+0)
        ld d, (ix+1)
        call cloud_visible
        jr nz, ccv_next
        ld a, (cloud_nvis)
        inc a
        ld (cloud_nvis), a
ccv_next:
        ld de, 6
        add ix, de
        pop bc
        djnz ccv_loop
        pop ix
        ld a, (cloud_nvis)
        ret

; HL = самый правый другой видимый x. Результат ещё и в cloud_max.
cloud_right_vis:
        ld hl, 0
        ld (cloud_max), hl
        push ix
        ld ix, clouds
        ld b, CLOUD_N
crv_loop:
        push bc
        push ix
        pop hl
        ld de, (cloud_self)
        or a
        sbc hl, de
        jr z, crv_next
        ld e, (ix+0)
        ld d, (ix+1)
        call cloud_visible
        jr nz, crv_next
        ld l, e
        ld h, d
        ld de, (cloud_max)
        call signed_lt
        jr c, crv_next
        ld (cloud_max), hl
crv_next:
        ld de, 6
        add ix, de
        pop bc
        djnz crv_loop
        pop ix
        ld hl, (cloud_max)
        ret

; Z = -16 <= DE < 256.
cloud_visible:
        ld a, d
        or a
        jr z, cv_yes
        cp $FF
        jr nz, cv_no
        ld a, e
        cp $F0
        jr c, cv_no
cv_yes:
        xor a
        ret
cv_no:
        or 1
        ret

; Z = HL не ближе 56 пикселей к чужому облаку. IX и HL сохраняются.
cloud_clear_of:
        ld (cloud_try), hl
        ld hl, clouds
        ld b, CLOUD_N
cco_loop:
        push bc
        ld de, (cloud_self)
        ld a, l
        cp e
        jr nz, cco_cmp
        ld a, h
        cp d
        jr z, cco_next
cco_cmp:
        ld e, (hl)
        inc hl
        ld d, (hl)
        dec hl
        push hl
        ld hl, (cloud_try)
        or a
        sbc hl, de
        jr nc, cco_abs
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        inc hl
cco_abs:
        ld a, h
        or a
        jr nz, cco_far
        ld a, l
        cp 56
        jr c, cco_hit
cco_far:
        pop hl
        jr cco_next
cco_hit:
        pop hl
        pop bc
        ld hl, (cloud_try)
        or 1
        ret
cco_next:
        ld de, 6
        add hl, de
        pop bc
        djnz cco_loop
        ld hl, (cloud_try)
        xor a
        ret

; A = свободная высота. Текущие y слотов не повторяются.
cloud_pick_y:
        ld b, 16
cpy_loop:
        call cloud_rnd
        and 7
        cp 5
        jr c, cpy_lane
        djnz cpy_loop
        xor a
cpy_lane:
        ld e, a
        ld d, 0
        ld hl, cloud_ys
        add hl, de
        ld c, (hl)
        ld hl, clouds+2
        ld e, CLOUD_N
cpy_scan:
        ld a, (hl)
        cp c
        jr z, cpy_busy
        ld a, l
        add a, 6
        ld l, a
        jr nc, cpy_nh
        inc h
cpy_nh:
        dec e
        jr nz, cpy_scan
        ld a, c
        ret
cpy_busy:
        djnz cpy_loop
        ld a, c
        ret

; Свой счётчик, чтобы облака не сдвигали последовательность препятствий.
cloud_rnd:
        push bc
        push de
        push hl
        ld hl, (seed)
        push hl
        ld hl, (cloud_seed)
        ld (seed), hl
        call rnd
        ld hl, (seed)
        ld (cloud_seed), hl
        pop hl
        ld (seed), hl
        pop hl
        pop de
        pop bc
        ret

; Раскладки: 2, 3 или 4 облака в кадре, остальные ждут справа.
init_clouds:
        ld hl, clouds
        ld de, clouds+1
        ld bc, CLOUD_N*6-1
        ld (hl), 0
        ldir
        call cloud_rnd
        and 7
        cp 6
        jr c, ic_lay
        xor a
ic_lay:
        add a, a
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld hl, cloud_layouts
        add hl, de
        ld ix, clouds
        ld b, CLOUD_N
ic_loop:
        push bc
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        push hl
        call cloud_rnd
        and 15
        sub 8
        ld l, a
        add a, a
        sbc a, a
        ld h, a
        add hl, de
        ld (ix+0), l
        ld (ix+1), h
        ld (ix+3), l
        ld (ix+4), h
        call cloud_pick_y
        ld (ix+2), a
        ld (ix+5), a
        ld de, 6
        add ix, de
        pop hl
        pop bc
        djnz ic_loop
        ret

; Один проход на speed бит. Бит камешка — с вероятностью 1/16.
scroll_pebbles:
        call rnd_core
        ld d, h
        ld e, l
        ld c, 0
        ld a, e
        and $0F
        jr nz, spb1
        set 0, c
spb1:
        ld a, e
        and $F0
        jr nz, spb2
        set 1, c
spb2:
        ld a, d
        and $0F
        jr nz, spb3
        set 2, c
spb3:
        ld a, d
        and $F0
        jr nz, spb4
        set 3, c
spb4:
        ld a, (speed)
        cp 5
        jr c, sp_mask
        push bc
        call rnd_core
        and $0F
        pop bc
        jr nz, sp_mask
        set 4, c
sp_mask:
        ld a, (speed)
        ld b, a
        ld a, 1
sp_ml:
        add a, a
        djnz sp_ml
        dec a
        and c
        ld c, a
        ld a, (speed)
        cp 3
        jp c, sp_sh2
        jp z, sp_sh3
        cp 5
        jp c, sp_sh4
        jp z, sp_sh5
        cp 7
        jp c, sp_sh6
        jp sp_sh7

sp_sh2:
        ld hl, pebbles+31
        ld b, 32
sp_sh2l:
        ld a, (hl)
        ld e, a
        rlca
        rlca
        and 3
        ld d, a
        ld a, e
        add a, a
        add a, a
        or c
        ld (hl), a
        ld c, d
        dec hl
        djnz sp_sh2l
        ret

sp_sh3:
        ld hl, pebbles+31
        ld b, 32
sp_sh3l:
        ld a, (hl)
        ld e, a
        rlca
        rlca
        rlca
        and 7
        ld d, a
        ld a, e
        add a, a
        add a, a
        add a, a
        or c
        ld (hl), a
        ld c, d
        dec hl
        djnz sp_sh3l
        ret

sp_sh4:
        ld hl, pebbles+31
        ld b, 32
sp_sh4l:
        ld a, (hl)
        ld e, a
        rlca
        rlca
        rlca
        rlca
        and 15
        ld d, a
        ld a, e
        add a, a
        add a, a
        add a, a
        add a, a
        or c
        ld (hl), a
        ld c, d
        dec hl
        djnz sp_sh4l
        ret

sp_sh5:
        ld hl, pebbles+31
        ld b, 32
sp_sh5l:
        ld a, (hl)
        ld e, a
        rlca
        rlca
        rlca
        rlca
        rlca
        and 31
        ld d, a
        ld a, e
        add a, a
        add a, a
        add a, a
        add a, a
        add a, a
        or c
        ld (hl), a
        ld c, d
        dec hl
        djnz sp_sh5l
        ret

sp_sh6:
        ld hl, pebbles+31
        ld b, 32
sp_sh6l:
        ld a, (hl)
        ld e, a
        rlca
        rlca
        rlca
        rlca
        rlca
        rlca
        and 63
        ld d, a
        ld a, e
        add a, a
        add a, a
        add a, a
        add a, a
        add a, a
        add a, a
        or c
        ld (hl), a
        ld c, d
        dec hl
        djnz sp_sh6l
        ret

sp_sh7:
        ld hl, pebbles+31
        ld b, 32
sp_sh7l:
        ld a, (hl)
        ld e, a
        rlca
        rlca
        rlca
        rlca
        rlca
        rlca
        rlca
        and 127
        ld d, a
        ld a, e
        add a, a
        add a, a
        add a, a
        add a, a
        add a, a
        add a, a
        add a, a
        or c
        ld (hl), a
        ld c, d
        dec hl
        djnz sp_sh7l
        ret

try_spawn:
        ld a, (spawn_t)
        or a
        jr z, ts_go
        dec a
        ld (spawn_t), a
        ret
ts_go:
        ld hl, -200
        ld (max_x), hl
        ld ix, obs
        ld b, 3
ts_max:
        push bc
        ld a, (ix+2)
        or a
        jr z, ts_max_n
        ld l, (ix+0)
        ld h, (ix+1)
        ld (tmp_x), hl
        ld de, (tmp_x)
        ld hl, (max_x)
        call signed_lt
        jr nc, ts_max_n
        ld hl, (tmp_x)
        ld (max_x), hl
ts_max_n:
        ld de, 7
        add ix, de
        pop bc
        djnz ts_max
        ld hl, (max_x)
        ld de, 176
        call signed_lt
        jr c, ts_slot
        ld a, 4
        ld (spawn_t), a
        ret
ts_slot:
        ld ix, obs
        ld b, 3
ts_find:
        ld a, (ix+2)
        or a
        jr z, ts_put
        ld de, 7
        add ix, de
        djnz ts_find
        ld a, 4
        ld (spawn_t), a
        ret
ts_put:
        call pick_type
        ld (ix+2), a
        ld hl, 256
        ld (ix+0), l
        ld (ix+1), h
        cp 4
        jr c, ts_gap
        call rnd
        and 1
        add a, 2
        ld (ix+6), a
ts_gap:
        call rnd
        and 63
        add a, 50
        ld c, a
        ld a, (speed)
        add a, a
        add a, a
        ld b, a
        ld a, c
        sub b
        cp 28
        jr nc, ts_store
        ld a, 28
ts_store:
        ld (spawn_t), a
        ret

; A = тип: 1 маленький кактус, 2 высокий, 3 двойной, 4 птица низко, 5 птица высоко.
pick_type:
        ld a, (first_spawn)
        or a
        jr z, pt_norm
        xor a
        ld (first_spawn), a
        ld a, 1
        ret
pt_norm:
        call rnd
        and 7
        cp 6
        jr nc, pt_bird
        cp 2
        jr c, pt_small
        cp 4
        jr c, pt_tall
        ld a, 3
        ret
pt_small:
        ld a, 1
        ret
pt_tall:
        ld a, 2
        ret
pt_bird:
        ld hl, (score)
        ld de, 80
        or a
        sbc hl, de
        jr nc, pt_bird_ok
        ld a, 1
        ret
pt_bird_ok:
        ld hl, (score)
        ld de, 250
        or a
        sbc hl, de
        jr nc, pt_bird_any
        ld a, 4
        ret
pt_bird_any:
        call rnd
        and 1
        add a, 4
        ret

update_score:
        ld a, (score_frac)
        ld hl, speed
        add a, (hl)
us_loop:
        cp 6
        jr c, us_store
        sub 6
        push af
        ld hl, (score)
        inc hl
        ld (score), hl
        ld a, h
        or l
        jr z, us_wrap
        call bump_score_digits
        call maybe_ding
        jr us_next
us_wrap:
        call zero_score_dig
us_next:
        pop af
        jr us_loop
us_store:
        ld (score_frac), a
        ret

; score_from — первая цифра, которую нужно перерисовать. 5 = экран свежий.
bump_score_digits:
        ld hl, score_dig+4
        ld c, 4
bsd_loop:
        inc (hl)
        ld a, (hl)
        cp 10
        jr c, bsd_mark
        ld (hl), 0
        dec hl
        dec c
        jp p, bsd_loop
        ld c, 0
bsd_mark:
        ld hl, score_from
        ld a, (hl)
        cp c
        ret c
        ret z
        ld (hl), c
        ret

zero_score_dig:
        xor a
        ld (score_from), a
        ld hl, score_dig
        ld b, 5
zsd_loop:
        ld (hl), a
        inc hl
        djnz zsd_loop
        ret

; Один раз за забег, когда счёт строго больше уже существующего HI.
maybe_ding:
        ld a, (hi_chime)
        or a
        ret nz
        ld hl, (hi_score)
        ld a, h
        or l
        ret z
        ex de, hl
        ld hl, (score)
        or a
        sbc hl, de
        ret z
        ret c
        ld a, 1
        ld (hi_chime), a
        jp ding_snd

update_speed:
        ld a, (score+1)
        cp 5
        jr c, usp_ok
        ld a, 5
usp_ok:
        add a, 2
        ld (speed), a
        ret

update_night:
        ld a, (score+1)
        and 1
        ld b, a
        ld a, (night)
        cp b
        ret z
        ld a, b
        ld (night), a
        ld a, 1
        ld (attr_dirty), a
        ret

check_hit:
        ld ix, obs
        ld b, 3
ch_loop:
        push bc
        ld a, (ix+2)
        or a
        jr z, ch_next
        call dino_hitbox
        call obs_hitbox
        call rects_overlap
        jr nc, ch_next
        pop bc
        call die
        ret
ch_next:
        ld de, 7
        add ix, de
        pop bc
        djnz ch_loop
        ret

die:
        ld a, STATE_DEAD
        ld (state), a
        xor a
        ld (released), a
        ld (ducking), a
        ld (idle_t), a
        ld (idle_t+1), a
        ld (demo_dead), a
        ld hl, (score)
        ld de, (hi_score)
        or a
        sbc hl, de
        jr c, die_snd
        ld hl, (score)
        ld (hi_score), hl
        ld hl, score_dig
        ld de, hi_dig
        ld bc, 5
        ldir
        xor a
        ld (hi_from), a
die_snd:
        ld a, 1
        ld (death_play), a
        ret

dino_hitbox:
        ld hl, DINO_X+5
        ld (ax), hl
        ld a, 7
        ld (aw), a
        ld a, (ducking)
        or a
        jr z, dh_stand
        ld a, (dino_y)
        add a, 10
        ld (ay), a
        ld a, 7
        ld (ah), a
        ret
dh_stand:
        ld a, (dino_y)
        add a, 1
        ld (ay), a
        ld a, 16
        ld (ah), a
        ret

obs_hitbox:
        ld l, (ix+0)
        ld h, (ix+1)
        inc hl
        inc hl
        ld (bx), hl
        ld a, (ix+2)
        cp 2
        jr z, oh_tall
        cp 3
        jr z, oh_wide
        cp 4
        jr z, oh_blow
        cp 5
        jr z, oh_bhigh
        ld a, 4
        ld (bw), a
        ld a, GROUND_Y-12
        ld (by), a
        ld a, 10
        ld (bh), a
        ret
oh_tall:
        ld a, 4
        ld (bw), a
        ld a, GROUND_Y-18
        ld (by), a
        ld a, 16
        ld (bh), a
        ret
oh_wide:
        ld a, 10
        ld (bw), a
        ld a, GROUND_Y-12
        ld (by), a
        ld a, 10
        ld (bh), a
        ret
oh_blow:
        ld a, 12
        ld (bw), a
        ld a, BIRD_LOW_Y+2
        ld (by), a
        ld a, 6
        ld (bh), a
        ret
oh_bhigh:
        ld a, 12
        ld (bw), a
        ld a, BIRD_HIGH_Y+2
        ld (by), a
        ld a, 6
        ld (bh), a
        ret

; CF = 1, если прямоугольники пересекаются. X знаковые 16 бит.
rects_overlap:
        ld hl, (bx)
        ld a, (bw)
        ld e, a
        ld d, 0
        add hl, de
        ex de, hl
        ld hl, (ax)
        call signed_lt
        ret nc
        ld hl, (ax)
        ld a, (aw)
        ld e, a
        ld d, 0
        add hl, de
        ex de, hl
        ld hl, (bx)
        call signed_lt
        ret nc
        ld a, (by)
        ld hl, bh
        add a, (hl)
        ld c, a
        ld a, (ay)
        cp c
        ret nc
        ld a, (ay)
        ld hl, ah
        add a, (hl)
        ld c, a
        ld a, (by)
        cp c
        ret nc
        scf
        ret

; CF = 1, если знаковый HL < знакового DE. HL и DE сохраняются.
signed_lt:
        push hl
        push de
        ld a, h
        xor $80
        ld h, a
        ld a, d
        xor $80
        ld d, a
        or a
        sbc hl, de
        pop de
        pop hl
        ret

; xorshift 16. Результат в A, seed обновлён. BC, DE, HL сохраняются.
rnd:
        push bc
        push de
        push hl
        call rnd_core
        pop hl
        pop de
        pop bc
        ret

; То же, но HL = новое seed, A = младший байт. BC сохраняется.
rnd_core:
        push bc
        ld hl, (seed)
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
        xor d
        ld h, a
        ld a, l
        xor e
        ld l, a
        ld d, h
        ld e, l
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        ld a, h
        xor d
        ld h, a
        ld a, l
        xor e
        ld l, a
        ld a, h
        xor l
        ld h, a
        ld (seed), hl
        ld a, l
        pop bc
        ret

; Дин-дон: короткая высокая нота, затем короткая более низкая.
ding_snd:
        ld c, 50
        ld b, 60
        call dn_note
        ld c, 85
        ld b, 45
        jp dn_note

dn_note:
dn_loop:
        ld a, (border_col)
        or $10
        out ($FE), a
        ld a, c
dn_d1:
        dec a
        jr nz, dn_d1
        ld a, (border_col)
        out ($FE), a
        ld a, c
dn_d2:
        dec a
        jr nz, dn_d2
        djnz dn_loop
        ret

jump_snd:
        ld b, 18
js_loop:
        ld a, (border_col)
        or $10
        out ($FE), a
        ld a, 10
js_d1:
        dec a
        jr nz, js_d1
        ld a, (border_col)
        out ($FE), a
        ld a, 14
js_d2:
        dec a
        jr nz, js_d2
        djnz js_loop
        ret

; Нисходящий тон примерно от 200 до 60 Гц, около 200 мс.
death_snd:
        ld hl, 330
        ld b, 19
ds_loop:
        ld a, (border_col)
        or $10
        out ($FE), a
        push hl
        pop de
        call ds_wait
        ld a, (border_col)
        out ($FE), a
        push hl
        pop de
        call ds_wait
        ld de, 42
        add hl, de
        djnz ds_loop
        ret

ds_wait:
        dec de
        ld a, d
        or e
        jr nz, ds_wait
        ret

;------------------------------------------------------------
; Кадр
;------------------------------------------------------------

; Облака живут вверху экрана. Стирание и новая отрисовка — сразу после
; прерывания, пока луч ещё в верхней рамке: иначе между стиранием и
; рисованием кадр показывает пустое место.
early_clouds:
        ld a, (need_cls)
        or a
        ret nz
        call update_clouds
        jp paint_clouds

paint_clouds:
        call erase_clouds
        call draw_clouds
        ld ix, clouds
        ld b, CLOUD_N
pc_old:
        ld a, (ix+0)
        ld (ix+3), a
        ld a, (ix+1)
        ld (ix+4), a
        ld a, (ix+2)
        ld (ix+5), a
        ld de, 6
        add ix, de
        djnz pc_old
        xor a
        ld (cloud_dirty), a
        ret

render_world:
        ld a, (need_cls)
        or a
        jr z, rw_clouds
        call cls_pixels
        call draw_ground_lines
        call draw_sign
        xor a
        ld (need_cls), a
        inc a
        ld (cloud_dirty), a
rw_clouds:
        ld a, (cloud_dirty)
        or a
        call nz, paint_clouds
        call erase_dino
        call erase_obs
        call draw_ground
        call draw_obs
        call draw_dino
        call draw_hud
        call commit_positions
        ld a, (death_play)
        or a
        ret z
        xor a
        ld (death_play), a
        jp death_snd

cls_pixels:
        ld hl, $4000
        ld de, $4001
        ld bc, $17FF
        ld (hl), 0
        ldir
        ret

; Последняя символьная строка, один раз после очистки экрана.
draw_sign:
        ld b, 23
        ld c, 3
        call char_addr
        ld hl, str_copy
        call print_str
        ret

; Заливка атрибутов в верхней рамке, сразу после HALT. Стек на время
; смотрит в экран, поэтому прерывания выключены.
flush_attrs:
        ld a, (attr_dirty)
        or a
        ret z
        xor a
        ld (attr_dirty), a
        di
        ld (saved_sp), sp
        ld a, (night)
        or a
        ld hl, $4747
        jr z, fa_fill
        ld hl, $7878
fa_fill:
        ld sp, $5B00
        ld b, 96
fa_loop:
        push hl
        push hl
        push hl
        push hl
        djnz fa_loop
        ld sp, (saved_sp)
        ld a, (night)
        or a
        jr z, fa_day
        ld a, 7
        jr fa_out
fa_day:
        xor a
fa_out:
        ld (border_col), a
        out ($FE), a
        ei
        ret

erase_dino:
        ld a, (old_dino_y)
        call dino_de
        ld b, DINO_H
        jp es2

erase_obs:
        ld ix, obs
        ld b, 3
eo_loop:
        push bc
        ld a, (ix+5)
        or a
        jr z, eo_next
        ld l, (ix+3)
        ld h, (ix+4)
        ld (spr_x), hl
        ld a, (ix+5)
        call metrics_from_type
        call erase_sprite
eo_next:
        ld de, 7
        add ix, de
        pop bc
        djnz eo_loop
        ret

erase_clouds:
        ld ix, clouds
        ld b, CLOUD_N
erc_loop:
        push bc
        ld a, (ix+5)
        or a
        jr z, erc_next
        ld l, (ix+3)
        ld h, (ix+4)
        call erase_cloud
erc_next:
        ld de, 6
        add ix, de
        pop bc
        djnz erc_loop
        ret

erase_cloud:
        ld (spr_x), hl
        ld (spr_y), a
        ld a, CLOUD_H
        ld (spr_h), a
        ld a, 3
        ld (spr_w), a
        jp erase_sprite

; A = тип. Ставит spr_y, spr_h и spr_w (видимая ширина в байтах).
metrics_from_type:
        cp 2
        jr z, mt_tall
        cp 3
        jr z, mt_wide
        cp 4
        jr z, mt_blow
        cp 5
        jr z, mt_bhigh
        cp 1
        jr nz, mt_blow
mt_short:
        ld a, GROUND_Y-CAC_S_H
        ld (spr_y), a
        ld a, CAC_S_H
        ld (spr_h), a
        ld a, 2
        ld (spr_w), a
        ret
mt_wide:
        ld a, GROUND_Y-CAC_S_H
        ld (spr_y), a
        ld a, CAC_S_H
        ld (spr_h), a
        ld a, 3
        ld (spr_w), a
        ret
mt_tall:
        ld a, GROUND_Y-CAC_T_H
        ld (spr_y), a
        ld a, CAC_T_H
        ld (spr_h), a
        ld a, 2
        ld (spr_w), a
        ret
mt_blow:
        ld a, BIRD_LOW_Y
        ld (spr_y), a
        ld a, BIRD_H
        ld (spr_h), a
        ld a, 3
        ld (spr_w), a
        ret
mt_bhigh:
        ld a, BIRD_HIGH_Y
        ld (spr_y), a
        ld a, BIRD_H
        ld (spr_h), a
        ld a, 3
        ld (spr_w), a
        ret

; Линии земли не меняются. Камешки — отдельной строкой каждый кадр.
draw_ground_lines:
        ld b, GROUND_Y
        call fill_row_ff
        ld b, GROUND_Y+1
        jp fill_row_ff

draw_ground:
        ld b, GROUND_Y+3
        ld a, 0
        call pixadr
        ld hl, pebbles
        ld bc, 32
        ldir
        ret

fill_row_ff:
        ld a, 0
        call pixadr
        ld a, $FF
        ld b, 32
fr_loop:
        ld (de), a
        inc e
        djnz fr_loop
        ret

draw_clouds:
        ld ix, clouds
        ld b, CLOUD_N
drc_loop:
        push bc
        ld a, (ix+2)
        or a
        jr z, drc_next
        ld l, (ix+0)
        ld h, (ix+1)
        call draw_cloud
drc_next:
        ld de, 6
        add ix, de
        pop bc
        djnz drc_loop
        ret

draw_cloud:
        ld (spr_x), hl
        ld (spr_y), a
        ld a, 3
        ld (spr_w), a
        ld hl, cloud
        ld b, CLOUD_H
        jp blit

draw_obs:
        ld ix, obs
        ld b, 3
do_loop:
        push bc
        ld a, (ix+2)
        or a
        jr z, do_next
        ld l, (ix+0)
        ld h, (ix+1)
        ld (spr_x), hl
        ld a, (ix+2)
        call sprite_for_type
        call blit
do_next:
        ld de, 7
        add ix, de
        pop bc
        djnz do_loop
        ret

; A = тип. HL = спрайт, B = высота, C = ширина в байтах, spr_y задан.
sprite_for_type:
        cp 2
        jr z, sf_tall
        cp 3
        jr z, sf_wide
        cp 4
        jr z, sf_bird
        cp 5
        jr z, sf_bird_h
        ld hl, cac_small
        ld a, GROUND_Y-CAC_S_H
        ld (spr_y), a
        ld b, CAC_S_H
        ld c, 1
        ld a, 2
        ld (spr_w), a
        ret
sf_tall:
        ld hl, cac_tall
        ld a, GROUND_Y-CAC_T_H
        ld (spr_y), a
        ld b, CAC_T_H
        ld c, 1
        ld a, 2
        ld (spr_w), a
        ret
sf_wide:
        ld hl, cac_wide
        ld a, GROUND_Y-CAC_S_H
        ld (spr_y), a
        ld b, CAC_S_H
        ld c, 2
        ld a, 3
        ld (spr_w), a
        ret
sf_bird_h:
        ld a, BIRD_HIGH_Y
        jr sf_bird_y
sf_bird:
        ld a, BIRD_LOW_Y
sf_bird_y:
        ld (spr_y), a
        ld a, (frame)
        and 8
        jr z, sf_b1
        ld hl, bird2
        jr sf_bdone
sf_b1:
        ld hl, bird1
sf_bdone:
        ld b, BIRD_H
        ld c, 2
        ld a, 3
        ld (spr_w), a
        ret

draw_dino:
        ld a, (state)
        cp STATE_DEAD
        jr z, dd_dead
        cp STATE_WAIT
        jr z, dd_stand
        ld a, (dino_y)
        cp DINO_Y0
        jr c, dd_jump
        ld a, (ducking)
        or a
        jr z, dd_legs
        ld a, (frame)
        and 8
        jr z, dd_dk1
        ld hl, dino_duck2
        jr dd_go
dd_dk1:
        ld hl, dino_duck1
        jr dd_go
dd_legs:
        ld a, (frame)
        and 8
        jr z, dd_stand
        ld hl, dino_run2
        jr dd_go
dd_stand:
        ld hl, dino_run1
        jr dd_go
dd_jump:
        ld hl, dino_jump
        jr dd_go
dd_dead:
        ld hl, dino_dead
dd_go:
        ld a, (dino_y)
        call dino_de
        ld b, DINO_H
        jp dino_or

; A = Y. DE = адрес колонки динозавра. X всегда 32, сдвиг 0.
dino_de:
        ld b, a
        ld a, DINO_COL
        jp pixadr

; HL = кадр сдвига 0 (3 байта в строке, третий нулевой). B = высота, DE = экран.
; Накладывается через OR: кактус уже нарисован прямой записью.
dino_or:
        ld a, d
        and 7
        ld c, a
        ld a, 8
        sub c
        cp b
        jr c, dor_fit
        ld a, b
dor_fit:
        ld c, a
        ld a, b
        sub c
        ld b, a
dor_row:
        ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        inc hl
        dec e
        dec c
        jr z, dor_end
        inc d
        jr dor_row
dor_end:
        ld a, b
        or a
        ret z
        inc d
        ld a, e
        add a, 32
        ld e, a
        jr c, dino_or
        ld a, d
        sub 8
        ld d, a
        jr dino_or

draw_hud:
        ld a, (hud_ready)
        or a
        jr nz, hud_nums
        ld b, 0
        ld c, 14
        call char_addr
        ld hl, str_hi
        call print_str
        ld a, 1
        ld (hud_ready), a
        ld a, $FF
        ld (hud_msg), a
hud_nums:
        ld a, (hi_from)
        cp 5
        jr nc, hud_no_hi
        ld c, a
        ld b, 0
        ld hl, hi_dig
        add hl, bc
        ld a, c
        add a, 17
        ld c, a
        ld b, 0
        push hl
        call char_addr
        pop hl
        ld a, (hi_from)
        ld b, a
        ld a, 5
        sub b
        ld b, a
hud_hi_d:
        push bc
        push hl
        ld a, (hl)
        add a, '0'
        call print_char
        pop hl
        inc hl
        pop bc
        djnz hud_hi_d
        ld a, 5
        ld (hi_from), a
hud_no_hi:
        ld a, (score_from)
        cp 5
        jr nc, hud_no_sc
        ld c, a
        ld b, 0
        ld hl, score_dig
        add hl, bc
        ld a, c
        add a, 24
        ld c, a
        ld b, 0
        push hl
        call char_addr
        pop hl
        ld a, (score_from)
        ld b, a
        ld a, 5
        sub b
        ld b, a
hud_sc_d:
        push bc
        push hl
        ld a, (hl)
        add a, '0'
        call print_char
        pop hl
        inc hl
        pop bc
        djnz hud_sc_d
        ld a, 5
        ld (score_from), a
hud_no_sc:
        ld a, (state)
        cp STATE_RUN
        jr nz, hud_phase
        ld a, (demo)
        or a
        jr z, hud_run_id
        ld a, 3
        jr hud_phase
hud_run_id:
        ld a, STATE_RUN
hud_phase:
        ld hl, hud_msg
        cp (hl)
        ret z
        ld (hl), a
        call hud_clear_msg
        ld a, (state)
        cp STATE_WAIT
        jp z, hud_legend
        cp STATE_DEAD
        jp z, hud_dead
        ld a, (demo)
        or a
        ret z
        ld b, 8
        ld c, 14
        call char_addr
        ld hl, str_demo
        jp print_str

hud_legend:
        ld b, 8
        ld c, 8
        call char_addr
        ld hl, str_jump
        call print_str
        ld b, 9
        ld c, 12
        call char_addr
        ld hl, str_duck
        call print_str
        ld b, 10
        ld c, 8
        call char_addr
        ld hl, str_start
        jp print_str

hud_dead:
        ld b, 8
        ld c, 11
        call char_addr
        ld hl, str_over
        call print_str
        ld b, 10
        ld c, 10
        call char_addr
        ld hl, str_hit
        jp print_str

; Строки 8..10, колонки 8..22: туда помещаются легенда и GAME OVER.
hud_clear_msg:
        ld b, 8
hcm_loop:
        push bc
        ld c, 8
        call char_addr
        ld hl, str_wide
        call print_str
        pop bc
        inc b
        ld a, b
        cp 11
        jr c, hcm_loop
        ret

commit_positions:
        ld hl, DINO_X
        ld (old_dino_x), hl
        ld a, (dino_y)
        ld (old_dino_y), a
        ld ix, obs
        ld b, 3
cp_obs:
        ld a, (ix+0)
        ld (ix+3), a
        ld a, (ix+1)
        ld (ix+4), a
        ld a, (ix+2)
        ld (ix+5), a
        ld de, 7
        add ix, de
        djnz cp_obs
        ret

;------------------------------------------------------------
; Графика
;------------------------------------------------------------

; HL = предсдвинутый спрайт (8 кадров по height*3 байта).
; B = высота. spr_x / spr_y / spr_w заданы. Прямая запись, без OR.
; IX не портится.
blit:
        ld (spr_ptr), hl
        ld a, b
        ld (spr_h), a
        call prep_span
        ret c
        ld hl, (spr_ptr)
        ld a, (spr_h)
        ld c, a
        add a, a
        add a, c
        ld c, a
        ld b, 0
        ld a, (shift_n)
        or a
        jr z, bl_aimed
bl_seek:
        add hl, bc
        dec a
        jr nz, bl_seek
bl_aimed:
        ld de, (scr_ptr)
        ld a, (spr_h)
        ld b, a
        ld a, (span_n)
        cp 3
        jp z, bl3
        ld a, (skip_n)
        or a
        jr nz, bl_left
        ld a, (span_n)
        dec a
        jr z, bl_r1
bl_r2:
        ld a, d
        and 7
        ld c, a
        ld a, 8
        sub c
        cp b
        jr c, bl2_fit
        ld a, b
bl2_fit:
        ld c, a
        ld a, b
        sub c
        ld b, a
bl2_row:
        ld a, (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (hl)
        ld (de), a
        inc hl
        inc hl
        dec e
        dec c
        jr z, bl2_end
        inc d
        jr bl2_row
bl2_end:
        ld a, b
        or a
        ret z
        inc d
        ld a, e
        add a, 32
        ld e, a
        jr c, bl_r2
        ld a, d
        sub 8
        ld d, a
        jr bl_r2
bl_r1:
        ld a, (hl)
        ld (de), a
        inc hl
        inc hl
        inc hl
        inc d
        ld a, d
        and 7
        jr z, bl_r1b
        djnz bl_r1
        ret
bl_r1b:
        ld a, e
        add a, 32
        ld e, a
        jr c, bl_r1dj
        ld a, d
        sub 8
        ld d, a
bl_r1dj:
        djnz bl_r1
        ret
bl_left:
        ld a, (skip_n)
        dec a
        jr z, bl_l2
bl_l1:
        inc hl
        inc hl
        ld a, (hl)
        ld (de), a
        inc hl
        inc d
        ld a, d
        and 7
        jr z, bl_l1b
        djnz bl_l1
        ret
bl_l1b:
        ld a, e
        add a, 32
        ld e, a
        jr c, bl_l1dj
        ld a, d
        sub 8
        ld d, a
bl_l1dj:
        djnz bl_l1
        ret
bl_l2:
        inc hl
        ld a, (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (hl)
        ld (de), a
        inc hl
        dec e
        inc d
        ld a, d
        and 7
        jr z, bl_l2b
        djnz bl_l2
        ret
bl_l2b:
        ld a, e
        add a, 32
        ld e, a
        jr c, bl_l2dj
        ld a, d
        sub 8
        ld d, a
bl_l2dj:
        djnz bl_l2
        ret
bl3:
        ld a, d
        and 7
        ld c, a
        ld a, 8
        sub c
        cp b
        jr c, bl3_fit
        ld a, b
bl3_fit:
        ld c, a
        ld a, b
        sub c
        ld b, a
bl3_row:
        ld a, (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (hl)
        ld (de), a
        inc hl
        dec e
        dec e
        dec c
        jr z, bl3_end
        inc d
        jr bl3_row
bl3_end:
        ld a, b
        or a
        ret z
        inc d
        ld a, e
        add a, 32
        ld e, a
        jr c, bl3
        ld a, d
        sub 8
        ld d, a
        jr bl3

; Стирает видимый кусок спрайта. spr_x, spr_y, spr_h заданы.
erase_sprite:
        call prep_span
        ret c
        ld a, (span_n)
        cp 3
        jp z, es3
        dec a
        jr z, es1
es2:
        ld a, d
        and 7
        ld c, a
        ld a, 8
        sub c
        cp b
        jr c, es2_fit
        ld a, b
es2_fit:
        ld c, a
        ld a, b
        sub c
        ld b, a
es2_row:
        xor a
        ld (de), a
        inc e
        ld (de), a
        dec e
        dec c
        jr z, es2_end
        inc d
        jr es2_row
es2_end:
        ld a, b
        or a
        ret z
        inc d
        ld a, e
        add a, 32
        ld e, a
        jr c, es2
        ld a, d
        sub 8
        ld d, a
        jr es2
es1:
        ld c, 0
        ld a, c
        ld (de), a
        inc d
        ld a, d
        and 7
        jr z, es1b
        djnz es1
        ret
es1b:
        ld a, e
        add a, 32
        ld e, a
        jr c, es1dj
        ld a, d
        sub 8
        ld d, a
es1dj:
        djnz es1
        ret
es3:
        ld a, d
        and 7
        ld c, a
        ld a, 8
        sub c
        cp b
        jr c, es3_fit
        ld a, b
es3_fit:
        ld c, a
        ld a, b
        sub c
        ld b, a
es3_row:
        xor a
        ld (de), a
        inc e
        ld (de), a
        inc e
        ld (de), a
        dec e
        dec e
        dec c
        jr z, es3_end
        inc d
        jr es3_row
es3_end:
        ld a, b
        or a
        ret z
        inc d
        ld a, e
        add a, 32
        ld e, a
        jr c, es3
        ld a, d
        sub 8
        ld d, a
        jr es3

; Колонка, сдвиг и видимый кусок шириной spr_w байт.
; CF = 1, если рисовать нечего. Иначе DE = экран, B = высота.
prep_span:
        ld hl, (spr_x)
        ld a, l
        and 7
        ld (shift_n), a
        call x_to_col
        xor a
        ld (skip_n), a
        ld a, (spr_w)
        ld (span_n), a
        bit 7, h
        jr nz, ps_neg
        ld a, h
        or a
        jr nz, ps_off
        ld a, l
        cp 32
        jr nc, ps_off
        ld c, a
        ld a, (spr_w)
        add a, c
        cp 33
        jr c, ps_addr
        ld a, 32
        sub c
        ld (span_n), a
        jr ps_addr
ps_neg:
        ld a, (spr_w)
        ld e, a
        ld a, 1
        sub e
        ld e, a
        ld d, $FF
        call signed_lt
        jr c, ps_off
        xor a
        sub l
        ld (skip_n), a
        ld c, a
        ld a, (spr_w)
        sub c
        ld (span_n), a
        ld hl, 0
ps_addr:
        ld a, l
        push af
        ld a, (spr_y)
        ld b, a
        pop af
        call pixadr
        ld (scr_ptr), de
        ld a, (spr_h)
        ld b, a
        or a
        ret
ps_off:
        scf
        ret

; HL = пиксельный X (знаковый) -> HL = номер байта.
x_to_col:
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ret

; B = Y (0..191), A = колонка (0..31) -> DE. Портит A и C.
pixadr:
        ld c, a
        ld a, b
        and 7
        ld d, a
        ld a, b
        and 192
        rrca
        rrca
        rrca
        or d
        ld d, a
        ld a, b
        and 56
        rlca
        rlca
        or c
        ld e, a
        ld a, d
        or 64
        ld d, a
        ret

; B = ряд символов, C = колонка -> DE.
char_addr:
        ld a, b
        add a, a
        add a, a
        add a, a
        ld b, a
        ld a, c
        call pixadr
        ret

; Печатает A. DE — верх знакоместа, после вызова сдвигается на колонку вправо.
print_char:
        push bc
        push de
        push hl
        sub 32
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, $3D00
        add hl, bc
        ld b, 8
pc_loop:
        ld a, (hl)
        ld (de), a
        inc hl
        inc d
        djnz pc_loop
        pop hl
        pop de
        pop bc
        inc e
        ret

print_str:
        ld a, (hl)
        or a
        ret z
        push hl
        call print_char
        pop hl
        inc hl
        jr print_str

;------------------------------------------------------------
; Старт и рестарт
;------------------------------------------------------------

init_game:
        xor a
        ld (hi_score), a
        ld (hi_score+1), a
        ld (state), a
        ld (frame), a
        ld (released), a
        ld (death_play), a
        ld (demo), a
        ld (ducking), a
        ld (demo_dead), a
        ld (idle_t), a
        ld (idle_t+1), a
        ld a, 1
        ld (can_start), a
        ld hl, hi_dig
        ld b, 5
ig_hi:
        ld (hl), 0
        inc hl
        djnz ig_hi
        call init_round
        ret

init_round:
        xor a
        ld (score), a
        ld (score+1), a
        ld (score_frac), a
        ld (dino_vy), a
        ld (night), a
        ld a, 2
        ld (speed), a
        ld a, DINO_Y0
        ld (dino_y), a
        xor a
        ld (ducking), a
        ld a, 50
        ld (spawn_t), a
        ld a, 1
        ld (first_spawn), a
        ld a, 1
        ld (need_cls), a
        ld (cloud_dirty), a
        ld (attr_dirty), a
        xor a
        ld (hud_ready), a
        ld (grav_phase), a
        ld (score_from), a
        ld (hi_from), a
        ld (hi_chime), a
        ld hl, score_dig
        ld b, 5
ir_dig:
        ld (hl), 0
        inc hl
        djnz ir_dig
        ld hl, DINO_X
        ld (old_dino_x), hl
        ld a, DINO_Y0
        ld (old_dino_y), a
        ld hl, obs
        ld b, 21
ir_clr:
        ld (hl), 0
        inc hl
        djnz ir_clr
        call init_clouds
        ld hl, pebble_init
        ld de, pebbles
        ld bc, 32
        ldir
        ret

;------------------------------------------------------------
; Данные
;------------------------------------------------------------

str_hi:
        defm "HI "
        defb 0
str_gap:
        defm "  "
        defb 0
str_jump:
        defm "Q, SPACE - JUMP"
        defb 0
str_duck:
        defm "A - DUCK"
        defb 0
str_start:
        defm "START - ANY KEY"
        defb 0
str_demo:
        defm "DEMO"
        defb 0
str_over:
        defm "GAME OVER"
        defb 0
str_hit:
        defm "HIT ANY KEY"
        defb 0
str_wide:
        defm "               "
        defb 0
str_copy:
        defb 127
        defm " 2026 Kukovnikov Bonifas"
        defb 0

pebble_init:
        db $00, $00, $08, $00, $00, $00, $00, $40
        db $00, $00, $00, $10, $00, $00, $04, $00
        db $00, $80, $00, $00, $00, $20, $00, $00
        db $02, $00, $00, $00, $00, $08, $00, $01

        include 'sprites.inc'

state:       db 0
frame:       db 0
released:    db 0
demo:        db 0
ducking:     db 0
can_start:   db 1
idle_t:      dw 0
demo_dead:   db 0
demo_want:   db 0
demo_block:  db 0
; Поздние окна прыжка: верх, низ. Скорость 2..7, типы 1..3.
jump_tbl:
        db 76, 62, 72, 62, 70, 62
        db 100, 46, 94, 52, 94, 46
        db 120, 48, 112, 56, 116, 48
        db 145, 50, 135, 60, 140, 50
        db 166, 52, 154, 64, 160, 52
        db 192, 52, 178, 66, 185, 52
death_play:  db 0
need_cls:    db 1
cloud_dirty: db 1
night:       db 0
border_col:  db 0
dino_y:      db 0
dino_vy:     db 0
grav_phase:  db 0
hud_ready:   db 0
hud_msg:     db $FF
speed:       db 2
score:       dw 0
score_frac:  db 0
score_dig:   ds 5
score_from:  db 0
hi_score:    dw 0
hi_dig:      ds 5
hi_from:     db 0
hi_chime:    db 0
attr_dirty:  db 1
saved_sp:    dw 0
spawn_t:     db 0
first_spawn: db 1
seed:        dw 12345
old_dino_x:  dw DINO_X
old_dino_y:  db DINO_Y0
cloud_self:  dw 0
cloud_try:   dw 0
cloud_max:   dw 0
cloud_nvis:  db 0
cloud_seed:  dw 54321
; Высоты не задевают счёт (ряд 0) и надписи (ряды 8 и 10).
cloud_ys:
        db 10, 26, 42, 54, 96
cloud_layouts:
        dw 18, 176, 330, 470
        dw 36, 210, 360, 520
        dw 10, 96, 200, 380
        dw 28, 130, 230, 420
        dw 6, 78, 156, 230
        dw 14, 64, 150, 228
clouds:      ds CLOUD_N*6
; 3 слота по 7 байт: x, тип, старый x, старый тип, шаг птицы.
obs:         ds 21
pebbles:     ds 32
spr_x:       dw 0
spr_y:       db 0
spr_h:       db 0
spr_w:       db 3
spr_ptr:     dw 0
shift_n:     db 0
skip_n:      db 0
span_n:      db 0
scr_ptr:     dw 0
row_y:       db 0
col_tmp:     dw 0
out0:        db 0
out1:        db 0
out2:        db 0
paint_or:    db 0
max_x:       dw 0
tmp_x:       dw 0
ax:          dw 0
aw:          db 0
ay:          db 0
ah:          db 0
bx:          dw 0
bw:          db 0
by:          db 0
bh:          db 0
