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

;...
;...
;...
;...
;...
