
	.include "note_table.h"
	.include "sound_data.h"
	.include "sound_defs.h"

	;; Exported symbols
	.export sound_init
	.export sound_disable
	.export	sound_load
	.export sound_play_frame

	.export sound_disable_flag
	.export stream_status

	.zeropage
	
	sound_ptr:		.res	2

	.segment "SRAM1"

;;; A flag that keeps track of whether or the sound engine is disabled or not.
sound_disable_flag:	.res	1
sound_temp1:		.res	1
sound_temp2:		.res	1

;;; A primitive counter used to time notes in this demo
sound_frame_counter:	.res	1

;;; Reserve 6 bytes, one for each stream
	
stream_curr_sound:	.res	6 ; Current song/fx loaded
;;; Status byte. Bit 0 (1: stream enabled, 0: stream disabled)
stream_status:		.res	6
stream_channel:		.res	6 ; What channel is this stream playing on?
stream_ptr_lo:		.res	6 ; Low byte of pointer to data stream
stream_ptr_hi:		.res	6 ; High byte of pointer to data stream
stream_vol_duty:	.res	6 ; Stream volume/duty settings
stream_note_lo:		.res	6 ; Low 8 bits of period for current note
stream_note_hi:		.res	6 ; High 3 bites of period for current note

;;;;;;;;;;;;;;;

	.code
	
sound_init:
	;; Enable Square 1, Square 2, Triangle and Noise channels
	lda	#$0f
	sta	$4015

	lda	#$00
	sta	sound_disable_flag ; Clear disable flag
	;; Later, if we have other variables we want to initialize, we will do
	;; that here.
	sta	sound_frame_counter

se_silence:	
	lda	#$30
	sta	$4000		; Set Square 1 volume to 0
	sta	$4004		; Set Square 2 volumne to 0
	sta	$400c		; Set Noice volume to 0
	lda	#$80
	sta	$4008		; Silence Triangle
	
	rts

sound_disable:
	lda	#$00
	sta	$4015		; Disable all channels
	lda	#$01
	sta	sound_disable_flag ; Set disable flag
	rts

;;; 
;;; sound_load will preprate the sound engine to play a song or sfx.
;;; Inputs:
;;; 	A: song/sfx number to play
;;; 
sound_load:
	sta	sound_temp1	; Save song number
	asl	a		; Multiply by 2. Index into a table of pointers.
	tay
	lda	song_headers, y	; Setup the pointer to our song header
	sta	sound_ptr
	lda	song_headers+1, y
	sta	sound_ptr+1

	ldy	#$00
	lda	(sound_ptr), y	; Read the first byte: # streams
	;; Store in a temp variable. We will use this as a loop counter: how
	;; many streams to read stream headers for
	sta	sound_temp2
	iny
@loop:
	lda	(sound_ptr), y	; Stream number
	tax			; Strem number acts as our variable index
	iny

	lda	(sound_ptr), y	; Status byte. 1=enable, 0=disable
	sta	stream_status, x
	;; If status byte is 0, stream disable, move pointer
	beq	@advance_pointer
	iny

	lda	(sound_ptr), y	; Channel number
	sta	stream_channel, x
	iny

	lda	(sound_ptr), y	; Initial duty and volume settings
	sta	stream_vol_duty, x
	iny

	;; Pointer to stream data. Little endian, so low byte first
	lda	(sound_ptr), y
	sta	stream_ptr_lo, x
	iny

	lda	(sound_ptr), y
	sta	stream_ptr_hi, x

@next_stream:
	iny

	lda	sound_temp1	; Song number
	sta	stream_curr_sound, x

	dec	sound_temp2	; Our loop counter
	bne	@loop
	
	rts

@advance_pointer:
    iny
    iny
    iny
    iny
    iny
    jmp @next_stream


	;; *** Change this to make the notes play faster or slower ***
	TEMPO = $0C
	
sound_play_frame:
	lda	sound_disable_flag
	bne	@done		; If disable flag is set, dont' advance a frame

	inc	sound_frame_counter
	lda	sound_frame_counter
	cmp	#TEMPO
	bne	@done		; Only take action once very TEMPO frames

	;; Silence all channels. se_set_apu will set volumen later for all
	;; channels that are enabled. The purpose of this subroutine call is
	;; to silence all channels that aren't used by any streams
	jsr	se_silence

	ldx	#$00
@loop:
	lda	stream_status, x
	and	#$01		; Check whether the stream is active
	beq	@endloop	; If the channel isn't active, skip it
	jsr	se_fetch_byte
	jsr	se_set_apu
@endloop:
	inx
	cpx	#$06
	bne	@loop

	;; Reset frame counter so we can start counting to TEMPO again.
	lda	#$00
	sta	sound_frame_counter
@done:
	rts

;;;
;;; se_fetch_byte reads one byte from the sound data stream and handles it
;;; Inputs:
;;; 	X: stream number
;;; 
se_fetch_byte:
	lda	stream_ptr_lo, x
	sta	sound_ptr
	lda	stream_ptr_hi, x
	sta	sound_ptr+1

	ldy	#$00
	lda	(sound_ptr), y
	bpl	@note		; If < #$80, it's a Note
	cmp	#$A0
	bcc	@note_length	; Else if < #$A0, it's a Note Length
@opcode:			; Else it's an opcode
	;; Do Opcode stuff
	cmp	#$ff
	bne	@end
	lda	stream_status, x ; If $FF, end of stream so disable it and silence
	and	#%11111110
	sta	stream_status, x ; Clear enable flag in status byte

	lda	stream_channel, x
	cmp	#TRIANGLE
	;; Triangle is silenced differenlty from squares and noise
	beq	@silence_tri
	lda	#$30		; Squaures and noise silenced witht #$30
	bne	@silence
@silence_tri:
	lda	#$80		; Triangle silenced with #$80
@silence:
	sta	stream_vol_duty, x ; Store silence value in the stream's volume
	jmp	@update_pointer	   ; Done
@note_length:
	;; Do Note Length stuff
	jmp	@update_pointer	; Note implemented yet
@note:
	;; Do Note stuff
	sty	sound_temp1	; Save our index into the data stream
	asl	a
	tay
	lda	note_table, y
	sta	stream_note_lo, x
	lda	note_table+1, y
	sta	stream_note_hi, x
	ldy	sound_temp1	; Restore data stream index
@update_pointer:
	iny
	tya
	clc
	adc	stream_ptr_lo, x
	sta	stream_ptr_lo, x
	bcc	@end
	inc	stream_ptr_hi, x
@end:
	rts

;;; 
;;; se_set_apu writes a stream's data to the APU ports
;;; Inputs:
;;; 	X: stream number
;;; 
se_set_apu:
	lda	stream_channel, x
	;; Multipley by 4 so our index will point to the right set of registers
	asl	a
	asl	a
	tay
	lda	stream_vol_duty, x
	sta	$4000, y
	lda	stream_note_lo, x
	sta	$4002, y
	lda	stream_note_hi, x
	sta	$4003, y

	lda	stream_channel, x
	cmp	#TRIANGLE
	bcs	@end		; If Triangle or Noise, skip this part
	;; Else set negate flag in sweep unit to allow low notes on Squares
	lda	#$08
	sta	$4001, y
@end:
	rts

;;; This is our poitner table. Each entry is a pointer to a song header
	.import song0_header
	.import song1_header
	.import song2_header
	.import song3_header
song_headers:
	.word	song0_header	; This is a silence song.
	.word	song1_header	; Evil, demented notes
	.word	song2_header	; A sound effect. Try playing it over other songs
	.word	song3_header	; A little chord progression
