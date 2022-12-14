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
; Try to rank these bits from most common to least common, as the FX processing loop goes from MSB
; to LSB, stopping as soon as no more bits are set.
; (For example, LAST should be the first one in the list, ironically.)
DEF VALFX_STEP_LAST_B    equ 0
DEF VALFX_STEP_PAN_B     equ 1
DEF VALFX_STEP_SPEED_B   equ 2
DEF VALFX_STEP_CH2NOTE_B equ 3
DEF VALFX_STEP_CH2DUTY_B equ 4
DEF VALFX_STEP_CH4FREQ_B equ 5
DEF VALFX_STEP_CH2VOL_B  equ 6
DEF VALFX_STEP_CH4VOL_B  equ 7

SECTION "VAL-FX RAM Variables",WRAM0
_valfx_is_playing:: ; Must be set to 0 before first call to `valfx_play` or `valfx_update`.
valfx:
.header      db ; The current SFX's header. If 0, no SFX is currently playing.
.speed       db ; How many no-op calls to insert between SFX "steps".
.delay       db ; How many calls remain until the next SFX "step".
.pointer     dw ; Where the next SFX byte should be read from.
.shadow_nr24 db ; Keeps the lower 3 bits of NR24, to avoid resetting them when restarting the channel.
.sgb         db ; Set to $FF (although VALFX_HDR_SGB_B is sufficient) to enable SGB support, 0 otherwise.

SECTION "VAL-FX Code",ROM0

valfx_identifier:
    pushc
    newcharmap valfx_ascii ; Ensure ASCII
    db "VAL-FX BY CVB 2022"
    popc
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


; Parameters:
; HL: Address for SFX start
valfx_play:
    ; Compare priorities:
    ; for the SFX to start playing, its priority must be no greater than the current one's.
    ld a, [hl]
    and VALFX_HDR_PRIO_F
    ld c, a
    ld a, [valfx.header]
    and VALFX_HDR_PRIO_F
    cp c
    ret c ; Bail if cur - new < 0, i.e. cur < new
    ; Here, new <= cur

    ; Prevent SFX playback while we are modifying memory (race condition).
    xor a
    ld [valfx.header], a

    ld a, [hl+]
    ld c, a
    ld a, [valfx.sgb]
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
    ; Increase pointer by one and store to valfx.pointer
    ld a, h
    ld [valfx.pointer], a
    ld a, l
    ld [valfx.pointer+1], a

    ; Reset mute channels

    bit VALFX_HDR_CH2_B, c
    jr z, .skipch2
    ; Mute ch2
    xor a
    ldh [rNR22], a
.skipch2

    bit VALFX_HDR_CH4_B, c
    jr z, .skipch4
    ; Mute ch4
    xor a
    ldh [rNR42], a
.skipch4

    ld hl, valfx.delay
    xor a
    ld [hld], a
    assert valfx.delay - 1 == valfx.speed
    ld [hld], a
    assert valfx.speed - 1 == valfx.header
    ; Finally, enable SFX playback by writing the header.
    ld [hl], c
    ret

valfx_update:
    ld a, [valfx.header]
    and a
    ret z

    ld a, [valfx.delay]
    and a
    jr z, .iszero
    dec a
    ld [valfx.delay], a
    ret
.iszero

    ld hl, valfx.speed
    ld a, [hli]
    assert valfx.speed + 1 == valfx.delay
    ld [hli], a

    assert valfx.delay + 1 == valfx.pointer
    ld a, [hli]
    ld h, [hl]
    ld l, a

    ; Read the step's header byte.
    ld a, [hli]
    ld c, a
    ld de, .jumpTable - 2
.fxLoop
    ; Skip to next pointer.
    inc de
    inc de
    sla c
    jr c, .runFX ; We may loop one extra time after the last
    jr nz, .fxLoop ; Keep looping if there are remaining bits.

    ld a, l
    ld [valfx.pointer], a
    ld a, h
    ld [valfx.pointer + 1], a
    ret

.runFX
    push de
    ret ; jp de

.jumpTable
    rsset 8
MACRO valfx_fx
    rsset _RS - 1
    assert \1 == _RS, STRFMT("\1 (%d) != {d:_RS}", \1)
    IF _RS != 0
        jr \2
    ELSE
        assert @ == \2 ; The last function is inline
    ENDC
ENDM
    valfx_fx VALFX_STEP_CH4VOL_B,  .set_ch4_vol
    valfx_fx VALFX_STEP_CH2VOL_B,  .set_ch2_vol
    valfx_fx VALFX_STEP_CH4FREQ_B, .set_ch4_freq
    valfx_fx VALFX_STEP_CH2DUTY_B, .set_ch2_duty
    valfx_fx VALFX_STEP_CH2NOTE_B, .set_ch2_note
    valfx_fx VALFX_STEP_SPEED_B,   .set_speed
    valfx_fx VALFX_STEP_PAN_B,     .set_pan
    valfx_fx VALFX_STEP_LAST_B,    .stop

    ; These FX functions can read bytes from the SFX data from hl (and modify it appropriately),
    ; but MUST preserve c (which contains the step header being iterated on).

.stop
    ld a, $FF ; TODO: maybe we're a bit overreaching here
    ldh [rNR51], a

    ld a, [valfx.header]
    ld b, a
    ; Disable playback.
    xor a
    ld [valfx.header], a
    ; Unmute the music channels that we use.
    bit 5, b
    jr nz, .skipch2
    ; Mute ch2
    ; a = 0
    ldh [rNR22], a
.skipch2

    bit 4, b
    jr nz, .fxLoop
    ; Mute ch4
    xor a
    ldh [rNR42], a
    jr .fxLoop

.set_speed
    ld a, [hli]
    ld [valfx.speed], a
    ld [valfx.delay], a
    jr .fxLoop

.set_pan
    ld a, [hli]
    ldh [rNR51], a
    jr .fxLoop

.set_ch2_duty
    ld a, [hli]
    ldh [rNR21], a
    jr .fxLoop

.set_ch2_note
    ld a, [hli]
    add a, LOW(valfx_note_table)
    ld e, a
    adc a, HIGH(valfx_note_table)
    sub e
    ld d, a
    ld a, [de]
    ldh [rNR23], a
    inc de
    ld a, [de]
    ld [valfx.shadow_nr24], a
    ldh [rNR24], a
    jr .fxLoop

.set_ch4_freq
    ld a, [hli]
    ldh [rNR43], a
    jr .fxLoop

.set_ch2_vol
    ld a, [hli]
    ldh [rNR22], a
    ld a, [valfx.shadow_nr24]
    set 7, a ; Trigger bit
    ldh [rNR24], a
    jr .fxLoop

.set_ch4_vol
    ld a, [hli]
    ldh [rNR42], a
    ld a, $80 ; Trigger bit
    ldh [rNR44], a
    jr .fxLoop
