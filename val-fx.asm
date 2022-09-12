;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  VAL-FX BY VALEN  ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;

INCLUDE "hardware.inc"

/*

TODO:
    - SGB Support (Wrapper code done, just gotta add the sgb transfer itself)

*/

; Header fields
rsreset
DEF VALFX_HDR_PRIO_F equ %0000_1111
DEF VALFX_HDR_CH4_B equ 4 ; Does this SFX use CH4?
DEF VALFX_HDR_CH2_B equ 5 ; Does this SFX use CH2?
DEF VALFX_HDR_SGB_B equ 6 ; Does this SFX include SGB packet data?

; Step header fields
DEF VALFX_STEP_PAN_B     equ 0
DEF VALFX_STEP_CH4VOL_B  equ 1
DEF VALFX_STEP_CH2VOL_B  equ 2
DEF VALFX_STEP_CH4FREQ_B equ 3
DEF VALFX_STEP_CH2NOTE_B equ 4
DEF VALFX_STEP_CH2DUTY_B equ 5
DEF VALFX_STEP_SPEED_B   equ 6
DEF VALFX_STEP_LAST_B    equ 7

SECTION "VAL-FX RAM Variables",WRAM0
valfx_ram:
.is_playing  db ; 0 disables SFX playback.
.delay       db ; How many calls remain until the next SFX "step".
.speed       db ; How many no-op calls to insert between SFX "steps".
.pointer     dw ; Where the next SFX byte should be read from.
.step_header db ; The current "step"'s header byte.
.shadow_nr24 db ; Keeps the lower 3 bits of NR24, to avoid resetting them when restarting the channel.
.sgb         db ; Set to $FF (although VALFX_HDR_SGB_B is sufficient) to enable SGB support, 0 otherwise.
.end

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
    ld c, (valfx_ram.end - valfx_ram)
    xor a
.clear
    ld [hli], a
    dec c
    jr nz, .clear
    ret


; Parameters:
; HL: Address for SFX start
valfx_play:
    ; Compare priorities:
    ; for the SFX to start playing, its priority must be no greater than the current one's.
    ld a, [hl]
    and VALFX_HDR_PRIO_F
    ld c, a
    ld a, [valfx_ram.step_header]
    and VALFX_HDR_PRIO_F
    cp c
    ret c ; Bail if cur - new < 0, i.e. cur < new
    ; Here, new <= cur

    ; Prevent SFX playback while we are modifying memory (race condition).
    xor a
    ld [valfx_ram.is_playing], a

    ld a, [hl+]
    ld c, a
    ld a, [valfx_ram.sgb]
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
    ; Increase pointer by one and store to valfx_ram.pointer
    ld a, h
    ld [valfx_ram.pointer], a
    ld a, l
    ld [valfx_ram.pointer+1], a

    ; Reset mute channels

    bit VALFX_HDR_CH2_B, c
    jr z, .skipch2
    ; Mute ch2
    xor a
    ldh [rNR22], a
    set 7, a
    ldh [rNR24], a
.skipch2

    bit VALFX_HDR_CH4_B, c
    jr z, .skipch4
    ; Mute ch4
    xor a
    ldh [rNR42], a
    ld a, AUDHIGH_LENGTH_ON
    ldh [rNR44], a
.skipch4

    ld hl, valfx_ram.speed
    xor a
    ld [hld], a
    assert valfx_ram.speed - 1 == valfx_ram.delay
    ld [hld], a
    assert valfx_ram.delay - 1 == valfx_ram.is_playing
    ld [hl], 1
    ret

valfx_update:
    ld a, [valfx_ram.is_playing]
    and a
    ret z

    ld a, [valfx_ram.delay]
    and a
    jr z, .iszero
    dec a
    ld [valfx_ram.delay], a
    ret
.iszero

    ld a, [valfx_ram.speed]
    ld [valfx_ram.delay], a

    call .get_next_value
    ld [valfx_ram.step_header], a

    ld c, %10000000 ; Which of the flags we are processing
    ld hl, .jump
.loop
    ld a, [valfx_ram.step_header]
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
    ld hl, valfx_ram.pointer
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    push af
    ld a, h
    ld [valfx_ram.pointer], a
    ld a, l
    ld [valfx_ram.pointer+1], a
    pop af
    ret

.jump
    rsset 8
MACRO valfx_fx
    rsset _RS - 1
    dw \2
    assert \1 == _RS
ENDM
    valfx_fx VALFX_STEP_LAST_B,    .kill
    valfx_fx VALFX_STEP_SPEED_B,   .set_speed
    valfx_fx VALFX_STEP_CH2DUTY_B, .set_duty
    valfx_fx VALFX_STEP_CH2NOTE_B, .set_note
    valfx_fx VALFX_STEP_CH4FREQ_B, .set_freq
    valfx_fx VALFX_STEP_CH2VOL_B,  .set_ch2_vol
    valfx_fx VALFX_STEP_CH4VOL_B,  .set_ch4_vol
    valfx_fx VALFX_STEP_PAN_B,     .set_pan

.set_speed
    call .get_next_value
    ld [valfx_ram.speed], a
    ld [valfx_ram.delay], a
    jp .return

.set_pan
    call .get_next_value
    ldh [rNR51], a
    jp .return

.set_duty
    call .get_next_value
    ldh [rNR21], a
    jp .return

.set_note
    call .get_next_value
    ld hl, valfx_note_table
    ld d, 0
    ld e, a
    add hl, de
    ld a, [hl+]
    ldh [rNR23], a
    ld a, [hl]
    ld [valfx_ram.shadow_nr24], a
    ldh [rNR24], a
    jp .return

.set_freq
    call .get_next_value
    ldh [rNR43], a
    jp .return

.set_ch2_vol
    call .get_next_value
    ldh [rNR22], a
    ld a, [valfx_ram.shadow_nr24]
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
    ld [valfx_ram.is_playing], a
    ld a, $FF
    ldh [rNR51], a
    ; Unmute music channels
    ld a, [valfx_ram.step_header]
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
