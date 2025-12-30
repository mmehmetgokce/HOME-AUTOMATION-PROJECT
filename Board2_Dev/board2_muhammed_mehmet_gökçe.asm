;...
;...
;...
;...
;...

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

;...
;...
;...
;...
;...
