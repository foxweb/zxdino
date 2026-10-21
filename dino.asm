; ZX Spectrum 48K — «динозаврик» в духе офлайн-игры Chrome.
; Управление: SPACE или Q — прыжок. После столкновения отпустите клавишу и нажмите снова.
; Точка входа: $8000. Сборка: python3 build.py

        org $8000

STATE_WAIT:  equ 0
STATE_RUN:   equ 1
STATE_DEAD:  equ 2

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
CLOUD1_Y:    equ 20
CLOUD2_Y:    equ 44
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
        call update_run
        ret

update_wait:
        call read_jump
        ret nz
        ld a, STATE_RUN
        ld (state), a
        ret

update_dead:
        call read_jump
        jr z, dead_held
        ld a, 1
        ld (released), a
        ret
dead_held:
        ld a, (released)
        or a
        ret z
        xor a
        ld (released), a
        call init_round
        ld a, STATE_RUN
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

update_dino:
        ld a, (dino_y)
        cp DINO_Y0
        jr c, dino_air
        ld a, DINO_Y0
        ld (dino_y), a
        xor a
        ld (dino_vy), a
        call read_jump
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

update_clouds:
        ld hl, (cloud1_x)
        dec hl
        ld de, -40
        call signed_lt
        jr nc, uc1_keep
        ld hl, 280
uc1_keep:
        ld (cloud1_x), hl
        ld hl, (cloud2_x)
        dec hl
        ld de, -40
        call signed_lt
        jr nc, uc2_keep
        ld hl, 300
uc2_keep:
        ld (cloud2_x), hl
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
        jp z, sp_sh5
        jp sp_sh4

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
        cp 3
        jr c, usp_ok
        ld a, 3
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
        ld a, (dino_y)
        add a, 6
        ld (ay), a
        ld a, 10
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
        ld a, (state)
        cp STATE_RUN
        jr nz, ec_static
        call update_clouds
        jp paint_clouds
ec_static:
        ld a, (cloud_dirty)
        or a
        ret z
        jp paint_clouds

paint_clouds:
        call erase_clouds
        call draw_clouds
        ld hl, (cloud1_x)
        ld (cloud1_old), hl
        ld hl, (cloud2_x)
        ld (cloud2_old), hl
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
        ld hl, (cloud1_old)
        ld a, CLOUD1_Y
        call erase_cloud
        ld hl, (cloud2_old)
        ld a, CLOUD2_Y
        call erase_cloud
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
        ld hl, (cloud1_x)
        ld a, CLOUD1_Y
        call draw_cloud
        ld hl, (cloud2_x)
        ld a, CLOUD2_Y
        call draw_cloud
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
        jr z, hud_phase_ok
        ld b, a
        ld a, (frame)
        and 16
        or b
        jr hud_phase
hud_phase_ok:
        ld a, STATE_RUN
hud_phase:
        ld hl, hud_msg
        cp (hl)
        ret z
        ld (hl), a
        ld b, 8
        ld c, 10
        call char_addr
        ld hl, str_blank
        ld a, (state)
        cp STATE_WAIT
        jr nz, hud_l1b
        ld a, (frame)
        and 16
        jr nz, hud_l1_print
        ld hl, str_press
        jr hud_l1_print
hud_l1b:
        cp STATE_DEAD
        jr nz, hud_l1_print
        ld hl, str_over
hud_l1_print:
        call print_str
        ld b, 10
        ld c, 10
        call char_addr
        ld hl, str_blank
        ld a, (state)
        cp STATE_DEAD
        jr nz, hud_l2_print
        ld a, (frame)
        and 16
        jr nz, hud_l2_print
        ld hl, str_again
hud_l2_print:
        call print_str
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
        ld hl, (cloud1_x)
        ld (cloud1_old), hl
        ld hl, (cloud2_x)
        ld (cloud2_old), hl
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
        ld hl, 30
        ld (cloud1_x), hl
        ld (cloud1_old), hl
        ld hl, 170
        ld (cloud2_x), hl
        ld (cloud2_old), hl
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
str_press:
        defm "PRESS SPACE"
        defb 0
str_over:
        defm " GAME OVER "
        defb 0
str_again:
        defm " HIT SPACE "
        defb 0
str_blank:
        defm "           "
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
cloud1_x:    dw 30
cloud1_old:  dw 30
cloud2_x:    dw 170
cloud2_old:  dw 170
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
