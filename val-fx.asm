;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  VAL-FX BT VALEN  ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;

INCLUDE "hardware.inc"

/*

TODO:
    - SGB Support (Wrapper code done, just gotta add the sgb transfer itself)

HEADER FORMAT
00000000
||||++++- Priority
|||+----- CH4 used flag
||+------ CH2 used flag
|+------- SGB data packet flag

if SGB data packet, 5 bytes for the SGB transfer are stored here

STEP HEADER FORMAT:
00000000
||||||||
|||||||+- Kill step flag (End sfx after step)
||||||+-- Set CH4 Vol flag (vol << 4)
|||||+--- Set CH2 Vol flag (vol << 4)
||||+---- Set CH4 Freq flag (bare freq)
|||+----- Set CH2 Note flag (note * 2)
||+------ Set CH2 Duty flag (duty << 6)
|+------- Set panning flag (NR51)
+-------- Set speed flag (Speed - 1)

*/

SECTION "VAL-FX RAM Variables",WRAM0
valfx_ram:
valfx_is_play: db
valfx_curlen: db
valfx_laslen: db
valfx_point: dw
valfx_header: db
valfx_step_header: db
valfx_shadow_nr24: db
valfx_sgb: db
valfx_ram_end:

SECTION "VAL-FX Code",ROM0

valfx_identifier:
    ; "VAL-FX BY CVB 2022"
    db 86, 65, 76, 45, 70, 88, 32, 66, 89, 32, 67, 86, 66, 32, 50, 48, 50, 50
valfx_note_table:
    dw 44
    dw 156
    dw 262
    dw 363
    dw 457
    dw 547
    dw 631
    dw 710
    dw 786
    dw 854
    dw 923
    dw 986
    dw 1046
    dw 1102
    dw 1155
    dw 1205
    dw 1253
    dw 1297
    dw 1339
    dw 1379
    dw 1417
    dw 1452
    dw 1486
    dw 1517
    dw 1546
    dw 1575
    dw 1602
    dw 1627
    dw 1650
    dw 1673
    dw 1694
    dw 1714
    dw 1732
    dw 1750
    dw 1767
    dw 1783
    dw 1798
    dw 1812
    dw 1825
    dw 1837
    dw 1849
    dw 1860
    dw 1871
    dw 1881
    dw 1890
    dw 1899
    dw 1907
    dw 1915
    dw 1923
    dw 1930
    dw 1936
    dw 1943
    dw 1949
    dw 1954
    dw 1959
    dw 1964
    dw 1969
    dw 1974
    dw 1978
    dw 1982
    dw 1985
    dw 1988
    dw 1992
    dw 1995
    dw 1998
    dw 2001
    dw 2004
    dw 2006
    dw 2009
    dw 2011
    dw 2013
    dw 2015

valfx_init:
    ld hl, valfx_ram
    ld c, (valfx_ram_end - valfx_ram)
    xor a
.clear
    ld [hli], a
    dec c
    jr nz, .clear
    ret


; Parameters:
; HL: Address for SFX start
valfx_play:
    ; Compare priority
    ld a, [hl]
    and $f
    ld c, a
    ld a, [valfx_step_header]
    and $f
    cp c
    ret c

    ; Stop SFX
    xor a
    ld [valfx_is_play], a

    ld a, [hl+]
    ld [valfx_header], a
    ld c, a
    ld a, [valfx_sgb]
    and c
    jr z, .notsgb
    ; Do SGB Stuff IDK
    ret
.notsgb

    ; C still has the header, thus we check that
    bit 6, c
    jr z, .notsgbdata
    ld de, $5
    add hl, de
.notsgbdata

    ; Load data from header
    ; Increase pointer by one and store to valfx_point
    ld a, h
    ld [valfx_point], a
    ld a, l
    ld [valfx_point+1], a

    ; Reset mute channels

    ; C still has the header, so we load it again
    ld a, c
    push af ; Store it for later
    bit 5, a
    jr z, .skipch2
    ; Mute ch2
    xor a
    ldh [rNR22], a
    set 7, a
    ldh [rNR24], a
.skipch2
    pop af
    bit 4, a
    jr z, .skipch4
    ; Mute ch4
    xor a
    ldh [rNR42], a
    set 7, a
    ldh [rNR44], a
.skipch4
    ld hl, valfx_is_play
    ld a, $FF
    ld [hl+], a
    xor a
    ld [hl+], a
    ld [hl], a
    ret

valfx_update:
    ld a, [valfx_is_play]
    and a
    ret z

    ld a, [valfx_curlen]
    and a
    jr z, .iszero
    dec a
    ld [valfx_curlen], a
    ret
.iszero

    ld a, [valfx_laslen]
    ld [valfx_curlen], a

    call .get_next_value
    ld [valfx_step_header], a

    ld c, %10000000 ; Start of the flag check, start from left to right
    ld hl, .jump
.loop
    ld a, [valfx_step_header]
    and c
    ld a, [hl+]
    jr z, .notflag
    push hl
    ld h, [hl]
    ld l, a
    jp hl
.return
    pop hl
.notflag
    inc hl
    srl c
    jr nc, .loop
    ret

; Returns next value in A
; Modifies: H, L, A, F
.get_next_value
    ld hl, valfx_point
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    push af
    ld a, h
    ld [valfx_point], a
    ld a, l
    ld [valfx_point+1], a
    pop af
    ret

.jump
    dw .set_speed
    dw .set_pan
    dw .set_duty
    dw .set_note
    dw .set_freq
    dw .set_ch2_vol
    dw .set_ch4_vol
    dw .kill

.set_speed
    call .get_next_value
    ld [valfx_laslen], a
    ld [valfx_curlen], a
    jp .return

.set_pan
    call .get_next_value
    ldh [rNR50], a
    jp .return

.set_duty
    call .get_next_value
    ldh [rNR21], a
    jp .return

.set_note
    call .get_next_value
    ld hl, valfx_note_table
    xor d
    ld e, a
    add hl, de
    ld a, [hl+]
    ldh [rNR23], a
    ld a, [hl]
    ld [valfx_shadow_nr24], a
    ldh [rNR24], a
    jp .return

.set_freq
    call .get_next_value
    ldh [rNR43], a
    jp .return

.set_ch2_vol
    call .get_next_value
    ldh [rNR22], a
    ld a, [valfx_shadow_nr24]
    set 7, a ; Trigger bit
    ldh [rNR24], a
    jp .return

.set_ch4_vol
    call .get_next_value
    ldh [rNR42], a
    ld a, $80 ; Trigger bit
    ldh [rNR44], a
    jp .return

.kill
    xor a
    ld [valfx_is_play], a
    ld a, $FF
    ldh [rNR51], a
    ; Unmute music channels
    ld a, [valfx_step_header]
    push af
    bit 5, a
    jr nz, .skipch2
    ; Mute ch2
    xor a
    ldh [rNR22], a
    set 7, a
    ldh [rNR24], a
.skipch2
    pop af
    bit 4, a
    jr nz, .skipch4
    ; Mute ch4
    xor a
    ldh [rNR42], a
    set 7, a
    ldh [rNR44], a
.skipch4
    jp .return
