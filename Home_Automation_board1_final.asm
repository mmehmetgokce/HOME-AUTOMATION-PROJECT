; ============================================================================================
; PROJECT: HOME AUTOMATION - BOARD #1
; TARGET: PIC16F877A @ 4MHz (XT Oscillator)
; COMPILER: XC8 (pic-as)
;
; RESPONSIBILITIES:
;
; 1. MUHAMMED MEHMET GOKCE (152120221070) - COMPUTER ENGINEERING
;    -[R2.1.1] Temperature Control Module logic.
;    -Sensor data acquisition and validation logic.
;
; 2. YUSUF GOC (152120221056) - COMPUTER ENGINEERING
;    -[R2.1.4] UART Module implementation.
;    -Protocol Design & Command Parsing.
;    -Serial Interrupt Service Routines.
;    -Main Loop architecture.
;
; 3. EMINE ATMA (151220222075) - ELECTRICAL-ELECTRONICS ENGINEERING
;    -[R2.1.2] Keypad Module & Input State Machine.
;    -[R2.1.3] Display Module (7-Segment Multiplexing).
;    -Timer & Interrupt Configuration.
; ============================================================================================

#include <xc.inc>

; ==============================================================================
; SYSTEM CONFIGURATION
; Responsible: EMINE ATMA
; ==============================================================================
    CONFIG FOSC = XT, WDTE = OFF, PWRTE = ON, BOREN = ON
    CONFIG LVP = OFF, CPD = OFF, WRT = OFF, CP = OFF

; ==============================================================================
; VARIABLE DEFINITIONS (BANK 0)
; ==============================================================================
    PSECT udata_bank0
    
; System Status Flags
SYSTEM_FLAGS:     DS 1    ; Bit 0: Cooler ON, Bit 1: Heater ON

; [R2.1.1-1] Memory address reserved to keep the desired temperature value.
DESIRED_TEMP_INT: DS 1    ; Integral part of desired temp
DESIRED_TEMP_FRC: DS 1    ; Fractional part of desired temp

; [R2.1.1-4] Ambient temperature value read periodically.
CURR_TEMP_INT:    DS 1    ; Integral part of ambient temp
CURR_TEMP_FRC:    DS 1    ; Fractional part of ambient temp

; [R2.1.1-5] Fan speed (in rps) value read periodically.
FAN_SPEED_RPS:    DS 1    

; Communication Buffers
UART_RX_BUF:      DS 1    ; Buffer for received UART byte

; Display & Timing Variables
DISPLAY_MODE:     DS 1    ; 0: Desired, 1: Ambient, 2: Fan, 3: Input
INT_COUNTER:      DS 1    ; Counter for Multiplexing Timing
SEC_FLAG:         DS 1    ; 1-Second Flag for Fan Speed Calculation
TWO_SEC_CNTR:     DS 1    ; [R2.1.3-1] Counter for 2-second display interval
        
; [R2.1.3] Display Buffer Variables
DIGIT1_VAL:       DS 1    ; Leftmost digit data
DIGIT2_VAL:       DS 1    
DIGIT3_VAL:       DS 1    
DIGIT4_VAL:       DS 1    ; Rightmost digit data
DOT_STATE:        DS 1    ; Decimal Point control
TEMP_SEG:         DS 1    
        
; Math Helper Variables
CALC_D1:          DS 1
CALC_D2:          DS 1
        
; ADC Variables
TEMP_ADC_L:       DS 1
TEMP_ADC_H:       DS 1
BCD_TEMP_L:       DS 1
        
; [R2.1.2] Keypad Variables
KEY_PRESSED:      DS 1    ; Code of currently pressed key
LAST_KEY:         DS 1    ; Code of previously pressed key (Debounce)
INPUT_STATE:      DS 1    ; State Machine Index for Input Logic
NEW_TEMP_INT:     DS 1    ; Temp storage during input
NEW_TEMP_FRC:     DS 1    ; Temp storage during input
DEBOUNCE_CNT:     DS 1    
COLUMN_DELAY:     DS 1    
DELAY_VAR:        DS 1    

; [R2.1.2-1] Software Interrupt Flag
ISR_FLAG:         DS 1    ; Bit 0: Set when Keypad 'A' is pressed

; ==============================================================================
; INTERRUPT CONTEXT SAVING
; ==============================================================================
    PSECT udata_shr
W_TEMP:           DS 1
STATUS_TEMP:      DS 1
PCLATH_TEMP:      DS 1

; ==============================================================================
; RESET VECTOR & INTERRUPT VECTOR
; ==============================================================================
    PSECT code, abs
    ORG 0x0000
    GOTO    Init_System

    ORG 0x0004
    GOTO    ISR_Handler

; ==============================================================================
; LOOKUP TABLE (7-SEGMENT DECODING)
; Responsible: EMINE ATMA
; ==============================================================================
    ORG 0x0020
GetSeg:
    ANDLW   0x0F            ; Mask lower nibble
    ADDWF   PCL, F          ; Computed GOTO
    RETLW   00111111B ; 0
    RETLW   00000110B ; 1
    RETLW   01011011B ; 2
    RETLW   01001111B ; 3
    RETLW   01100110B ; 4
    RETLW   01101101B ; 5
    RETLW   01111101B ; 6
    RETLW   00000111B ; 7
    RETLW   01111111B ; 8
    RETLW   01101111B ; 9
    RETLW   00000000B ; 10 (Blank)
    RETLW   01000000B ; 11 (Dash -)
    RETLW   00000000B
    RETLW   00000000B
    RETLW   00000000B
    RETLW   00000000B

; ==============================================================================
; INTERRUPT SERVICE ROUTINE (ISR)
; Responsible: YUSUF GOC (UART) & EMINE ATMA (Timer/Keypad)
; ==============================================================================
ISR_Handler:
    ; Context Save
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP
    
    CLRF    PCLATH

    ; [R2.1.2-1] Check if Button A was pressed (Software Interrupt Trigger)
    BANKSEL ISR_FLAG
    BTFSC   ISR_FLAG, 0     ; If Flag is set
    CALL    ISR_Keypad_Task ; Run the interrupt routine for input

    ; [R2.1.4] UART Interrupt Handler
    BANKSEL PIR1
    BTFSC   PIR1, 5         ; Check RCIF (Data Received)
    CALL    UART_Process    

    ; [R2.1.3] Timer Interrupt Handler (Multiplexing)
    BANKSEL PIR1
    BTFSS   PIR1, 1         ; Check TMR2IF
    GOTO    ISR_Exit
    
    BCF     PIR1, 1         ; Clear Timer Flag
    CALL    Display_Refresh_ISR

ISR_Exit:
    ; Context Restore
    MOVF    PCLATH_TEMP, W
    MOVWF   PCLATH
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE

; ==============================================================================
; [R2.1.2-1] INTERRUPT ROUTINE FOR BUTTON 'A'
; Responsible: EMINE ATMA
; Function: Initializes the system for user input mode when 'A' is pressed.
; ==============================================================================
ISR_Keypad_Task:
    BANKSEL ISR_FLAG
    BCF     ISR_FLAG, 0     ; Clear the trigger flag

    ; Prepare system state for Input Mode
    MOVLW   3
    MOVWF   DISPLAY_MODE    ; Set Display Mode to Input (3)
    MOVLW   1
    MOVWF   INPUT_STATE     ; Set State Machine to 'Get Tens Digit'
    
    ; Clear Display Buffers (Show Blank)
    MOVLW   10              ; Code for Blank
    MOVWF   DIGIT1_VAL
    MOVWF   DIGIT2_VAL
    MOVWF   DIGIT3_VAL
    CLRF    DIGIT4_VAL
    
    BCF     DOT_STATE, 0    ; Turn off decimal point
    CLRF    NEW_TEMP_INT    ; Clear temp input storage
    CLRF    NEW_TEMP_FRC
    
    RETURN

; ==============================================================================
; SYSTEM INITIALIZATION
; Responsible: EMINE ATMA
; ==============================================================================
Init_System:
    CLRF    PCLATH

    ; --- Port Configuration ---
    BANKSEL TRISA
    MOVLW   00010001B       ; RA0 (Analog In), RA4 (Tachometer In)
    MOVWF   TRISA
    MOVLW   11110000B       ; RB4-7 Input (Rows), RB0-3 Output (Cols)
    MOVWF   TRISB
    CLRF    TRISD           ; PORTD Output (7-Segment Data)
    
    ; --- Control Pins ---
    BSF     TRISC, 7        ; RX Input
    BCF     TRISC, 6        ; TX Output
    BCF     TRISC, 0        ; Heater Control Output
    BCF     TRISC, 1        ; Cooler Control Output

    ; --- ADC Configuration ---
    MOVLW   10001110B       ; Right Justified, AN0 Analog
    MOVWF   ADCON1
    BANKSEL ADCON0
    MOVLW   01000001B       ; Fosc/8, Channel 0, ADC On
    MOVWF   ADCON0
    
    ; --- Timer Configuration ---
    BANKSEL OPTION_REG
    BCF     OPTION_REG, 7   ; Pull-ups Enabled
    BSF     OPTION_REG, 5   ; TMR0 Source: RA4/T0CKI (Counter Mode)
    BCF     OPTION_REG, 4   ; Rising Edge
    BSF     OPTION_REG, 3   ; Prescaler to WDT (1:1 for TMR0)
    
    BANKSEL T2CON
    MOVLW   00000110B       ; TMR2 On, Prescaler 1:16
    MOVWF   T2CON
    BANKSEL PR2
    MOVLW   255             ; Timer Period
    MOVWF   PR2

    ; --- UART Configuration (9600 Baud @ 4MHz) ---
    BANKSEL SPBRG
    MOVLW   25              ; 9600 Baud
    MOVWF   SPBRG
    BSF     TXSTA, 2        ; BRGH High Speed
    BCF     TXSTA, 4        ; Sync Mode Off
    BSF     TXSTA, 5        ; Transmit Enable
    BANKSEL RCSTA
    BSF     RCSTA, 7        ; Serial Port Enable
    BSF     RCSTA, 4        ; Continuous Receive Enable

    ; --- Variable Init ---
    BANKSEL PORTA
    CLRF    PORTA
    CLRF    PORTD
    CLRF    PORTB
    
    CLRF    DISPLAY_MODE
    CLRF    INT_COUNTER
    CLRF    SEC_FLAG
    CLRF    TWO_SEC_CNTR
    CLRF    INPUT_STATE
    CLRF    ISR_FLAG        ; Clear Software Interrupt Flag
    
    MOVLW   255
    MOVWF   LAST_KEY        ; Init Key Debounce
    
    ; Set Default Desired Temp
    MOVLW   25
    MOVWF   DESIRED_TEMP_INT
    CLRF    DESIRED_TEMP_FRC

    ; --- Interrupt Enable ---
    BSF     INTCON, 7       ; GIE (Global Interrupt Enable)
    BSF     INTCON, 6       ; PEIE (Peripheral Interrupt Enable)
    BANKSEL PIE1
    BSF     PIE1, 1         ; TMR2IE (Timer 2 Interrupt Enable)
    BSF     PIE1, 5         ; RCIE (UART Receive Interrupt Enable)

    BANKSEL PORTA
    GOTO    Main_Loop

; ==============================================================================
; MAIN LOOP
; Responsible: YUSUF GOC
; Function: Orchestrates sensor reading, logic control, and display updates.
; ==============================================================================
Main_Loop:
    CLRF    PCLATH

    ; 1. [R2.1.1-4, R2.1.1-5] Read Sensors
    CALL    Read_Sensors
    
    ; 2. [R2.1.1-2, R2.1.1-3] Control Logic (Heater/Cooler)
    CALL    Logic_Control
    
    ; 3. [R2.1.2] Check Keypad Input
    CALL    Keypad_Task
    
    ; 4. [R2.1.3] Prepare Data for Display
    CALL    Prepare_Display_Data
    
    ; --- Fan Speed Calculation (1 Second Interval) ---
    BTFSS   SEC_FLAG, 0     ; Check 1-sec flag from Timer ISR
    GOTO    Main_Loop
    
    BCF     SEC_FLAG, 0     ; Clear flag
    MOVF    TMR0, W         ; Read TMR0 count (Pulses per second)
    MOVWF   FAN_SPEED_RPS   ; [R2.1.1-5] Update Fan Speed Memory
    CLRF    TMR0            ; Reset Counter
    
    ; --- Display Mode Switching (2 Second Interval) ---
    ; [R2.1.3-1] Switch display content every 2 seconds
    INCF    TWO_SEC_CNTR, F
    MOVF    TWO_SEC_CNTR, W
    SUBLW   2
    BTFSS   STATUS, 2       ; If counter < 2, skip
    GOTO    Main_Loop
    CLRF    TWO_SEC_CNTR    ; Reset 2-sec counter
    
    ; Cycle Display Mode (0 -> 1 -> 2 -> 0)
    ; Mode 3 is reserved for Input, handled separately
    MOVF    DISPLAY_MODE, W
    XORLW   3               ; If Input Mode is active
    BTFSC   STATUS, 2
    GOTO    Main_Loop       ; Do not auto-switch during input
    
    INCF    DISPLAY_MODE, F
    MOVLW   3
    SUBWF   DISPLAY_MODE, W
    BTFSS   STATUS, 2       ; If Mode == 3, wrap to 0
    GOTO    Main_Loop
    CLRF    DISPLAY_MODE
    GOTO    Main_Loop

; ==============================================================================
; [R2.1.4] UART MODULE
; Responsible: YUSUF GOC
; Function: Handles bidirectional communication based on specified protocol.
; ==============================================================================
UART_Process:
    BANKSEL RCREG
    MOVF    RCREG, W        ; Read received data
    MOVWF   UART_RX_BUF     
    BANKSEL PORTA           

    ; [R2.1.4-1] Check Command Type
    BTFSS   UART_RX_BUF, 7  ; Bit 7 = 1 -> SET Command
    GOTO    UART_Check_Get  ; Bit 7 = 0 -> GET Command

    BTFSS   UART_RX_BUF, 6  ; Bit 6 determines Int/Frac
    GOTO    UART_Set_Frac   
    GOTO    UART_Set_Int    

UART_Set_Frac:
    MOVLW   00111111B       ; Mask 6-bit data
    ANDWF   UART_RX_BUF, W
    MOVWF   DESIRED_TEMP_FRC ; Update memory [R2.1.1-1]
    RETURN

UART_Set_Int:
    MOVLW   00111111B       ; Mask 6-bit data
    ANDWF   UART_RX_BUF, W
    MOVWF   DESIRED_TEMP_INT ; Update memory [R2.1.1-1]
    RETURN

UART_Check_Get:
    ; Protocol Matching
    MOVF    UART_RX_BUF, W
    XORLW   1
    BTFSC   STATUS, 2
    GOTO    Tx_Des_Frac

    MOVF    UART_RX_BUF, W
    XORLW   2
    BTFSC   STATUS, 2
    GOTO    Tx_Des_Int

    MOVF    UART_RX_BUF, W
    XORLW   3
    BTFSC   STATUS, 2
    GOTO    Tx_Amb_Frac

    MOVF    UART_RX_BUF, W
    XORLW   4
    BTFSC   STATUS, 2
    GOTO    Tx_Amb_Int

    MOVF    UART_RX_BUF, W
    XORLW   5
    BTFSC   STATUS, 2
    GOTO    Tx_Fan
    RETURN

; Response Handlers
Tx_Des_Frac:
    MOVF    DESIRED_TEMP_FRC, W
    GOTO    UART_Send_W
Tx_Des_Int:
    MOVF    DESIRED_TEMP_INT, W
    GOTO    UART_Send_W
Tx_Amb_Frac:
    MOVF    CURR_TEMP_FRC, W
    GOTO    UART_Send_W
Tx_Amb_Int:
    MOVF    CURR_TEMP_INT, W
    GOTO    UART_Send_W
Tx_Fan:
    MOVF    FAN_SPEED_RPS, W
    GOTO    UART_Send_W

UART_Send_W:
    BANKSEL TXREG
    MOVWF   TXREG           ; Write to Transmit Buffer
    BANKSEL TXSTA
Tx_Pending:
    BTFSS   TXSTA, 1        ; Wait for completion
    GOTO    Tx_Pending
    BANKSEL PORTA
    RETURN

; ==============================================================================
; [R2.1.3] DISPLAY MODULE (ISR DRIVEN)
; Responsible: EMINE ATMA
; Function: Multiplexes 4-digit 7-segment display.
; ==============================================================================
Display_Refresh_ISR:
    BANKSEL PORTA
    ; Turn off all digits (Common Anode/Cathode Control)
    BCF     PORTA, 1
    BCF     PORTA, 2
    BCF     PORTA, 3
    BCF     PORTA, 5
    BANKSEL PORTD
    CLRF    PORTD
    
    ; Determine active digit based on counter (0-3)
    MOVF    INT_COUNTER, W
    ANDLW   00000011B
    MOVWF   BCD_TEMP_L
    
    MOVF    BCD_TEMP_L, W
    XORLW   0
    BTFSC   STATUS, 2
    GOTO    Disp_D1
    MOVF    BCD_TEMP_L, W
    XORLW   1
    BTFSC   STATUS, 2
    GOTO    Disp_D2
    MOVF    BCD_TEMP_L, W
    XORLW   2
    BTFSC   STATUS, 2
    GOTO    Disp_D3
    GOTO    Disp_D4

Disp_D1:
    MOVF    DIGIT1_VAL, W
    CALL    GetSeg          ; Get segment code
    MOVWF   PORTD           ; Output to Segments
    BSF     PORTA, 1        ; Enable Digit 1
    GOTO    Disp_Done
Disp_D2:
    MOVF    DIGIT2_VAL, W
    CALL    GetSeg
    BTFSC   DOT_STATE, 0    ; Check if Dot is needed
    IORLW   10000000B       ; Add Decimal Point bit
    MOVWF   PORTD
    BSF     PORTA, 2        ; Enable Digit 2
    GOTO    Disp_Done
Disp_D3:
    MOVF    DIGIT3_VAL, W
    CALL    GetSeg
    MOVWF   PORTD
    BSF     PORTA, 3        ; Enable Digit 3
    GOTO    Disp_Done
Disp_D4:
    MOVF    DIGIT4_VAL, W
    MOVWF   PORTD           ; Note: Digit 4 might use raw segments for characters like 'F', 'C'
    BSF     PORTA, 5        ; Enable Digit 4
    GOTO    Disp_Done

Disp_Done:
    ; Update timing counter for 1-second flag
    INCF    INT_COUNTER, F
    MOVF    INT_COUNTER, W
    SUBLW   250             ; Approx 1 sec based on interrupt frequency
    BTFSS   STATUS, 2
    RETURN
    CLRF    INT_COUNTER
    BSF     SEC_FLAG, 0     ; Set 1-second flag
    RETURN

; ==============================================================================
; [R2.1.1] TEMPERATURE CONTROL MODULE
; Responsible: MUHAMMED MEHMET GOKCE
; Function: Reads ADC, converts to Temp, controls Heater/Fan.
; ==============================================================================
Read_Sensors:
    ; [R2.1.1-4] Read Ambient Temperature (ADC)
    BANKSEL ADCON0
    BSF     ADCON0, 2       ; Start Conversion
Wait_ADC:
    BTFSC   ADCON0, 2       ; Wait for Done
    GOTO    Wait_ADC
    BANKSEL ADRESL
    MOVF    ADRESL, W
    BANKSEL TEMP_ADC_L
    MOVWF   TEMP_ADC_L
    
    ; Calibration Offset (Simulated)
    DECF    TEMP_ADC_L, F
    
    BANKSEL ADRESH
    MOVF    ADRESH, W
    MOVWF   TEMP_ADC_H
    
    ; Convert ADC (10-bit) to Temp (LM35 Logic)
    ; Assuming Vref and Scaling results in: Temp = ADC / 2
    BCF     STATUS, 0
    RRF     TEMP_ADC_H, F
    RRF     TEMP_ADC_L, F
    MOVF    TEMP_ADC_L, W
    MOVWF   CURR_TEMP_INT   ; Store Integral Part
    
    ; Handle .5 degree fraction
    CLRF    CURR_TEMP_FRC
    BTFSS   STATUS, 0       ; Check Carry from Rotate
    RETURN
    
    MOVLW   5
    MOVWF   CURR_TEMP_FRC
    RETURN

Logic_Control:
    ; [R2.1.1-2, R2.1.1-3] Compare Ambient vs Desired
    BANKSEL PORTC
    MOVF    DESIRED_TEMP_INT, W
    SUBWF   CURR_TEMP_INT, W
    
    BTFSC   STATUS, 2       ; If Equal -> Heat (Hysteresis choice)
    GOTO    Turn_Heat_On
    BTFSS   STATUS, 0       ; If Ambient < Desired -> Heat
    GOTO    Turn_Heat_On
    GOTO    Turn_Cool_On    ; If Ambient > Desired -> Cool

Turn_Heat_On:
    BSF     PORTC, 0        ; Heater ON
    BCF     PORTC, 1        ; Cooler OFF
    BSF     SYSTEM_FLAGS, 1
    BCF     SYSTEM_FLAGS, 0
    RETURN
Turn_Cool_On:
    BCF     PORTC, 0        ; Heater OFF
    BSF     PORTC, 1        ; Cooler ON
    BCF     SYSTEM_FLAGS, 1
    BSF     SYSTEM_FLAGS, 0
    RETURN

; ==============================================================================
; DATA PREPARATION FOR DISPLAY
; Responsible: MUHAMMED MEHMET GOKCE
; ==============================================================================
Prepare_Display_Data:
    MOVF    DISPLAY_MODE, W
    XORLW   3               ; If Input Mode
    BTFSC   STATUS, 2
    RETURN                  ; Do nothing (Input logic handles display buffer)
    
    MOVF    DISPLAY_MODE, W
    XORLW   2               ; If Fan Mode
    BTFSC   STATUS, 2
    GOTO    Prep_Fan
    MOVF    DISPLAY_MODE, W
    XORLW   1               ; If Ambient Mode
    BTFSC   STATUS, 2
    GOTO    Prep_Amb
    
Prep_Des: 
    ; Show Desired Temp
    MOVF    DESIRED_TEMP_INT, W
    CALL    Util_BinToBCD
    BSF     DOT_STATE, 0    ; Enable Dot
    MOVF    DESIRED_TEMP_FRC, W
    MOVWF   DIGIT3_VAL
    MOVLW   00111001B ; 'C'
    MOVWF   DIGIT4_VAL
    RETURN
Prep_Amb:
    ; Show Ambient Temp
    MOVF    CURR_TEMP_INT, W
    CALL    Util_BinToBCD
    BSF     DOT_STATE, 0
    
    MOVF    CURR_TEMP_FRC, W
    MOVWF   DIGIT3_VAL
    
    MOVLW   01110111B ; 'A' (Ambient)
    MOVWF   DIGIT4_VAL
    RETURN
Prep_Fan:
    ; Show Fan Speed
    MOVF    FAN_SPEED_RPS, W
    CALL    Util_BinToBCD3  ; 3-digit conversion
    BCF     DOT_STATE, 0    ; Disable Dot
    MOVLW   01110001B ; 'F' (Fan)
    MOVWF   DIGIT4_VAL
    RETURN

; ==============================================================================
; [R2.1.2] KEYPAD MODULE logic
; Responsible: EMINE ATMA
; Function: Scans keypad, debounces, and executes Input State Machine.
; ==============================================================================
Keypad_Task:
    CALL    Key_Scan_Matrix
    MOVWF   KEY_PRESSED
    
    ; Debounce Logic
    MOVF    KEY_PRESSED, W
    XORLW   255             ; Check if No Key Pressed
    BTFSC   STATUS, 2
    GOTO    Key_Reset
    
    MOVF    KEY_PRESSED, W
    SUBWF   LAST_KEY, W     ; Check if same key held
    BTFSC   STATUS, 2
    RETURN
    
    CALL    Util_Delay      ; Debounce Delay
    CALL    Key_Scan_Matrix ; Re-scan
    XORLW   255
    BTFSC   STATUS, 2
    RETURN 
    
    MOVF    KEY_PRESSED, W
    MOVWF   LAST_KEY        ; Update Last Key
    GOTO    Key_Process

Key_Reset:
    MOVLW   255
    MOVWF   LAST_KEY
    RETURN

Key_Scan_Matrix:
    ; Column Scanning Algorithm
    BANKSEL PORTB
    MOVLW   00001111B 
    MOVWF   PORTB
    CALL    Util_ShortDelay
    
    ; Scan Column 1
    MOVLW   11111101B
    MOVWF   PORTB
    CALL    Util_ShortDelay
    BTFSS   PORTB, 4
    RETLW   1
    BTFSS   PORTB, 5
    RETLW   4
    BTFSS   PORTB, 6
    RETLW   7
    BTFSS   PORTB, 7
    RETLW   10 ; '*'
    
    ; Scan Column 2
    MOVLW   11111011B
    MOVWF   PORTB
    CALL    Util_ShortDelay
    BTFSS   PORTB, 4
    RETLW   2
    BTFSS   PORTB, 5
    RETLW   5
    BTFSS   PORTB, 6
    RETLW   8
    BTFSS   PORTB, 7
    RETLW   0
    
    ; Scan Column 3
    MOVLW   11110111B
    MOVWF   PORTB
    CALL    Util_ShortDelay
    BTFSS   PORTB, 4
    RETLW   3
    BTFSS   PORTB, 5
    RETLW   6
    BTFSS   PORTB, 6
    RETLW   9
    BTFSS   PORTB, 7
    RETLW   11 ; '#'
    
    ; Scan Column 4
    MOVLW   11111110B
    MOVWF   PORTB
    CALL    Util_ShortDelay
    BTFSS   PORTB, 4
    RETLW   12 ; 'A'
    BTFSS   PORTB, 5
    RETLW   13 ; 'B'
    BTFSS   PORTB, 6
    RETLW   14 ; 'C'
    BTFSS   PORTB, 7
    RETLW   15 ; 'D'
    
    RETLW   255 ; No Key Pressed

Key_Process:
    ; [R2.1.2-1] Check for 'A' Button Trigger
    MOVF    KEY_PRESSED, W
    XORLW   12        ; Code for 'A'
    BTFSC   STATUS, 2
    GOTO    Set_A_Flag  ; Trigger Software Interrupt
    
    ; Check if Input Mode Active
    MOVF    INPUT_STATE, W
    BTFSC   STATUS, 2
    RETURN              ; Not in input mode, ignore keys
    
    ; Digit Entry (0-9)
    MOVF    KEY_PRESSED, W
    SUBLW   9
    BTFSC   STATUS, 0
    GOTO    Inp_Digit
    
    ; Decimal Point Entry (*)
    MOVF    KEY_PRESSED, W
    XORLW   10        ; '*'
    BTFSC   STATUS, 2
    GOTO    Inp_Star
    
    ; Confirmation Entry (#)
    MOVF    KEY_PRESSED, W
    XORLW   11        ; '#'
    BTFSC   STATUS, 2
    GOTO    Inp_Enter
    RETURN

Set_A_Flag:
    BANKSEL ISR_FLAG
    BSF     ISR_FLAG, 0 ; Set Flag for ISR to detect
    RETURN

; --- INPUT STATE MACHINE ---
Inp_Digit:
    ; Handle digit input based on current state (Tens, Ones, Fraction)
    MOVF    INPUT_STATE, W
    XORLW   1
    BTFSC   STATUS, 2
    GOTO    St_Tens
    MOVF    INPUT_STATE, W
    XORLW   2
    BTFSC   STATUS, 2
    GOTO    St_Ones
    MOVF    INPUT_STATE, W
    XORLW   4
    BTFSC   STATUS, 2
    GOTO    St_Frac
    RETURN

St_Tens:
    MOVF    KEY_PRESSED, W
    MOVWF   DIGIT1_VAL      ; Update Display
    MOVWF   NEW_TEMP_INT    ; Save Tens
    MOVLW   2
    MOVWF   INPUT_STATE     ; Next State
    RETURN

St_Ones:
    MOVF    KEY_PRESSED, W
    MOVWF   DIGIT2_VAL      ; Update Display
    MOVF    DIGIT1_VAL, W
    MOVWF   NEW_TEMP_INT
    ; Calculate: (Tens * 10) + Ones
    ; Using bit shifts for X*10 = X*8 + X*2
    BCF     STATUS, 0      
    RLF     NEW_TEMP_INT, F
    MOVF    NEW_TEMP_INT, W
    MOVWF   BCD_TEMP_L
    BCF     STATUS, 0      
    RLF     NEW_TEMP_INT, F
    BCF     STATUS, 0      
    RLF     NEW_TEMP_INT, F
    MOVF    BCD_TEMP_L, W
    ADDWF   NEW_TEMP_INT, F
    
    MOVF    KEY_PRESSED, W
    ADDWF   NEW_TEMP_INT, F ; Add Ones
    MOVLW   3
    MOVWF   INPUT_STATE     ; Next State
    RETURN

Inp_Star:
    ; [R2.1.2-2] Decimal point entry
    MOVF    INPUT_STATE, W
    XORLW   2               ; Valid after Ones digit
    BTFSS   STATUS, 2
    GOTO    Check_St3       ; Or check alternate path
    MOVF    DIGIT1_VAL, W
    MOVWF   DIGIT2_VAL      ; Shift digits if entered as single digit
    CLRF    DIGIT1_VAL
    MOVWF   NEW_TEMP_INT
    GOTO    Do_Dot
Check_St3:
    MOVF    INPUT_STATE, W
    XORLW   3
    BTFSS   STATUS, 2
    RETURN
Do_Dot:
    BSF     DOT_STATE, 0    ; Turn on Dot
    MOVLW   4
    MOVWF   INPUT_STATE     ; Next State
    RETURN

St_Frac:
    MOVF    KEY_PRESSED, W
    MOVWF   DIGIT3_VAL      ; Update Display
    MOVWF   NEW_TEMP_FRC    ; Save Fraction
    MOVLW   5
    MOVWF   INPUT_STATE     ; Ready for Enter
    RETURN

Inp_Enter:
    ; [R2.1.2-2] Enter Confirmation
    MOVF    INPUT_STATE, W
    XORLW   5
    BTFSS   STATUS, 2
    RETURN
    
    ; [R2.1.2-3] Range Validation (10.0 - 50.0)
    MOVF    NEW_TEMP_INT, W
    SUBLW   9
    BTFSC   STATUS, 0       ; If Temp <= 9 -> Cancel
    GOTO    Inp_Cancel
    MOVF    NEW_TEMP_INT, W
    SUBLW   50
    BTFSS   STATUS, 0       ; If Temp > 50 -> Cancel
    GOTO    Inp_Cancel
    
    ; [R2.1.2-4] Save Valid Value to Memory
    MOVF    NEW_TEMP_INT, W
    MOVWF   DESIRED_TEMP_INT
    MOVF    NEW_TEMP_FRC, W
    MOVWF   DESIRED_TEMP_FRC
    
Inp_Cancel:
    CLRF    INPUT_STATE     ; Exit Input Mode
    CLRF    DISPLAY_MODE    ; Return to Default Display
    RETURN

; ==============================================================================
; UTILITY FUNCTIONS
; Responsible: EMINE ATMA
; ==============================================================================
Util_ShortDelay:
    MOVLW   50
    MOVWF   COLUMN_DELAY
D_Loop_S:
    DECFSZ  COLUMN_DELAY, F
    GOTO    D_Loop_S
    RETURN

Util_Delay:
    MOVLW   200
    MOVWF   DEBOUNCE_CNT
D_L1:
    MOVLW   200
    MOVWF   DELAY_VAR
D_L2:
    DECFSZ  DELAY_VAR, F
    GOTO    D_L2
    DECFSZ  DEBOUNCE_CNT, F
    GOTO    D_L1
    RETURN

Util_BinToBCD:
    ; Converts Binary (0-99) to BCD Digits
    CLRF    CALC_D1
    MOVWF   BCD_TEMP_L
L_BCD:
    MOVLW   10
    SUBWF   BCD_TEMP_L, W
    BTFSS   STATUS, 0      
    GOTO    End_BCD
    MOVWF   BCD_TEMP_L
    INCF    CALC_D1, F
    GOTO    L_BCD
End_BCD:
    MOVF    CALC_D1, W
    MOVWF   DIGIT1_VAL
    MOVF    BCD_TEMP_L, W
    MOVWF   DIGIT2_VAL
    RETURN

Util_BinToBCD3:
    ; Converts Binary (0-255) to 3 BCD Digits
    CLRF    DIGIT1_VAL
    CLRF    DIGIT2_VAL
    CLRF    DIGIT3_VAL
    MOVWF   BCD_TEMP_L
H_L:
    MOVLW   100
    SUBWF   BCD_TEMP_L, W
    BTFSS   STATUS, 0
    GOTO    T_L
    MOVWF   BCD_TEMP_L
    INCF    DIGIT1_VAL, F
    GOTO    H_L
T_L:
    MOVLW   10
    SUBWF   BCD_TEMP_L, W
    BTFSS   STATUS, 0
    GOTO    O_L
    MOVWF   BCD_TEMP_L
    INCF    DIGIT2_VAL, F
    GOTO    T_L
O_L:
    MOVF    BCD_TEMP_L, W
    MOVWF   DIGIT3_VAL
    RETURN

    END