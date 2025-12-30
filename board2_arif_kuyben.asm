;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...
