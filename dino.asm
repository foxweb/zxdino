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
        ld a, (speed)
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
        ld de, 6
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

scroll_pebbles:
        ld a, (speed)
        ld b, a
spb_loop:
        push bc
        call scroll_one
        pop bc
        djnz spb_loop
        ret

scroll_one:
        call rnd
        and 15
        jr nz, so_clear
        scf
        jr so_shift
so_clear:
        or a
so_shift:
        ld hl, pebbles+31
        ld b, 32
so_loop:
        rl (hl)
        dec hl
        djnz so_loop
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
        ld de, 6
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
        ld de, 6
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
        pop af
        jr us_loop
us_store:
        ld (score_frac), a
        ret

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
        call apply_colors
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
        ld de, 6
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

; xorshift 16. Результат в A, seed обновлён.
rnd:
        push bc
        push de
        push hl
        ld hl, (seed)
        ld d, h
        ld e, l
        ld b, 7
rnd_s7:
        add hl, hl
        djnz rnd_s7
        ld a, h
        xor d
        ld h, a
        ld a, l
        xor e
        ld l, a
        ld d, h
        ld e, l
        ld b, 9
rnd_s9:
        srl d
        rr e
        djnz rnd_s9
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
        pop hl
        pop de
        pop bc
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
        call apply_colors
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

apply_colors:
        ld a, (night)
        or a
        ld a, $47
        jr z, ac_fill
        ld a, $78
ac_fill:
        ld hl, $5800
        ld de, $5801
        ld bc, $02FF
        ld (hl), a
        ldir
        ld a, (night)
        or a
        ld a, 0
        jr z, ac_border
        ld a, 7
ac_border:
        ld (border_col), a
        out ($FE), a
        ret

erase_dino:
        ld hl, (old_dino_x)
        ld (spr_x), hl
        ld a, (old_dino_y)
        ld (spr_y), a
        ld a, DINO_H
        ld (spr_h), a
        call erase_sprite
        ret

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
        ld de, 6
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
        call erase_sprite
        ret

; A = тип. Ставит spr_y и spr_h. Всегда стираем 3 байта в ширину.
metrics_from_type:
        cp 2
        jr z, mt_tall
        cp 4
        jr z, mt_blow
        cp 5
        jr z, mt_bhigh
        cp 1
        jr z, mt_short
        cp 3
        jr z, mt_short
        ld a, BIRD_LOW_Y
        ld (spr_y), a
        ld a, BIRD_H
        ld (spr_h), a
        ret
mt_short:
        ld a, GROUND_Y-CAC_S_H
        ld (spr_y), a
        ld a, CAC_S_H
        ld (spr_h), a
        ret
mt_tall:
        ld a, GROUND_Y-CAC_T_H
        ld (spr_y), a
        ld a, CAC_T_H
        ld (spr_h), a
        ret
mt_blow:
        ld a, BIRD_LOW_Y
        ld (spr_y), a
        ld a, BIRD_H
        ld (spr_h), a
        ret
mt_bhigh:
        ld a, BIRD_HIGH_Y
        ld (spr_y), a
        ld a, BIRD_H
        ld (spr_h), a
        ret

draw_ground:
        ld b, GROUND_Y
        call fill_row_ff
        ld b, GROUND_Y+1
        call fill_row_ff
        ld b, GROUND_Y+3
        ld a, 0
        call pixadr
        ld hl, pebbles
        ld b, 32
dg_p:
        ld a, (hl)
        ld (de), a
        inc hl
        inc e
        djnz dg_p
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
        ld hl, cloud
        ld b, CLOUD_H
        ld c, 2
        call blit
        ret

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
        ld de, 6
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
        ret
sf_tall:
        ld hl, cac_tall
        ld a, GROUND_Y-CAC_T_H
        ld (spr_y), a
        ld b, CAC_T_H
        ld c, 1
        ret
sf_wide:
        ld hl, cac_wide
        ld a, GROUND_Y-CAC_S_H
        ld (spr_y), a
        ld b, CAC_S_H
        ld c, 2
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
        ret

draw_dino:
        ld hl, DINO_X
        ld (spr_x), hl
        ld a, (dino_y)
        ld (spr_y), a
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
        ld b, DINO_H
        ld c, 2
        call blit
        ret

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
        ld hl, $FFFF
        ld (hud_score), hl
        ld (hud_hi), hl
        ld a, $FF
        ld (hud_msg), a
hud_nums:
        ld hl, (hi_score)
        ld de, (hud_hi)
        or a
        sbc hl, de
        jr z, hud_no_hi
        ld hl, (hi_score)
        ld (hud_hi), hl
        ld b, 0
        ld c, 17
        call char_addr
        ld hl, (hi_score)
        call print_hl5
hud_no_hi:
        ld hl, (score)
        ld de, (hud_score)
        or a
        sbc hl, de
        jr z, hud_no_sc
        ld hl, (score)
        ld (hud_score), hl
        ld b, 0
        ld c, 24
        call char_addr
        ld hl, (score)
        call print_hl5
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
        ld de, 6
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
; B = высота. spr_x / spr_y заданы. Пиксели накладываются через OR.
; IX не портится.
blit:
        ld (spr_ptr), hl
        ld a, b
        ld (spr_h), a
        call prep_span
        ret c
        ld hl, (spr_ptr)
        ld a, (shift_n)
        or a
        jr z, bl_aimed
        ld d, a
bl_seek:
        ld a, (spr_h)
        ld c, a
        add a, a
        add a, c
        ld c, a
        ld b, 0
        add hl, bc
        dec d
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
        inc d
        ld a, d
        and 7
        jr z, bl_r2b
        djnz bl_r2
        ret
bl_r2b:
        ld a, e
        add a, 32
        ld e, a
        jr c, bl_r2dj
        ld a, d
        sub 8
        ld d, a
bl_r2dj:
        djnz bl_r2
        ret
bl_r1:
        ld a, (de)
        or (hl)
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
        ld a, (de)
        or (hl)
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
        ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (de)
        or (hl)
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
        ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        inc e
        ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        dec e
        dec e
        inc d
        ld a, d
        and 7
        jr z, bl3b
        djnz bl3
        ret
bl3b:
        ld a, e
        add a, 32
        ld e, a
        jr c, bl3dj
        ld a, d
        sub 8
        ld d, a
bl3dj:
        djnz bl3
        ret

; Стирает видимый кусок спрайта. spr_x, spr_y, spr_h заданы.
erase_sprite:
        call prep_span
        ret c
        ld c, 0
        ld a, (span_n)
        cp 3
        jr z, es3
        dec a
        jr z, es1
es2:
        ld a, c
        ld (de), a
        inc e
        ld (de), a
        dec e
        inc d
        ld a, d
        and 7
        jr z, es2b
        djnz es2
        ret
es2b:
        ld a, e
        add a, 32
        ld e, a
        jr c, es2dj
        ld a, d
        sub 8
        ld d, a
es2dj:
        djnz es2
        ret
es1:
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
        ld a, c
        ld (de), a
        inc e
        ld (de), a
        inc e
        ld (de), a
        dec e
        dec e
        inc d
        ld a, d
        and 7
        jr z, es3b
        djnz es3
        ret
es3b:
        ld a, e
        add a, 32
        ld e, a
        jr c, es3dj
        ld a, d
        sub 8
        ld d, a
es3dj:
        djnz es3
        ret

; Считает колонку, сдвиг и видимый кусок из 3 байт.
; CF = 1, если рисовать нечего. Иначе DE = экран, B = высота.
prep_span:
        ld hl, (spr_x)
        ld a, l
        and 7
        ld (shift_n), a
        call x_to_col
        xor a
        ld (skip_n), a
        ld a, 3
        ld (span_n), a
        bit 7, h
        jr nz, ps_neg
        ld a, h
        or a
        jr nz, ps_off
        ld a, l
        cp 32
        jr nc, ps_off
        cp 30
        jr c, ps_addr
        ld a, 32
        sub l
        ld (span_n), a
        jr ps_addr
ps_neg:
        ld de, -2
        call signed_lt
        jr c, ps_off
        xor a
        sub l
        ld (skip_n), a
        ld c, a
        ld a, 3
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

; Один пиксельный шаг вниз. Портит A.
down_de:
        inc d
        ld a, d
        and 7
        ret nz
        ld a, e
        add a, 32
        ld e, a
        ret c
        ld a, d
        sub 8
        ld d, a
        ret

; Печатает A, DE — верх символа. DE сдвигается на колонку вправо.
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
        call down_de
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

; Печатает HL как 5 десятичных цифр.
print_hl5:
        ld bc, 10000
        call pr_digit
        ld bc, 1000
        call pr_digit
        ld bc, 100
        call pr_digit
        ld bc, 10
        call pr_digit
        ld bc, 1
pr_digit:
        ld a, '0'-1
pd_loop:
        inc a
        or a
        sbc hl, bc
        jr nc, pd_loop
        add hl, bc
        push bc
        call print_char
        pop bc
        ret

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
        xor a
        ld (hud_ready), a
        ld (grav_phase), a
        ld hl, DINO_X
        ld (old_dino_x), hl
        ld a, DINO_Y0
        ld (old_dino_y), a
        ld hl, obs
        ld b, 18
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
hud_score:   dw $FFFF
hud_hi:      dw $FFFF
speed:       db 2
score:       dw 0
score_frac:  db 0
hi_score:    dw 0
spawn_t:     db 0
first_spawn: db 1
seed:        dw 12345
old_dino_x:  dw DINO_X
old_dino_y:  db DINO_Y0
cloud1_x:    dw 30
cloud1_old:  dw 30
cloud2_x:    dw 170
cloud2_old:  dw 170
obs:         ds 18
pebbles:     ds 32
spr_x:       dw 0
spr_y:       db 0
spr_h:       db 0
spr_w:       db 0
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
