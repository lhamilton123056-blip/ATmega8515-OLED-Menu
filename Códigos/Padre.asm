.include "m8515def.inc"

; ATmega8515 - ver TIMER1_CS segun la velocidad real del reloj
; MENU EN DOS OLED SSD1306
;
; PB7 = SCK
; PB6 = MISO
; PB5 = MOSI
; PB4 = SS
; PB3 = RES
; PB2 = DC
; PB1 = CS OLED 2
; PB0 = CS OLED 1

; RELOJ DEL MICRO -> prescaler del Timer1 para 1 us por tick
;   micro a 1 MHz (oscilador interno de fabrica): (1<<CS10)  sin prescaler
;   micro a 8 MHz (fusibles/cristal a 8 MHz):     (1<<CS11)  clk/8
.equ TIMER1_CS = (1<<CS10)

;
; COMUNICACION CON EL ATmega8515 ESCLAVO (UART, 9600 baudios, 8N1)
;   PD1 (TXD) de este micro  ->  PD0 (RXD) del esclavo
;   GND comun entre los dos micros
;
; Baudios con U2X=1:
;   micro a 1 MHz -> UBRR = 12
;   micro a 8 MHz -> UBRR = 103
.equ UBRR_9600 = 12

; CODIGO DEL BOTON OK DEL CONTROL (confirmalo con Diagnostico_IR)
.equ IR_CMD_OK = 0x1C

.def temp = r16
.def dato = r17
.def contador = r18

.def seleccion = r20
.def indice    = r19

.org 0x0000
    rjmp INICIO

.org OVF0addr
    rjmp ISR_TIMER0

.org 0x0020

;================================
; INICIO
;================================
INICIO:
    ; STACK
    ldi temp, HIGH(RAMEND)
    out SPH, temp
    ldi temp, LOW(RAMEND)
    out SPL, temp

    ; SELECCION INICIAL
    ldi seleccion, 1

    ; Estado de ejercicios locales del padre (5 y 9)
    clr r8                       ; 0=menu, 1=ejercicio local activo
    clr r9                       ; 1=salir del ejercicio local al pulsar OK
    clr r2                       ; buffer de segmentos digito 0
    clr r3                       ; buffer de segmentos digito 1
    clr r4                       ; buffer de segmentos digito 2
    clr r5                       ; buffer de segmentos digito 3
    clr r6                       ; indice de multiplexado (lo usa ISR Timer0)

    ; Display 3661AS-1 545 del padre: PA segmentos, PC0-PC3 transistores
    ldi temp, 0xFF
    out DDRA, temp
    ldi temp, 0x0F
    out DDRC, temp
    clr temp
    out PORTA, temp
    out PORTC, temp

    ; PD3 = pulsador compartido de los ejercicios 5 y 9
    cbi DDRD, 3
    sbi PORTD, 3

    ; PUERTOS
    ldi temp, 0b10111111
    out DDRB, temp

    ldi temp, 0b00011011
    out PORTB, temp

    ; RECEPTOR INFRARROJO
    cbi DDRD, 2
    sbi PORTD, 2

    ; UART: 9600 8N1, solo transmision
    ldi temp, (1<<U2X)
    out UCSRA, temp
    clr temp
    out UBRRH, temp
    ldi temp, UBRR_9600
    out UBRRL, temp
    ldi temp, (1<<TXEN)
    out UCSRB, temp
    ldi temp, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, temp

    ; TIMER1: 1 microsegundo por incremento
    ldi temp, TIMER1_CS
    out TCCR1B, temp

    ; SPI MASTER
    ldi temp, (1<<SPE)|(1<<MSTR)|(1<<SPR0)
    out SPCR, temp

    ; RESET
    rcall OLED_RESET

    ; INICIALIZAR OLED 1
    cbi PORTB, 0
    rcall OLED_INIT
    rcall OLED_LIMPIAR
    sbi PORTB, 0

    ; INICIALIZAR OLED 2
    cbi PORTB, 1
    rcall OLED_INIT
    rcall OLED_LIMPIAR
    sbi PORTB, 1

    ; MOSTRAR MENU OLED 1
    cbi PORTB, 0
    rcall MENU_SUPERIOR
    sbi PORTB, 0

    ; MOSTRAR MENU OLED 2
    cbi PORTB, 1
    rcall MENU_INFERIOR
    sbi PORTB, 1

    ; Timer0: refresco continuo del display de cuatro digitos.
    ; A 1 MHz y prescaler /8: overflow cada ~2.048 ms.
    clr temp
    out TCNT0, temp
    ldi temp, (1<<CS01)
    out TCCR0, temp
    ldi temp, (1<<TOIE0)
    out TIMSK, temp
    sei

BUCLE:
    rcall IR_RECIBIR
    rjmp BUCLE

;================================
; RECEPTOR INFRARROJO NEC
; PD2 = SALIDA DEL RECEPTOR
; TIMER1 = 1 us por incremento
;================================

IR_RECIBIR:

    ; Esperar inicio de se al
    rcall IR_ESPERAR_BAJO
    brcc IR_INICIO_DETECTADO
    rjmp IR_SALIR

IR_INICIO_DETECTADO:

    ; Medir pulso inicial bajo (~9 ms)
    rcall IR_ESPERAR_ALTO
    brcc IR_PULSO_INICIAL_OK
    rjmp IR_SALIR

IR_PULSO_INICIAL_OK:

    in dato, TCNT1L
    in temp, TCNT1H

    ; Validar entre 6 y 12 ms
    cpi temp, 0x18
    brsh IR_PULSO_MIN_OK
    rjmp IR_SALIR

IR_PULSO_MIN_OK:

    cpi temp, 0x30
    brlo IR_PULSO_MAX_OK
    rjmp IR_SALIR

IR_PULSO_MAX_OK:

    ; Medir espacio alto inicial (~4.5 ms)
    rcall IR_ESPERAR_BAJO
    brcc IR_ESPACIO_INICIAL_OK
    rjmp IR_SALIR

IR_ESPACIO_INICIAL_OK:

    in dato, TCNT1L
    in temp, TCNT1H

    ; Validar entre 3 y 6 ms
    cpi temp, 0x0C
    brsh IR_ESPACIO_MIN_OK
    rjmp IR_SALIR

IR_ESPACIO_MIN_OK:

    cpi temp, 0x18
    brlo IR_ESPACIO_MAX_OK
    rjmp IR_SALIR

IR_ESPACIO_MAX_OK:

    ; Limpiar los 32 bits recibidos
    clr r10
    clr r11
    clr r12
    clr r13

    ldi temp, 32
    mov r15, temp

IR_LEER_BITS:

    ; Medir pulso bajo del bit
    rcall IR_ESPERAR_ALTO
    brcc IR_MARCA_BIT_OK
    rjmp IR_SALIR

IR_MARCA_BIT_OK:

    in dato, TCNT1L
    in temp, TCNT1H

    ; Validar duraci n de la marca
    cpi temp, 1
    brsh IR_MARCA_MIN_OK
    rjmp IR_SALIR

IR_MARCA_MIN_OK:

    cpi temp, 6
    brlo IR_MARCA_MAX_OK
    rjmp IR_SALIR

IR_MARCA_MAX_OK:

    ; Medir espacio alto del bit
    rcall IR_ESPERAR_BAJO
    brcc IR_ESPACIO_BIT_OK
    rjmp IR_SALIR

IR_ESPACIO_BIT_OK:

    in dato, TCNT1L
    in temp, TCNT1H

    ; Espacio corto = bit 0
    cpi temp, 4
    brlo IR_BIT_CERO

    ; Espacio largo = bit 1
    cpi temp, 0x0B
    brlo IR_BIT_UNO
    rjmp IR_SALIR

IR_BIT_UNO:

    sec
    rjmp IR_GUARDAR_BIT

IR_BIT_CERO:

    clc

IR_GUARDAR_BIT:

    ; Guardar bit recibido
    ror r13
    ror r12
    ror r11
    ror r10

    dec r15
    brne IR_LEER_BITS

    ; Trama completa
    rjmp IR_VALIDAR

;================================
; VALIDAR DIRECCION Y COMANDO
;================================

IR_VALIDAR:

    ; Direcci n = 0x00
    tst r10
    breq IR_VALIDAR_DIR
    rjmp IR_SALIR

IR_VALIDAR_DIR:

    ; Direcci n invertida = 0xFF
    ; (cpi solo acepta r16-r31, por eso se pasa por temp)
    mov temp, r11
    cpi temp, 0xFF
    breq IR_VALIDAR_INV
    rjmp IR_SALIR

IR_VALIDAR_INV:

    ; Comprobar comando invertido
    mov r14, r12
    com r14
    cp r14, r13
    breq IR_VALIDAR_COMANDO
    rjmp IR_SALIR

IR_VALIDAR_COMANDO:

    mov temp, r12

    ; ARRIBA = 0x18
    cpi temp, 0x18
    breq IR_ARRIBA

    ; ABAJO = 0x52
    cpi temp, 0x52
    breq IR_ABAJO

    ; OK
    cpi temp, IR_CMD_OK
    breq IR_OK

    rjmp IR_SALIR

;================================
; OK: ENVIAR AL ESCLAVO EL EJERCICIO SELECCIONADO (1-9)
;================================

IR_OK:
    ; Si un ejercicio local esta activo, OK regresa al menu.
    tst r8
    breq IR_OK_DESDE_MENU
    ldi temp, 1
    mov r9, temp
    rjmp IR_SALIR

IR_OK_DESDE_MENU:
    ; Ejercicios 5 y 9 se ejecutan en el propio maestro.
    cpi seleccion, 5
    breq IR_OK_EJ5
    cpi seleccion, 9
    breq IR_OK_EJ9

    ; Los demas ejercicios se envian al esclavo.
    mov dato, seleccion
    rcall UART_ENVIA
    rjmp IR_SALIR

IR_OK_EJ5:
    rcall PADRE_EJERCICIO_5
    rjmp IR_SALIR

IR_OK_EJ9:
    rcall PADRE_EJERCICIO_9
    rjmp IR_SALIR

;================================
; MOVER SELECCION HACIA ARRIBA
;================================

IR_ARRIBA:

    dec seleccion
    brne IR_ACTUALIZAR

    ldi seleccion, 9
    rjmp IR_ACTUALIZAR

;================================
; MOVER SELECCION HACIA ABAJO
;================================

IR_ABAJO:

    inc seleccion
    cpi seleccion, 10
    brlo IR_ACTUALIZAR

    ldi seleccion, 1

;================================
; ACTUALIZAR LAS DOS OLED
;================================

IR_ACTUALIZAR:

    ; OLED 1: ejercicios 1-5
    cbi PORTB, 0
    rcall MENU_SUPERIOR
    sbi PORTB, 0

    ; OLED 2: ejercicios 6-9
    cbi PORTB, 1
    rcall MENU_INFERIOR
    sbi PORTB, 1

IR_SALIR:
    ret

;================================
; ESPERAR HASTA QUE PD2 SEA 0
;================================

IR_ESPERAR_BAJO:

    clr r14
    out TCNT1H, r14
    out TCNT1L, r14

IR_BAJO_LOOP:

    sbic PIND, 2
    rjmp IR_BAJO_TIMEOUT

    clc
    ret

IR_BAJO_TIMEOUT:

    in dato, TCNT1L
    in temp, TCNT1H
    cpi temp, 0x4E
    brlo IR_BAJO_LOOP

    sec
    ret

;================================
; ESPERAR HASTA QUE PD2 SEA 1
;================================

IR_ESPERAR_ALTO:

    clr r14
    out TCNT1H, r14
    out TCNT1L, r14

IR_ALTO_LOOP:

    sbis PIND, 2
    rjmp IR_ALTO_TIMEOUT

    clc
    ret

IR_ALTO_TIMEOUT:

    in dato, TCNT1L
    in temp, TCNT1H
    cpi temp, 0x4E
    brlo IR_ALTO_LOOP

    sec
    ret

;================================
; UART: enviar el byte que esta en dato
;================================
UART_ENVIA:
    sbis UCSRA, UDRE
    rjmp UART_ENVIA
    out UDR, dato
    ret

;================================
; RESET
;================================
OLED_RESET:
    cbi PORTB, 3
    rcall RETARDO
    sbi PORTB, 3
    rcall RETARDO
    ret

;================================
; INICIALIZACION SSD1306
;================================
OLED_INIT:
    cbi PORTB, 2

    ldi dato, 0xAE
    rcall SPI_ENVIA
    ldi dato, 0xD5
    rcall SPI_ENVIA
    ldi dato, 0x80
    rcall SPI_ENVIA
    ldi dato, 0xA8
    rcall SPI_ENVIA
    ldi dato, 0x3F
    rcall SPI_ENVIA
    ldi dato, 0xD3
    rcall SPI_ENVIA
    ldi dato, 0x00
    rcall SPI_ENVIA
    ldi dato, 0x40
    rcall SPI_ENVIA
    ldi dato, 0x8D
    rcall SPI_ENVIA
    ldi dato, 0x14
    rcall SPI_ENVIA
    ldi dato, 0x20
    rcall SPI_ENVIA
    ldi dato, 0x00
    rcall SPI_ENVIA
    ldi dato, 0xA1
    rcall SPI_ENVIA
    ldi dato, 0xC8
    rcall SPI_ENVIA
    ldi dato, 0xDA
    rcall SPI_ENVIA
    ldi dato, 0x12
    rcall SPI_ENVIA
    ldi dato, 0x81
    rcall SPI_ENVIA
    ldi dato, 0x7F
    rcall SPI_ENVIA
    ldi dato, 0xD9
    rcall SPI_ENVIA
    ldi dato, 0xF1
    rcall SPI_ENVIA
    ldi dato, 0xDB
    rcall SPI_ENVIA
    ldi dato, 0x40
    rcall SPI_ENVIA
    ldi dato, 0xA4
    rcall SPI_ENVIA
    ldi dato, 0xA6
    rcall SPI_ENVIA
    ldi dato, 0xAF
    rcall SPI_ENVIA

    ret

;================================
; LIMPIAR OLED COMPLETA
;================================
OLED_LIMPIAR:
    cbi PORTB, 2

    ; Columnas 0-127
    ldi dato, 0x21
    rcall SPI_ENVIA
    ldi dato, 0x00
    rcall SPI_ENVIA
    ldi dato, 0x7F
    rcall SPI_ENVIA

    ; Paginas 0-7
    ldi dato, 0x22
    rcall SPI_ENVIA
    ldi dato, 0x00
    rcall SPI_ENVIA
    ldi dato, 0x07
    rcall SPI_ENVIA

    ; Enviar 1024 bytes en cero
    sbi PORTB, 2
    ldi contador, 8

LIMPIAR_PAGINA:
    ldi r19, 128

LIMPIAR_COLUMNA:
    ldi dato, 0x00
    rcall SPI_ENVIA
    dec r19
    brne LIMPIAR_COLUMNA

    dec contador
    brne LIMPIAR_PAGINA

    ret

;================================
; MENU SUPERIOR: EJERCICIOS 1-5
;================================
MENU_SUPERIOR:

    ldi r23, 0
    ldi indice, 1
    ldi XL, low(2*TXT_1)
    ldi XH, high(2*TXT_1)
    rcall DIBUJAR_TEXTO

    ldi r23, 1
    ldi indice, 2
    ldi XL, low(2*TXT_2)
    ldi XH, high(2*TXT_2)
    rcall DIBUJAR_TEXTO

    ldi r23, 2
    ldi indice, 3
    ldi XL, low(2*TXT_3)
    ldi XH, high(2*TXT_3)
    rcall DIBUJAR_TEXTO

    ldi r23, 3
    ldi indice, 4
    ldi XL, low(2*TXT_4)
    ldi XH, high(2*TXT_4)
    rcall DIBUJAR_TEXTO

    ldi r23, 4
    ldi indice, 5
    ldi XL, low(2*TXT_5)
    ldi XH, high(2*TXT_5)
    rcall DIBUJAR_TEXTO

    ret

;================================
; MENU INFERIOR: EJERCICIOS 6-9
;================================
MENU_INFERIOR:

    ldi r23, 0
    ldi indice, 6
    ldi XL, low(2*TXT_6)
    ldi XH, high(2*TXT_6)
    rcall DIBUJAR_TEXTO

    ldi r23, 1
    ldi indice, 7
    ldi XL, low(2*TXT_7)
    ldi XH, high(2*TXT_7)
    rcall DIBUJAR_TEXTO

    ldi r23, 2
    ldi indice, 8
    ldi XL, low(2*TXT_8)
    ldi XH, high(2*TXT_8)
    rcall DIBUJAR_TEXTO

    ldi r23, 3
    ldi indice, 9
    ldi XL, low(2*TXT_9)
    ldi XH, high(2*TXT_9)
    rcall DIBUJAR_TEXTO

    ret

;================================
; DIBUJAR TEXTO CON SELECCION
;================================
DIBUJAR_TEXTO:

    cbi PORTB, 2

    ; Columnas 0-127
    ldi dato, 0x21
    rcall SPI_ENVIA
    ldi dato, 0x00
    rcall SPI_ENVIA
    ldi dato, 0x7F
    rcall SPI_ENVIA

    ; Pagina correspondiente
    ldi dato, 0x22
    rcall SPI_ENVIA

    mov dato, r23
    rcall SPI_ENVIA

    mov dato, r23
    rcall SPI_ENVIA

    sbi PORTB, 2

    ldi r25, 128

SIGUIENTE_CARACTER:

    movw ZL, XL
    lpm
    mov r22, r0
    adiw XL, 1

    tst r22
    breq FIN_TEXTO

    rcall OBTENER_GLYPH

    ldi r24, 5

DIBUJAR_GLYPH:

    lpm
    mov dato, r0

    ; SI ESTA SELECCIONADO, INVERTIR LETRA
    cp indice, seleccion
    brne GLYPH_NORMAL

    ldi r21, 0x7F
    eor dato, r21

GLYPH_NORMAL:

    ori dato, 0x80
    rcall OLED_DATO
    adiw ZL, 1

    dec r25
    dec r24
    brne DIBUJAR_GLYPH

    ; ESPACIO ENTRE LETRAS
    cp indice, seleccion
    brne ESPACIO_NORMAL

    ldi dato, 0xFF
    rjmp ENVIAR_ESPACIO

ESPACIO_NORMAL:
    ldi dato, 0x80

ENVIAR_ESPACIO:
    rcall OLED_DATO
    dec r25

    rjmp SIGUIENTE_CARACTER

FIN_TEXTO:

    ; RELLENAR EL RESTO DE LA FILA
    cp indice, seleccion
    brne RELLENO_NORMAL

    ldi dato, 0xFF
    rjmp RELLENAR_LINEA

RELLENO_NORMAL:
    ldi dato, 0x80

RELLENAR_LINEA:
    rcall OLED_DATO
    dec r25
    brne RELLENAR_LINEA

    ret

;================================
; BUSCAR GLIFO
; Caracter recibido en r22
; Direccion devuelta en Z
;================================
OBTENER_GLYPH:

    cpi r22, ' '
    breq G_SPACE

    cpi r22, '.'
    breq G_DOT

    cpi r22, '-'
    breq G_DASH

    cpi r22, '1'
    breq G_1
    cpi r22, '2'
    breq G_2
    cpi r22, '3'
    breq G_3
    cpi r22, '4'
    breq G_4
    cpi r22, '5'
    breq G_5
    cpi r22, '6'
    breq G_6
    cpi r22, '7'
    breq G_7
    cpi r22, '8'
    breq G_8
    cpi r22, '9'
    breq G_9

    cpi r22, 'E'
    breq G_E
    cpi r22, 'J'
    breq G_J
    cpi r22, 'R'
    breq G_R
    cpi r22, 'C'
    breq G_C
    cpi r22, 'I'
    breq G_I
    cpi r22, 'O'
    breq G_O
    cpi r22, 'S'
    breq G_S

    rjmp G_SPACE

G_SPACE:
    ldi ZL, low(2*GL_SPACE)
    ldi ZH, high(2*GL_SPACE)
    ret

G_DOT:
    ldi ZL, low(2*GL_DOT)
    ldi ZH, high(2*GL_DOT)
    ret

G_DASH:
    ldi ZL, low(2*GL_DASH)
    ldi ZH, high(2*GL_DASH)
    ret

G_1:
    ldi ZL, low(2*GL_1)
    ldi ZH, high(2*GL_1)
    ret
G_2:
    ldi ZL, low(2*GL_2)
    ldi ZH, high(2*GL_2)
    ret
G_3:
    ldi ZL, low(2*GL_3)
    ldi ZH, high(2*GL_3)
    ret
G_4:
    ldi ZL, low(2*GL_4)
    ldi ZH, high(2*GL_4)
    ret
G_5:
    ldi ZL, low(2*GL_5)
    ldi ZH, high(2*GL_5)
    ret
G_6:
    ldi ZL, low(2*GL_6)
    ldi ZH, high(2*GL_6)
    ret
G_7:
    ldi ZL, low(2*GL_7)
    ldi ZH, high(2*GL_7)
    ret
G_8:
    ldi ZL, low(2*GL_8)
    ldi ZH, high(2*GL_8)
    ret
G_9:
    ldi ZL, low(2*GL_9)
    ldi ZH, high(2*GL_9)
    ret

G_E:
    ldi ZL, low(2*GL_E)
    ldi ZH, high(2*GL_E)
    ret
G_J:
    ldi ZL, low(2*GL_J)
    ldi ZH, high(2*GL_J)
    ret
G_R:
    ldi ZL, low(2*GL_R)
    ldi ZH, high(2*GL_R)
    ret
G_C:
    ldi ZL, low(2*GL_C)
    ldi ZH, high(2*GL_C)
    ret
G_I:
    ldi ZL, low(2*GL_I)
    ldi ZH, high(2*GL_I)
    ret
G_O:
    ldi ZL, low(2*GL_O)
    ldi ZH, high(2*GL_O)
    ret
G_S:
    ldi ZL, low(2*GL_S)
    ldi ZH, high(2*GL_S)
    ret

;================================
; COMANDOS Y DATOS OLED
;================================
OLED_COMANDO:
    cbi PORTB, 2
    rcall SPI_ENVIA
    sbi PORTB, 2
    ret

OLED_DATO:
    sbi PORTB, 2
    rcall SPI_ENVIA
    ret

;================================
; SPI
;================================
SPI_ENVIA:
    out SPDR, dato

ESPERA_SPI:
    in temp, SPSR
    sbrs temp, SPIF
    rjmp ESPERA_SPI
    ret

;================================
; RETARDO
;================================
RETARDO:
    ldi r21, 255
RET1:
    ldi r22, 255
RET2:
    dec r22
    brne RET2
    dec r21
    brne RET1
    ret

;================================
; CADENAS DEL MENU
;================================

;====================================================================
; EJERCICIOS LOCALES DEL MAESTRO: 5 Y 9
; Display 3661AS-1 545 compartido:
;   PA0..PA7 = segmentos (patrones de CATODO COMUN)
;   PC0..PC3 = seleccion de digitos por los cuatro 2N2222A
;   PD3 = pulsador: velocidad en E5 / incrementar numero en E9
; Timer0 refresca los cuatro digitos mientras el menu IR sigue activo.
;====================================================================

PADRE_EJERCICIO_5:
    ldi temp, 1
    mov r8, temp                 ; ejercicio local activo
    clr r9                       ; bandera de salida
    clr r28                      ; unidades 0..9
    clr r29                      ; decenas 0..9
    ldi temp, 1
    mov r7, temp                 ; velocidad 1..5
    rcall PADRE_ACTUALIZAR_E5

PADRE_EJ5_CICLO:
    rcall IR_RECIBIR             ; Timer0 mantiene el display mientras espera IR
    tst r9
    breq PADRE_EJ5_CONTINUAR
    rjmp PADRE_FIN_LOCAL
PADRE_EJ5_CONTINUAR:

    ; Boton PD3 cambia velocidad
    sbis PIND, 3
    rcall PADRE_EJ5_BOTON
    tst r9
    breq PADRE_EJ5_CONTINUAR_BOTON
    rjmp PADRE_FIN_LOCAL
PADRE_EJ5_CONTINUAR_BOTON:

    rcall PADRE_RETARDO_VELOCIDAD
    tst r9
    breq PADRE_EJ5_AVANZAR
    rjmp PADRE_FIN_LOCAL
PADRE_EJ5_AVANZAR:
    inc r28
    cpi r28, 10
    brlo PADRE_EJ5_ACTUALIZAR
    clr r28
    inc r29
    cpi r29, 10
    brlo PADRE_EJ5_ACTUALIZAR
    clr r29
PADRE_EJ5_ACTUALIZAR:
    rcall PADRE_ACTUALIZAR_E5
    rjmp PADRE_EJ5_CICLO

PADRE_ACTUALIZAR_E5:
    ; PC0 y PC1 quedan en blanco; PC2=decenas, PC3=unidades.
    clr r2
    clr r3
    mov r24, r29
    rcall PADRE_CONVERTIR
    mov r4, r16
    mov r24, r28
    rcall PADRE_CONVERTIR
    mov r5, r16
    ret

PADRE_EJ5_BOTON:
    ldi r18, 30
PADRE_EJ5_ANTI1:
    ldi r19, 255
PADRE_EJ5_ANTI2:
    dec r19
    brne PADRE_EJ5_ANTI2
    dec r18
    brne PADRE_EJ5_ANTI1
    sbis PIND, 3
    rjmp PADRE_EJ5_BOTON_VALIDO
    ret
PADRE_EJ5_BOTON_VALIDO:
    inc r7
    mov temp, r7
    cpi temp, 6
    brlo PADRE_EJ5_ESPERAR_LIBERAR
    ldi temp, 1
    mov r7, temp
PADRE_EJ5_ESPERAR_LIBERAR:
    sbis PIND, 3
    rjmp PADRE_EJ5_ESPERAR_LIBERAR
    ret

PADRE_EJERCICIO_9:
    ldi temp, 1
    mov r8, temp
    clr r9
    clr r28                      ; numero 0..9
    rcall PADRE_ACTUALIZAR_E9

PADRE_EJ9_CICLO:
    rcall IR_RECIBIR
    tst r9
    breq PADRE_EJ9_CONTINUAR
    rjmp PADRE_FIN_LOCAL
PADRE_EJ9_CONTINUAR:
    sbis PIND, 3
    rcall PADRE_EJ9_BOTON
    tst r9
    breq PADRE_EJ9_CONTINUAR_BOTON
    rjmp PADRE_FIN_LOCAL
PADRE_EJ9_CONTINUAR_BOTON:
    rjmp PADRE_EJ9_CICLO

PADRE_ACTUALIZAR_E9:
    mov r24, r28
    rcall PADRE_CONVERTIR
    mov r2, r16
    mov r3, r16
    mov r4, r16
    mov r5, r16
    ret

PADRE_EJ9_BOTON:
    ldi r18, 30
PADRE_EJ9_ANTI1:
    ldi r19, 255
PADRE_EJ9_ANTI2:
    dec r19
    brne PADRE_EJ9_ANTI2
    dec r18
    brne PADRE_EJ9_ANTI1
    sbis PIND, 3
    rjmp PADRE_EJ9_BOTON_VALIDO
    ret
PADRE_EJ9_BOTON_VALIDO:
    inc r28
    cpi r28, 10
    brlo PADRE_EJ9_ACTUALIZAR
    clr r28
PADRE_EJ9_ACTUALIZAR:
    rcall PADRE_ACTUALIZAR_E9
PADRE_EJ9_ESPERAR_LIBERAR:
    sbis PIND, 3
    rjmp PADRE_EJ9_ESPERAR_LIBERAR
    ret

PADRE_FIN_LOCAL:
    clr r8
    clr r9
    clr r2
    clr r3
    clr r4
    clr r5
    clr temp
    out PORTA, temp
    out PORTC, temp
    ret

; Retardo de velocidad para el conteo 00..99.
; Nivel 1 lento -> nivel 5 rapido; el IR se revisa en cada vuelta
; principal, y el refresco del display ocurre por interrupcion.
PADRE_RETARDO_VELOCIDAD:
    ; Cada consulta IR sin trama tarda ~20 ms. De esta forma el
    ; display sigue multiplexandose y el control remoto se atiende
    ; continuamente incluso durante el conteo.
    mov temp, r7
    cpi temp, 1
    breq PADRE_RET_P10
    cpi temp, 2
    breq PADRE_RET_P7
    cpi temp, 3
    breq PADRE_RET_P4
    cpi temp, 4
    breq PADRE_RET_P2
    ldi temp, 1
    mov r1, temp
    rjmp PADRE_RET_POLL
PADRE_RET_P10:
    ldi temp, 10
    mov r1, temp
    rjmp PADRE_RET_POLL
PADRE_RET_P7:
    ldi temp, 7
    mov r1, temp
    rjmp PADRE_RET_POLL
PADRE_RET_P4:
    ldi temp, 4
    mov r1, temp
    rjmp PADRE_RET_POLL
PADRE_RET_P2:
    ldi temp, 2
    mov r1, temp
PADRE_RET_POLL:
    rcall IR_RECIBIR
    tst r9
    brne PADRE_RET_FIN
    sbis PIND, 3
    rcall PADRE_EJ5_BOTON
    tst r9
    brne PADRE_RET_FIN
    dec r1
    brne PADRE_RET_POLL
PADRE_RET_FIN:
    ret

; Entrada r24=0..9; salida r16=patron de catodo comun.
PADRE_CONVERTIR:
    cpi r24, 0
    breq PADRE_PAT_0
    cpi r24, 1
    breq PADRE_PAT_1
    cpi r24, 2
    breq PADRE_PAT_2
    cpi r24, 3
    breq PADRE_PAT_3
    cpi r24, 4
    breq PADRE_PAT_4
    cpi r24, 5
    breq PADRE_PAT_5
    cpi r24, 6
    breq PADRE_PAT_6
    cpi r24, 7
    breq PADRE_PAT_7
    cpi r24, 8
    breq PADRE_PAT_8
    ldi r16, 0x6F
    ret
PADRE_PAT_0: ldi r16, 0x3F
    ret
PADRE_PAT_1: ldi r16, 0x06
    ret
PADRE_PAT_2: ldi r16, 0x5B
    ret
PADRE_PAT_3: ldi r16, 0x4F
    ret
PADRE_PAT_4: ldi r16, 0x66
    ret
PADRE_PAT_5: ldi r16, 0x6D
    ret
PADRE_PAT_6: ldi r16, 0x7D
    ret
PADRE_PAT_7: ldi r16, 0x07
    ret
PADRE_PAT_8: ldi r16, 0x7F
    ret

;====================================================================
; ISR Timer0: multiplexado de cuatro digitos del padre.
; Buffers r2,r3,r4,r5 corresponden a PC0,PC1,PC2,PC3.
;====================================================================
ISR_TIMER0:
    push r16
    in r16, SREG
    push r16
    push r17
    push r30
    push r31

    clr r16
    out PORTC, r16               ; apagar todos los digitos antes de cambiar segmentos

    mov r16, r6
    cpi r16, 0
    breq ISR_DIGITO_0
    cpi r16, 1
    breq ISR_DIGITO_1
    cpi r16, 2
    breq ISR_DIGITO_2
    mov r16, r5
    ldi r17, 0x08
    rjmp ISR_ENCENDER_DIGITO
ISR_DIGITO_0:
    mov r16, r2
    ldi r17, 0x01
    rjmp ISR_ENCENDER_DIGITO
ISR_DIGITO_1:
    mov r16, r3
    ldi r17, 0x02
    rjmp ISR_ENCENDER_DIGITO
ISR_DIGITO_2:
    mov r16, r4
    ldi r17, 0x04
ISR_ENCENDER_DIGITO:
    out PORTA, r16
    out PORTC, r17

    inc r6
    mov r16, r6
    cpi r16, 4
    brlo ISR_TIMER0_FIN
    clr r6
ISR_TIMER0_FIN:
    pop r31
    pop r30
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

.cseg
.align 2

TXT_TITULO1:
    .db "EJERCICIOS 1-5",0,0

TXT_TITULO2:
    .db "EJERCICIOS 6-9",0,0

TXT_1:
    .db "1. EJERCICIO 1",0,0

TXT_2:
    .db "2. EJERCICIO 2",0,0

TXT_3:
    .db "3. EJERCICIO 3",0,0

TXT_4:
    .db "4. EJERCICIO 4",0,0

TXT_5:
    .db "5. EJERCICIO 5",0,0

TXT_6:
    .db "6. EJERCICIO 6",0,0

TXT_7:
    .db "7. EJERCICIO 7",0,0

TXT_8:
    .db "8. EJERCICIO 8",0,0

TXT_9:
    .db "9. EJERCICIO 9",0,0

;================================
; FUENTE 5x7
;================================
.align 2

GL_SPACE:
    .db 0x00,0x00,0x00,0x00,0x00,0x00

GL_DOT:
    .db 0x60,0x60,0x00,0x00,0x00,0x00

GL_DASH:
    .db 0x08,0x08,0x08,0x08,0x08,0x00

GL_1:
    .db 0x00,0x42,0x7F,0x40,0x00,0x00
GL_2:
    .db 0x62,0x51,0x49,0x49,0x46,0x00
GL_3:
    .db 0x22,0x41,0x49,0x49,0x36,0x00
GL_4:
    .db 0x18,0x14,0x12,0x7F,0x10,0x00
GL_5:
    .db 0x2F,0x49,0x49,0x49,0x31,0x00
GL_6:
    .db 0x3E,0x49,0x49,0x49,0x32,0x00
GL_7:
    .db 0x01,0x71,0x09,0x05,0x03,0x00
GL_8:
    .db 0x36,0x49,0x49,0x49,0x36,0x00
GL_9:
    .db 0x26,0x49,0x49,0x49,0x3E,0x00

GL_E:
    .db 0x7F,0x49,0x49,0x49,0x41,0x00
GL_J:
    .db 0x20,0x40,0x41,0x3F,0x01,0x00
GL_R:
    .db 0x7F,0x09,0x19,0x29,0x46,0x00
GL_C:
    .db 0x3E,0x41,0x41,0x41,0x22,0x00
GL_I:
    .db 0x00,0x41,0x7F,0x41,0x00,0x00
GL_O:
    .db 0x3E,0x41,0x41,0x41,0x3E,0x00
GL_S:
    .db 0x46,0x49,0x49,0x49,0x31,0x00