; ============================================================================================
; PROJECT: HOME AUTOMATION - BOARD #2
; TARGET: PIC16F877A @ 4MHz (XT Oscillator)
; COMPILER: XC8 (pic-as)
;
; RESPONSIBILITIES:
;
; 1. MUHAMMED MEHMET GOKCE (152120221070) - COMPUTER ENGINEERING
;    - [R2.2.6] UART Module Implementation
;    - Protocol Design & Command Parsing
;    - Serial Communication Handlers
;
; 2. OGUN BALKAN (151220184062) - ELECTRICAL-ELECTRONICS ENGINEERING
;    - [R2.2.1] Step Motor Control Logic & Physics
;    - [R2.2.2] LDR Light Sensor Logic & Threshold Management
;    - [R2.2.5] Low-Level LCD Drivers
;
; 3. ARIF KUYBEN (151220184082) - ELECTRICAL-ELECTRONICS ENGINEERING
;    - [R2.2.5] LCD Display Module
;    - [R2.2.4] Rotary Potentiometer Integration
;    - System Initialization & Main Loop Architecture
; ============================================================================================

#include <xc.inc>

; ==============================================================================
; SYSTEM CONFIGURATION
; Responsible: ARIF KUYBEN
; ==============================================================================
    CONFIG FOSC = XT        ; Oscillator Selection: XT (4 MHz Crystal)
    CONFIG WDTE = OFF       ; Watchdog Timer: Disabled
    CONFIG PWRTE = ON       ; Power-up Timer: Enabled
    CONFIG BOREN = ON       ; Brown-out Reset: Enabled
    CONFIG LVP = OFF        ; Low-Voltage Programming: Disabled
    CONFIG CPD = OFF        ; Data EEPROM Memory Code Protection: Disabled
    CONFIG WRT = OFF        ; Flash Program Memory Write Enable: Disabled
    CONFIG CP = OFF         ; Flash Program Memory Code Protection: Disabled

; --- CONSTANTS ---
LDR_THRESHOLD EQU 50        ; Threshold value for Light Sensor (Range 0-255)

; ==============================================================================
; MEMORY ALLOCATION (RAM BANK 0)
; ==============================================================================
    PSECT udata_bank0
    
; [R2.2.1-1] Desired curtain status (0% = Open, 100% = Closed)
desired_curtain: DS 1    

; [R2.2.1-2] Current curtain status (Updated by Motor Logic)
current_curtain: DS 1    

; [R2.2.2-1] Light intensity value (Read from LDR)
light_level:     DS 1    

; Step Motor Control Variables
step_index:      DS 1    ; Current index in step sequence (0-3)
portd_shadow:    DS 1    ; Shadow register for PORTD (Read-Modify-Write safety)
step_loop_cnt:   DS 1    ; Loop counter for motor speed delay

; Math & Helper Variables
math_num1:       DS 1    ; Math Operand 1
math_num2:       DS 1    ; Math Operand 2
math_res_l:      DS 1    ; Math Result Low Byte
math_res_h:      DS 1    ; Math Result High Byte
temp_val:        DS 1    ; Temporary storage
lcd_buff:        DS 1    ; Buffer for LCD data processing
lcd_temp:        DS 1    ; Temp storage for LCD nibble swapping
digit_100:       DS 1    ; BCD Hundreds digit
digit_10:        DS 1    ; BCD Tens digit
digit_1:         DS 1    ; BCD Ones digit
delay1:          DS 1    ; Delay counter 1
delay2:          DS 1    ; Delay counter 2

; UART & Control Logic Variables
uart_data:       DS 1    ; Received UART byte
uart_temp:       DS 1    ; Temp storage for UART TX
last_pot_val:    DS 1    ; Previous potentiometer value (for jitter filter)
ldr_active_flag: DS 1    ; Flag: 1 if LDR forced curtain close, 0 otherwise
saved_curtain_val: DS 1  ; Backup of user setting before LDR override

; ==============================================================================
; RESET VECTOR
; ==============================================================================
    PSECT resVect, class=CODE, delta=2, abs
ORG 0x0000
    PAGESEL INIT
    GOTO INIT

; ==============================================================================
; LOOKUP TABLES
; ==============================================================================
    PSECT table_sect, class=CODE, delta=2, abs
ORG 0x0020

; ------------------------------------------------------------------------------
; [R2.2.1] Step Motor Sequence Table
; Responsible: OGUN BALKAN
; Description: Half-step or Full-step sequence codes for unipolar stepper motor.
; ------------------------------------------------------------------------------
GET_STEP_CODE:
    ANDLW 0x03              ; Ensure index is within 0-3 range
    ADDWF PCL, F            ; Jump to table offset
    RETLW 0x01              ; Step 1: 0001
    RETLW 0x02              ; Step 2: 0010
    RETLW 0x04              ; Step 3: 0100
    RETLW 0x08              ; Step 4: 1000

; ==============================================================================
; SYSTEM INITIALIZATION
; Responsible: ARIF KUYBEN
; ==============================================================================
    PSECT code, class=CODE, delta=2

INIT:
    ; --- Port Configuration ---
    BANKSEL TRISA
    MOVLW 0xFF              ; Set PORTA as Input (for ADC)
    MOVWF TRISA
    
    BANKSEL TRISD
    CLRF TRISD              ; Set PORTD as Output (LCD Data & Motor)
    
    BANKSEL TRISE
    CLRF TRISE              ; Set PORTE as Output (LCD Control)
    
    BANKSEL TRISB
    MOVLW 0x01              ; Set RB0 as Input, others Output
    MOVWF TRISB
    
    ; --- UART Pin Configuration ---
    BANKSEL TRISC
    BSF TRISC, 7            ; RC7/RX must be Input
    BCF TRISC, 6            ; RC6/TX must be Output
    
    ; --- ADC Configuration ---
    BANKSEL ADCON1
    MOVLW 0x04              ; AN0, AN1, AN3 Analog. VREF+ = VDD.
    MOVWF ADCON1
    BANKSEL ADCON0
    MOVLW 0x81              ; Fosc/32 clock, ADC Enabled (ADON=1)
    MOVWF ADCON0

    ; --- UART Initialization (9600 Baud @ 4MHz) ---
    BANKSEL SPBRG
    MOVLW 25                ; SPBRG = ((4MHz / 9600) / 16) - 1 = 25
    MOVWF SPBRG
    
    BANKSEL TXSTA
    MOVLW 0x24              ; TXEN=1 (Transmit Enable), BRGH=1 (High Speed)
    MOVWF TXSTA
    
    BANKSEL RCSTA
    MOVLW 0x90              ; SPEN=1 (Serial Port Enable), CREN=1 (Continuous Rx)
    MOVWF RCSTA

    ; --- Variable Reset ---
    BANKSEL current_curtain
    CLRF current_curtain
    CLRF step_index
    CLRF portd_shadow
    CLRF ldr_active_flag
    CLRF saved_curtain_val
    
    BANKSEL PORTD
    CLRF PORTD
    
    MOVLW 0xFF              ; Initialize Pot value to max to force first read
    MOVWF last_pot_val

    ; --- LCD Initialization ---
    BANKSEL PORTE
    BCF PORTE, 1            ; RW = 0
    BCF PORTE, 2            ; EN = 0
    CALL LCD_INIT

; ==============================================================================
; MAIN APPLICATION LOOP
; Responsible: ARIF KUYBEN (Architecture)
; ==============================================================================
MAIN_LOOP:
    ; 1. [R2.2.6-1] Service UART requests (Remote Control)
    CALL UART_TASK           
    
    ; 2. [R2.2.4-1] Read Potentiometer (Manual Control)
    CALL READ_POT_SMART      
    
    ; 3. [R2.2.2-1] Read LDR Sensor (Environment Monitoring)
    CALL READ_LDR_LINEAR     
    
    ; 4. [R2.2.2-2] Automation Logic (Light Threshold Check)
    CALL CHECK_LDR_THRESHOLD 
    
    ; 5. [R2.2.1-3] Motor Control Logic (Move Curtain)
    CALL CONTROL_CURTAIN_LOGIC 
    
    ; 6. [R2.2.5-1] Update Information Display
    CALL UPDATE_LCD_REQ      
    
    GOTO MAIN_LOOP          ; Repeat forever

; ==============================================================================
; [R2.2.6] UART MODULE
; Responsible: MUHAMMED MEHMET GOKCE
; Function: Handles bidirectional serial communication with PC API.
; ==============================================================================
UART_TASK:
    ; Check for Frame Error / Overrun Error
    BANKSEL RCSTA
    BTFSS RCSTA, 1          ; Check OERR bit
    GOTO CHECK_RX_FLAG
    BCF RCSTA, 4            ; Reset CREN to clear error
    BSF RCSTA, 4            ; Re-enable CREN

CHECK_RX_FLAG:
    BANKSEL PIR1
    BTFSS PIR1, 5           ; Check RCIF (Data Received?)
    RETURN                  ; No data, return to main loop
    
    ; Read Data from Buffer
    BANKSEL RCREG
    MOVF RCREG, W
    BANKSEL uart_data
    MOVWF uart_data
    
    ; --- COMMAND PARSING ---
    
    ; 1. Check SET Command (Format: 11xxxxxx)
    MOVLW 0xC0              ; Mask for top 2 bits (11000000)
    ANDWF uart_data, W      ; Isolate top 2 bits
    SUBLW 0xC0              ; Compare with 11000000
    BTFSC STATUS, 2         ; If Zero flag is set, it's a match
    GOTO UART_CMD_SET
    
    ; 2. Check GET Commands (0x01 - 0x08)
    
    ; Get Desired Curtain Low Byte (Fractional) -> Always 0
    MOVF uart_data, W
    SUBLW 0x01
    BTFSC STATUS, 2
    GOTO SEND_ZERO
    
    ; Get Desired Curtain High Byte (Integral)
    MOVF uart_data, W
    SUBLW 0x02
    BTFSC STATUS, 2
    GOTO SEND_DES_CURTAIN
    
    ; Get Outdoor Temp Low Byte
    MOVF uart_data, W
    SUBLW 0x03
    BTFSC STATUS, 2
    GOTO SEND_TEMP_FRAC
    
    ; Get Outdoor Temp High Byte
    MOVF uart_data, W
    SUBLW 0x04
    BTFSC STATUS, 2
    GOTO SEND_TEMP_INT
    
    ; Get Pressure Low Byte
    MOVF uart_data, W
    SUBLW 0x05
    BTFSC STATUS, 2
    GOTO SEND_PRES_L
    
    ; Get Pressure High Byte
    MOVF uart_data, W
    SUBLW 0x06
    BTFSC STATUS, 2
    GOTO SEND_PRES_H
    
    ; Get Light Intensity Low Byte -> Always 0
    MOVF uart_data, W
    SUBLW 0x07
    BTFSC STATUS, 2
    GOTO SEND_ZERO
    
    ; Get Light Intensity High Byte
    MOVF uart_data, W
    SUBLW 0x08
    BTFSC STATUS, 2
    GOTO SEND_LIGHT
    
    RETURN

UART_CMD_SET:
    ; Extract 6-bit value (0-63) from command
    MOVLW 0x3F              ; Mask 00111111
    ANDWF uart_data, W
    MOVWF desired_curtain   ; Update desired curtain position
    RETURN

; --- UART RESPONSE ROUTINES ---
SEND_ZERO:
    MOVLW 0
    CALL UART_TX
    RETURN

SEND_DES_CURTAIN:
    ; Cap value at 100% just in case
    MOVF desired_curtain, W
    SUBLW 100
    BTFSS STATUS, 0         ; If Desired > 100
    GOTO SEND_100_FORCE        
    MOVF desired_curtain, W
    CALL UART_TX
    RETURN
SEND_100_FORCE:
    MOVLW 100
    CALL UART_TX
    RETURN

; Dummy values for sensors not present on Board #2
SEND_TEMP_FRAC:
    MOVLW 5                 ; 0.5 C
    CALL UART_TX
    RETURN
SEND_TEMP_INT:
    MOVLW 25                ; 25 C
    CALL UART_TX
    RETURN
SEND_PRES_L:
    MOVLW 0xF5              ; 1013 hPa (Low Byte)
    CALL UART_TX
    RETURN
SEND_PRES_H:
    MOVLW 0x03              ; 1013 hPa (High Byte)
    CALL UART_TX
    RETURN
SEND_LIGHT:
    MOVF light_level, W     ; Send actual LDR value
    CALL UART_TX
    RETURN

UART_TX:
    BANKSEL uart_temp
    MOVWF uart_temp         ; Store W
    BANKSEL TXSTA
TX_WAIT:
    BTFSS TXSTA, 1          ; Check TRMT (Transmit Buffer Empty)
    GOTO TX_WAIT            ; Wait until empty
    BANKSEL TXREG
    BANKSEL uart_temp
    MOVF uart_temp, W       ; Restore W
    MOVWF TXREG             ; Send Byte
    BANKSEL PORTD           ; Safe Return to Bank 0
    RETURN

; ==============================================================================
; [R2.2.2] LDR LIGHT SENSOR LOGIC
; Responsible: OGUN BALKAN
; Function: Monitors light level and overrides curtain if too dark.
; ==============================================================================
CHECK_LDR_THRESHOLD:
    MOVF light_level, W
    SUBLW LDR_THRESHOLD
    BTFSS STATUS, 0          ; Check if Light < Threshold
    GOTO LDR_IS_BRIGHT       ; Carry=1 means Result > 0 (Light > Threshold)
    
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
    BTFSC STATUS, 2          ; Check if we were in dark mode
    RETURN                   ; Flag=0, everything normal. Return.
    
    ; Light just returned!
    ; 1. Restore the user's previous setting
    MOVF saved_curtain_val, W
    MOVWF desired_curtain
    
    ; 2. Clear Flag
    CLRF ldr_active_flag
    RETURN

; ==============================================================================
; [R2.2.4] ROTARY POTENTIOMETER LOGIC
; Responsible: ARIF KUYBEN
; Function: Reads analog pot value and maps to curtain percentage.
; ==============================================================================
READ_POT_SMART:
    ; Safety Check: If LDR forced closure, ignore Potentiometer
    MOVF ldr_active_flag, W
    BTFSS STATUS, 2          ; If Flag=1
    RETURN                   ; Exit
    
    ; Start ADC Conversion
    BANKSEL ADCON0
    BSF ADCON0, 3            ; Select AN1 Channel
    BCF ADCON0, 4
    BCF ADCON0, 5
    CALL DELAY_US            ; Acquisition Delay
    BSF ADCON0, 2            ; Start Conversion (GO)
W_ADC1:
    BTFSC ADCON0, 2          ; Wait for DONE
    GOTO W_ADC1
    MOVF ADRESH, W           ; Read Result (8-bit)
    BANKSEL math_num1
    MOVWF math_num1
    
    ; Map 0-255 -> 0-100
    MOVLW 101                ; Scaling factor (approx)
    MOVWF math_num2
    CALL MATH_MUL_8x8
    
    ; Check Bounds
    MOVF math_res_h, W
    SUBLW 100
    BTFSS STATUS, 0
    GOTO SET_MAX_100_CHECK
    MOVF math_res_h, W
    MOVWF temp_val
    GOTO CHECK_CHANGE

SET_MAX_100_CHECK:
    MOVLW 100
    MOVWF temp_val

CHECK_CHANGE:
    ; Jitter Filter: Only update if value changed significantly
    MOVF temp_val, W
    SUBWF last_pot_val, W
    BTFSC STATUS, 2          ; If New == Old, Return
    RETURN
    
    ; [R2.2.4-1] Update desired curtain value
    MOVF temp_val, W
    MOVWF desired_curtain 
    MOVWF last_pot_val       ; Update history
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
    BTFSS STATUS, 0          ; If Borrow occurred (Current < Desired)
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
    
    ; Protect LCD bits (Upper 4) using Shadow Register
    MOVF portd_shadow, W
    ANDLW 0xF0               ; Keep Upper 4 bits
    IORWF lcd_buff, W        ; Combine with New Motor bits
    MOVWF portd_shadow
    MOVWF PORTD              ; Write to Physical Port
    CALL DELAY_MOTOR
    RETURN

; ==============================================================================
; [R2.2.5] LCD MODULE IMPLEMENTATION
; Responsible: ARIF KUYBEN
; Function: Displays system status on 2x16 LCD using 4-bit mode.
; ==============================================================================
UPDATE_LCD_REQ:
    ; --- Line 1: Temp & Pressure ---
    MOVLW 0x80              ; Set Cursor to Line 1
    CALL LCD_CMD
    
    ; Static Display for Sim: "+25.5 C"
    MOVLW '+'
    CALL LCD_DATA
    MOVLW '2'
    CALL LCD_DATA
    MOVLW '5'
    CALL LCD_DATA
    MOVLW '.'
    CALL LCD_DATA
    MOVLW '5'
    CALL LCD_DATA
    MOVLW 0xDF              ; Degree Symbol
    CALL LCD_DATA
    MOVLW 'C'
    CALL LCD_DATA
    MOVLW ' '
    CALL LCD_DATA
    
    ; Static Display for Sim: "1013hPa"
    MOVLW '1'
    CALL LCD_DATA
    MOVLW '0'
    CALL LCD_DATA
    MOVLW '1'
    CALL LCD_DATA
    MOVLW '3'
    CALL LCD_DATA
    MOVLW 'h'
    CALL LCD_DATA
    MOVLW 'P'
    CALL LCD_DATA
    MOVLW 'a'
    CALL LCD_DATA
    
    ; --- Line 2: Light & Curtain ---
    MOVLW 0xC0              ; Set Cursor to Line 2
    CALL LCD_CMD
    
    MOVLW ' '
    CALL LCD_DATA
    MOVLW ' '
    CALL LCD_DATA
    
    ; [R2.2.5-1] Display Light Intensity
    MOVF light_level, W
    CALL PRINT_3DIGIT       ; Convert Binary to ASCII
    MOVLW 'L'
    CALL LCD_DATA
    MOVLW 'u'
    CALL LCD_DATA
    MOVLW 'x'
    CALL LCD_DATA
    
    MOVLW ' '
    CALL LCD_DATA
    MOVLW ' '
    CALL LCD_DATA
    
    ; [R2.2.5-1] Display Curtain Status
    MOVF current_curtain, W
    CALL PRINT_2DIGIT_CLAMPED
    MOVLW '.'
    CALL LCD_DATA
    MOVLW '0'
    CALL LCD_DATA
    MOVLW '%'
    CALL LCD_DATA
    RETURN

PRINT_2DIGIT_CLAMPED:
    MOVWF temp_val
    MOVLW 100
    SUBWF temp_val, W
    BTFSS STATUS, 0         ; If val < 100
    GOTO PRINT_NORMAL
    MOVLW 99                ; Clamp visual at 99 to fit screen
    MOVWF temp_val
PRINT_NORMAL:
    CLRF digit_10
L_10:
    MOVLW 10
    SUBWF temp_val, W
    BTFSS STATUS, 0
    GOTO P_2D_OUT
    MOVWF temp_val
    INCF digit_10, F
    GOTO L_10
P_2D_OUT:
    MOVF digit_10, W
    ADDLW '0'
    CALL LCD_DATA
    MOVF temp_val, W
    ADDLW '0'
    CALL LCD_DATA
    RETURN

PRINT_3DIGIT:
    MOVWF temp_val
    CLRF digit_100
    CLRF digit_10
L_100:
    MOVLW 100
    SUBWF temp_val, W
    BTFSS STATUS, 0
    GOTO L_10_3
    MOVWF temp_val
    INCF digit_100, F
    GOTO L_100
L_10_3:
    MOVLW 10
    SUBWF temp_val, W
    BTFSS STATUS, 0
    GOTO P_3D_OUT
    MOVWF temp_val
    INCF digit_10, F
    GOTO L_10_3
P_3D_OUT:
    MOVF digit_100, W
    ADDLW '0'
    CALL LCD_DATA
    MOVF digit_10, W
    ADDLW '0'
    CALL LCD_DATA
    MOVF temp_val, W
    ADDLW '0'
    CALL LCD_DATA
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
    MOVLW 10                ; Controls Step Speed
    MOVWF delay1
DM1: MOVLW 200
    MOVWF delay2
DM2: DECFSZ delay2, F
    GOTO DM2
    DECFSZ delay1, F
    GOTO DM1
    RETURN

END