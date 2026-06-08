; microsound.asm
	LIST	p=16F628a	;tell assembler what chip we are using
	include "P16F628a.inc"	;include the defaults for the chip
	__config 0x3D18			;sets the configuration settings (oscillator type etc.)

;/***************************************************
; Jump to Main Loop
;
;***************************************************/
    org 0x0
    goto   startupcode       ; plenty of room; won't run into our ISR code.
;/***************************************************
;   ContextSave:
;   Saves important registers before running our interrupt.
;  (cool code taken from http://www.piclist.com/techref/microchip/ints16Fintro-wcw.htm)
;
;***************************************************/
    org 0x4
ContextSave
    movwf          temp_w      ;save w in temp.  movwf does not change STATUS
                              ;; NOTE However, that temp_w must exist in all RAM banks.
    swapf          STATUS,w    ;put unchanged STATUS in w with nibbles reversed.
    clrf           STATUS      ;now use RAM page 0
    movwf          temp_s       ;save STATUS in temp_s
    movf           PCLATH,W     ; save PCLATH as well
    movwf          temp_pclath
    clrf           PCLATH       ; now on code page 0 for sure too.
    ;movf		   FSR
	;movwf		   temp_fsr	   ;

; 200 Cycles total in interrupt.
dispathc_int
	;btfsc PIR1, TMR2IF
	goto int_sound
	;goto intexit  ;Other interrupt  possible? Maybe should just go straight to intsound?

	cblock 0x20 ; <-- probably also unnescessary

	;Sound Struct
	Key1Th ;Ticks whole part high.
	Key1Tl ;Ticks decimal part.
	Key1Curr; How many updates have we have until our next key set.
	Key1State;Is our square wave High (32) or Low (0)
	
	Key2Th
	Key2Tl
	Key2Curr
	Key2State
	
	outChannel ;This is a sum of all Keys states then pushed to the PWM register
	
	;Main Loop Stuff
	currsixth
	keyInSixth

	;State Save Stuff
	PORTA_temp
	curr_channels
	max_channels
	temp_w
	temp_s
	temp_pclath
	fired
	temp_fsr
	endc

	;org 0x42 Probably unnescessary
int_sound ;Sound generation! called via the ISR when Timer1 int is up
Key1						
	movf Key1Th, w
	btfsc STATUS, Z			;If the ticksHigh register for this key isn't set then we skip this key.
	goto Key1Done			;Maybe be able to go all the way to the end of the update depending on 
	;First key check		;how keypresses get to this heezy.
	decfsz Key1Curr, f		
	goto Key1Done
Key1Set				 ;If 0 we need to toggle the state of the key.
	movf Key1Th, w   ;Get the number of cycles high.
	movwf Key1Curr
	btfsc Key1State, 6 ;Check the current state.6th bit = value 32 or ON
	goto Key1Low
Key1High
	movlw 32           ;Key High
	movwf Key1State
	addwf outChannel, f
	goto Key1Done
Key1Low
	movlw 0
	movwf Key1State
Key1Done

Key2					
	movf Key2Th, w
	btfsc STATUS, Z			;If the ticksHigh register for this key isn't set then we skip this key.
	goto Key2Done			;Maybe be able to go all the way to the end of the update depending on 
	;First key check		;how keypresses get to this heezy.
	decfsz Key2Curr, f		
	goto Key2Done
Key2Set				 ;If 0 we need to toggle the state of the key.
	movf Key2Th, w   ;Get the number of cycles high.
	movwf Key2Curr
	btfsc Key2State, 6 ;Check the current state.6th bit = value 32 or ON
	goto Key2Low
Key2High
	movlw 32           ;Key High
	movwf Key2State
	addwf outChannel, f
	goto Key2Done
Key2Low
	movlw 0           ;Key Low
	movwf Key2State
Key2Done

;One Key Length:
; 4 minimum if no key set
; 5 on average (should just have to decf and skip til next note)
; 9 if key goes low
; 11 if key goes high

int_sound_out
	movf outChannel, w
	movwf CCPR1L
	;In this interrupt we need to set the CCP1CON 4:5 and CCP1H with our duty cycle
	;movlw b'00111100'
	;movwf CCP1CON; turn PWM xxxx11xx turns PWM on on Bits 4:5 are CPR1L (the high bits of the PWM duty cycle)
	;movlw b'01111111'
	;movwf CCPR1L ; CCPR1L is the high 8 bits of PWM
	clrf outChannel			;Out channel needs to be reset. Gets filled up every call.
	goto intexit

intexit
	movf temp_pclath, W
	movwf PCLATH
	swapf temp_s, W
	movwf STATUS
	;swapf temp_fsr, W
	;movwf FSR
	swapf temp_w, F
	swapf temp_w, W
	 retfie

	org 0x100
;/****************************************
;  Set up code for the pic pre main loop.
;
;
;
;****************************************/
startupcode
	bsf STATUS, RP0	;Bank one sets

	movlw 0xFF
	movwf TRISA ;All of PORTA will be inputs
	movlw 0X00
	movwf TRISB ;PORTB will be all outputs

	bsf PIE1, TMR2IE  ;Turn timer 2 interrupt enable on.

	movlw 0xC8        ;Decimal 200 at 20khz we have 200 cycles before we have to update.
	movwf PR2
	bcf STATUS, RP0;Exit bank one

	bsf INTCON, GIE	;Turn on all unmasked interupts
	bsf INTCON, PEIE;Turn on peripheral interrupts
	movlw 0x07
	movwf CMCON	;turn off comparators


;/***************************
;  TMR1H:L needs to have (500 - the number of ops in our interrupt.) It generates an interrupt on overflow.
;  Also, we may need to disable the timer while resetting it's value every interrupt.
;  This may be run too slow.  Something about TOSC/4 i dunno.  I'll increase it if quality is shitty.
;
;  Probably should be ran at a rate of 40khz or somewherez in there.
;
;*************************/
	;movlw b'00000101'
		;bits6543 10
	;movwf T1CON	;turn timer1 on timer1 is a 16 bit timer, perfect for our application.
				;maybe not.... timer1 doesn't have a comparison register.
				;Only generates interrupts on overflow.
				; Timer 2 which is 8 bit has a pre and post scaler and can be compared to
				; PR2 for exact timing.
				; Reccomend Postscaling of 1:5 and PR2:100 should get me 500 cycles between
				; PWM samples
				; Meh, oscillator is only 4mhz so I dunno. I think I'm only going to get 100 cycles
				; between updates at 40khz sound.  Maybe I should switch to 20khz or 10khz again.
				; I'll need more accuracy though at these levels.
				; Also consider an external RC circuit at 20Mhz
				
	;movlw b'00000000' ;Least significant bit of our timer.
	;movwf TMR1L

;PR2 = 0b01111100 ;
;T2CON = 0b00000100 ;
;CCPR1L = 0b00111110 ;
;CCP1CON = 0b00011100 ;
;	http://www.micro-examples.com/public/microex-navig/doc/097-pwm-calculator.html

	movlw b'00001100'
		;bits 10	low bits of CPR1
	movwf CCP1CON; turn PWM on Bits 4:5 are CPR1H (the low bits of the PWM duty cycle)
	movlw b'00000000'
	movwf CCPR1L ; The MS 8 bits of PWM. Start at 0
	
	movlw 2			  ;decimal 8 is max channels
	movwf max_channels;
	

;========================================================
;
;    Start of our main loop.
;    All we are doing is checking for keys pressed.
;
;=======================================================

testkeyboard
	;movlw 21   ;decimal 21 for middle C
	;call noteValue
	movlw 38     ;Middle C
	movwf Key1Th
	clrf  Key1State
	clrf  Key1Curr
	movlw b'00000001'
	movwf PORTB		;Test First Sixth
infLoop
	goto infLoop  ;For test let's just play a C
	
	movlw 0x00
	movwf curr_channels;  The current number of channels occupied
	movlw 0x00
	movwf keyInSixth;How far into this sixth is this key. values 0 - 5 for 6
					;keys in a 6th
	movlw 0xFF
	movwf PORTA_temp;Set up our temp PORTA for anding
	movlw b'00000001'
	movwf PORTB		;Test First Sixth
	movf PORTA, W   ;Lets check if we have any keypresses on the first Sixth	
	btfss STATUS, Z
	call testnote	;if STATUS is not zero we have a note!
	call clearNotes
	goto testkeyboard

testnote 
	andwf PORTA_temp, f  ;Backup our PORTA
	btfsc PORTA_temp, RA1;
	call  newnote
	incf  keyInSixth, f

	btfsc PORTA_temp, RA2;
	call  newnote
	incf  keyInSixth, f

	btfsc PORTA_temp, RA3;
	call  newnote
	incf  keyInSixth, f

	btfsc PORTA_temp, RA4;
	call  newnote
	incf  keyInSixth, f

	btfsc PORTA_temp, RA5;
	call  newnote
	incf  keyInSixth, f

	btfsc PORTA_temp, RA6;
	call  newnote
	return

newnote
	movlw 0x20
	addwf curr_channels, W
	incf curr_channels, f
	movwf FSR
	clrf  INDF
	movf  keyInSixth, W
	movwf INDF
	return

clearNotes   ;Rest of the channels must be cleared
	clrf keyInSixth
	movf max_channels, W
	subwf curr_channels, W
	btfss STATUS, Z
	call newnote
	return

	end
	
; Formula= (SAMPLERATE / FREQUENCY) / 2
; Number of samples the note is up.
noteValue;20khz sample rate.
	addwf   PCL, f      ;   Move the PC this many forward
	retlw	11.36363636	;	880	A5
	retlw	12.03935907	;	830.609	G♯5/A♭5
	retlw	12.75524847	;	783.991	G5
	retlw	13.51371439	;	739.989	F♯5/G♭5
	retlw	14.31729415	;	698.456	F5
	retlw	15.16863733	;	659.255	E5
	retlw	16.07060782	;	622.254	D♯5/E♭5
	retlw	17.02620333	;	587.33	D5
	retlw	18.03865684	;	554.365	C♯5/D♭5
	retlw	19.11128693	;	523.251	C5 Tenor C
	retlw	20.24771049	;	493.883	B4
	retlw	21.45167795	;	466.164	A♯4/B♭4
	retlw	22.72727273	;	440	A4 A440
	retlw	24.07868916	;	415.305	G♯4/A♭4
	retlw	25.51052947	;	391.995	G4
	retlw	27.02746531	;	369.994	F♯4/G♭4
	retlw	28.63458829	;	349.228	F4
	retlw	30.33722863	;	329.628	E4
	retlw	32.14121565	;	311.127	D♯4/E♭4
	retlw	34.05240665	;	293.665	D4
	retlw	36.0772486	;	277.183	C♯4/D♭4
	retlw	38.22250082	;	261.626	C4 Middle C
	retlw	40.49533899	;	246.942	B3
	retlw	42.9033559	;	233.082	A♯3/B♭3
	retlw	45.45454545	;	220	A3
	retlw	48.15749427	;	207.652	G♯3/A♭3
	retlw	51.02092878	;	195.998	G3
	retlw	54.05493062	;	184.997	F♯3/G♭3
	retlw	57.26917658	;	174.614	F3
	retlw	60.67445727	;	164.814	E3
	retlw	64.2826379	;	155.563	D♯3/E♭3
	retlw	68.10504522	;	146.832	D3
	retlw	72.15475752	;	138.591	C♯3/D♭3
	retlw	76.44500164	;	130.813	C3 Low C
	retlw	80.99067797	;	123.471	B2
	retlw	85.8067118	;	116.541	A♯2/B♭2
	retlw	90.90909091	;	110	A2
	retlw	96.31498854	;	103.826	G♯2/A♭2
	retlw	102.0419617	;	97.9989	G2