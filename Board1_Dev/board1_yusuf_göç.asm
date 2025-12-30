;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...