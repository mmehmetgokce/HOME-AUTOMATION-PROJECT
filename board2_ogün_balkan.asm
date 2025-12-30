
; ------------------------------------------------------------------------------
; Project  : Curtain Control System - Board #2
; Author   : Ogün Balkan
; MCU      : PIC16F877A
; ------------------------------------------------------------------------------


; ------------------------------------------------------------------------------
; [R2.2.1] Step Motor Sequence Table
; Responsible: OGUN BALKAN
; Description: Full-step (single coil excitation) sequence 
; for unipolar stepper motor. (Updated from bottom comments)
; ------------------------------------------------------------------------------
GET_STEP_CODE:
    ANDLW 0x03              ; Ensure index is within 0-3 range
    ADDWF PCL, F            ; Jump to table offset
    RETLW 0x01              ; Step 1: 0001
    RETLW 0x02              ; Step 2: 0010
    RETLW 0x04              ; Step 3: 0100
    RETLW 0x08              ; Step 4: 1000



; ==============================================================================
; [R2.2.2] LDR LIGHT SENSOR LOGIC
; Responsible: OGUN BALKAN
; Function: Monitors light level and overrides curtain if too dark.
; ==============================================================================
CHECK_LDR_THRESHOLD:
    MOVF light_level, W
    SUBLW LDR_THRESHOLD
    BTFSS STATUS, 0          ; C=1 if Light <= Threshold (Dark condition)
    GOTO LDR_IS_BRIGHT       ; C=0 means Light > Threshold (Bright condition)
    
    ; --- DARK DETECTED ---
    MOVF ldr_active_flag, W
    BTFSS STATUS, 2          ; Check if we already handled this
    RETURN                   ; Flag=1, already in dark mode. Return.
    
    ; [R2.2.2-2] First time darkness detected:
    ; 1. Save current user preference to restore later
    MOVF desired_curtain, W
    MOVWF saved_curtain_val
    
    ; 2. Force curtain to Close (100%)
    MOVLW 100
    MOVWF desired_curtain
    
    ; 3. Set Flag to avoid repetitive saving
    MOVLW 1
    MOVWF ldr_active_flag
    RETURN

LDR_IS_BRIGHT:
    ; --- BRIGHT DETECTED ---
    MOVF ldr_active_flag, W
    BTFSC STATUS, 2          ; If ldr_active_flag == 0, system already in normal mode
    RETURN                   ; No restoration needed
    
    ; Light just returned!
    ; 1. Restore the user's previous setting
    MOVF saved_curtain_val, W
    MOVWF desired_curtain
    
    ; 2. Clear Flag
    CLRF ldr_active_flag
    RETURN



; ==============================================================================
; [R2.2.2-1] LDR READ ROUTINE
; Responsible: OGUN BALKAN
; ==============================================================================
READ_LDR_LINEAR:
    BANKSEL ADCON0
    BCF ADCON0, 3            ; Select AN0 Channel
    BCF ADCON0, 4
    BCF ADCON0, 5
    CALL DELAY_US
    BSF ADCON0, 2
W_ADC0:
    BTFSC ADCON0, 2
    GOTO W_ADC0
    MOVF ADRESH, W           ; Read 8-bit value
    BANKSEL light_level
    MOVWF light_level        ; Update memory
    RETURN

; --- MATH HELPER: 8x8 Bit Multiplication ---
; Multiplies two 8-bit numbers (math_num1 x math_num2)
; Result stored in math_res_h : math_res_l
MATH_MUL_8x8:
    CLRF math_res_h
    CLRF math_res_l
    MOVLW 8
    MOVWF step_loop_cnt
    MOVF math_num1, W
MUL_LOOP:
    RRF math_num2, F
    BTFSS STATUS, 0
    GOTO NO_ADD
    ADDWF math_res_h, F
NO_ADD:
    RRF math_res_h, F
    RRF math_res_l, F
    DECFSZ step_loop_cnt, F
    GOTO MUL_LOOP
    RETURN

; ==============================================================================
; [R2.2.1] STEP MOTOR CONTROL MODULE
; Responsible: OGUN BALKAN
; Function: Compares current vs desired status and drives the motor.
; ==============================================================================
CONTROL_CURTAIN_LOGIC:
    BANKSEL current_curtain
    MOVF desired_curtain, W
    SUBWF current_curtain, W
    BTFSC STATUS, 2          ; If Current == Desired, Stop.
    RETURN
    
    ; Check Direction
    BTFSS STATUS, 0          ; If Current < Desired, curtain must be closed further
    GOTO ACTION_CLOSE        ; We need to increase percentage (Close)
    GOTO ACTION_OPEN         ; We need to decrease percentage (Open)

ACTION_CLOSE: 
    MOVLW 10                 ; Steps per percent loop
    MOVWF step_loop_cnt
LOOP_CLOSE:
    INCF step_index, F       ; Increment Phase Index
    CALL DO_STEP_PHYSICAL    ; Output to Pins
    DECFSZ step_loop_cnt, F
    GOTO LOOP_CLOSE
    
    ; [R2.2.1-2] Update Status
    INCF current_curtain, F
    RETURN

ACTION_OPEN:
    MOVLW 10
    MOVWF step_loop_cnt
LOOP_OPEN:
    DECF step_index, F       ; Decrement Phase Index
    CALL DO_STEP_PHYSICAL    ; Output to Pins
    DECFSZ step_loop_cnt, F
    GOTO LOOP_OPEN
    
    ; [R2.2.1-2] Update Status
    DECF current_curtain, F
    RETURN

DO_STEP_PHYSICAL:
    MOVF step_index, W
    CALL GET_STEP_CODE       ; Get Bit Pattern (e.g., 0001)
    ANDLW 0x0F               ; Mask Lower 4 bits
    MOVWF lcd_buff
    
    ; Protect LCD upper data bits while updating motor control pins
    MOVF portd_shadow, W
    ANDLW 0xF0               ; Keep Upper 4 bits
    IORWF lcd_buff, W        ; Combine with New Motor bits
    MOVWF portd_shadow
    MOVWF PORTD              ; Write to Physical Port
    CALL DELAY_MOTOR
    RETURN



; ==============================================================================
; LOW LEVEL LCD DRIVERS
; Responsible: OGUN BALKAN
; ==============================================================================
LCD_INIT:
    CALL DELAY_MS           ; Power-up wait
    CALL DELAY_MS
    MOVLW 0x30              ; Soft Reset 1
    CALL LCD_CMD_NIBBLE
    CALL DELAY_MS
    MOVLW 0x30              ; Soft Reset 2
    CALL LCD_CMD_NIBBLE
    CALL DELAY_MS
    MOVLW 0x30              ; Soft Reset 3
    CALL LCD_CMD_NIBBLE
    CALL DELAY_MS
    MOVLW 0x20              ; Set 4-bit Mode
    CALL LCD_CMD_NIBBLE
    CALL DELAY_MS
    MOVLW 0x28              ; 4-bit, 2-line, 5x7
    CALL LCD_CMD
    MOVLW 0x0C              ; Display ON, Cursor OFF
    CALL LCD_CMD
    MOVLW 0x06              ; Increment Mode
    CALL LCD_CMD
    MOVLW 0x01              ; Clear Screen
    CALL LCD_CMD
    RETURN

LCD_CMD:
    MOVWF lcd_temp
    ANDLW 0xF0
    CALL LCD_SEND_NIBBLE
    SWAPF lcd_temp, W
    ANDLW 0xF0
    CALL LCD_SEND_NIBBLE
    CALL DELAY_MS
    RETURN

LCD_DATA:
    MOVWF lcd_temp
    ANDLW 0xF0
    CALL LCD_SEND_DATA_NIBBLE
    SWAPF lcd_temp, W
    ANDLW 0xF0
    CALL LCD_SEND_DATA_NIBBLE
    CALL DELAY_US
    RETURN

LCD_CMD_NIBBLE:
    ANDLW 0xF0
    CALL LCD_SEND_NIBBLE
    CALL DELAY_MS
    RETURN

LCD_SEND_NIBBLE:
    BCF PORTE, 0            ; RS = 0 (Command)
    GOTO LCD_PORT_WRITE

LCD_SEND_DATA_NIBBLE:
    BSF PORTE, 0            ; RS = 1 (Data)
    GOTO LCD_PORT_WRITE

LCD_PORT_WRITE:
    MOVWF lcd_buff
    MOVF portd_shadow, W
    ANDLW 0x0F              ; Keep Motor Bits (Lower 4)
    IORWF lcd_buff, W       ; Add LCD Bits (Upper 4)
    MOVWF portd_shadow
    MOVWF PORTD
    BSF PORTE, 2            ; Pulse Enable
    NOP
    NOP
    BCF PORTE, 2
    RETURN

; ==============================================================================
; TIMING ROUTINES
; Optimized for 4MHz Clock
; ==============================================================================
DELAY_MS:
    MOVLW 50
    MOVWF delay1
D1: MOVLW 200
    MOVWF delay2
D2: DECFSZ delay2, F
    GOTO D2
    DECFSZ delay1, F
    GOTO D1
    RETURN

DELAY_US:
    MOVLW 50
    MOVWF delay1
D_US: DECFSZ delay1, F
    GOTO D_US
    RETURN

DELAY_MOTOR:
    MOVLW 10                ; Controls stepper motor speed
    MOVWF delay1
DM1: MOVLW 200
    MOVWF delay2
DM2: DECFSZ delay2, F
    GOTO DM2
    DECFSZ delay1, F
    GOTO DM1
    RETURN

END