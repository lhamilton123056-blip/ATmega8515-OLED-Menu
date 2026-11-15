.include "m8515def.inc"

; ============================================================
; ATmega8515 ESCLAVO - EJERCICIOS 1, 2, 3, 4, 6, 7 Y 8
; Reloj: 1 MHz (configuracion de fabrica)
; UART: 9600 baudios, U2X=1, UBRR=12
;
; EJERCICIO 1:
;   PB0..PB7 = entradas del DIP switch con pull-up interno
;   PA0..PA7 = salidas para los ocho LEDs
;   Cada switch conecta su entrada a GND al activarse.
;
; EJERCICIO 2:
;   PA0..PA7 = ocho LEDs para el pendulo
;   PD3 = pulsador de velocidad (conectar entre PD3 y GND)
;   Pull-up interno activado en PD3
;   Cada pulsacion cambia la velocidad: 1 -> 2 -> 3 -> 4 -> 5 -> 1
;
; EJERCICIOS 3, 4 Y 6:
;   PA0..PA7 = display de 7 segmentos de ANODO COMUN
;   PD3 = pulsador de velocidad (ejercicios 2, 3, 4 y 6)
;   PD4 = cambio numeros/letras (ejercicio 6)
;   PD7 = LED indicador de modo (ejercicio 6)
;   PD2 = pulsador de interrupcion INT0 (solo ejercicio 4)
;
; EJERCICIOS 7 Y 8:
;   PB0..PB7 = primer DIP de 8 bits
;   PC0..PC7 = segundo DIP de 8 bits
;   PA0..PA7 = resultado (mayor o suma)
;   PD5 = indicador A (ejercicios 7/8); PD6 = transistor buzzer (ejercicio 8)
;   PD7 = indicador de modo (ejercicio 6) / indicador B (ejercicio 7)
;
; COMUNICACION:
;   PD0 (RXD) recibe desde PD1 (TXD) del maestro
;   GND del maestro y esclavo unidos
;
; IMPORTANTE:
;   PD0/PD1 quedan reservados para UART.
;   PD2 queda reservado para INT0.
;   PD3/PD4 son pulsadores; PD5/PD6/PD7 son salidas auxiliares.
;   El ejercicio 5 y el 9 se ejecutan en el maestro.
; ============================================================

.equ UBRR_9600 = 12

.def temp = r16
.def cmd  = r17
.def patron = r18
.def direccion = r19
.def velocidad = r20
.def cuenta_lenta = r22
.def cuenta_media = r23
.def cuenta_rapida = r24

.org 0x0000
    rjmp INICIO

.org 0x0001
    rjmp ISR_INT0

.org 0x0020

INICIO:
    ; Inicializar Stack Pointer
    ldi temp, HIGH(RAMEND)
    out SPH, temp
    ldi temp, LOW(RAMEND)
    out SPL, temp

    ; Puerto A: ocho LEDs como salidas, inicialmente apagados
    ldi temp, 0xFF
    out DDRA, temp
    clr temp
    out PORTA, temp

    ; Puerto B: entradas del DIP con pull-ups internos
    clr temp
    out DDRB, temp
    ldi temp, 0xFF
    out PORTB, temp

    ; PD3 y PD4: botones con pull-up interno (velocidad / modo)
    cbi DDRD, 3
    sbi PORTD, 3
    cbi DDRD, 4
    sbi PORTD, 4

    ; PD5 y PD6: salidas para LED indicador y transistor del buzzer
    sbi DDRD, 5
    sbi DDRD, 6
    sbi DDRD, 7
    cbi PORTD, 5
    cbi PORTD, 6
    cbi PORTD, 7

    ; PD2: entrada para el pulsador de interrupcion INT0, con pull-up
    cbi DDRD, 2
    sbi PORTD, 2
    ldi temp, (1<<ISC01)       ; INT0 por flanco descendente
    out MCUCR, temp
    ldi temp, (1<<INTF0)       ; limpiar bandera pendiente
    out GIFR, temp
    in temp, GICR
    andi temp, 0xBF             ; limpiar bit INT0 (GICR esta fuera del rango SBI/CBI)
    out GICR, temp              ; INT0 se habilita solo en ejercicio 4

    ; UART: 9600, 8 bits, sin paridad, 1 stop, solo RX
    ldi temp, (1<<U2X)
    out UCSRA, temp
    clr temp
    out UBRRH, temp
    ldi temp, UBRR_9600
    out UBRRL, temp
    ldi temp, (1<<RXEN)
    out UCSRB, temp
    ldi temp, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, temp

; ============================================================
; ESPERA INICIAL: aguarda la primera seleccion del maestro
; ============================================================
ESPERA:
    sbis UCSRA, RXC
    rjmp ESPERA
    rjmp PROCESAR_COMANDO

; ============================================================
; PROCESAR COMANDO UART (el maestro envia valores del 1 al 9)
; ============================================================
PROCESAR_COMANDO:
    ; Deshabilitar INT0 al cambiar de ejercicio
    in temp, GICR
    andi temp, 0xBF             ; deshabilitar INT0 sin usar CBI sobre GICR
    out GICR, temp
    in cmd, UDR

    ; Validar que el comando este entre 1 y 9
    cpi cmd, 1
    brlo COMANDO_INVALIDO
    cpi cmd, 10
    brsh COMANDO_INVALIDO

    ; Convertir 1..9 a indice 0..8 para la tabla
    dec cmd

    ; Apagar salidas auxiliares antes de entrar al nuevo ejercicio.
    ; Se conservan PD0..PD4 (UART, INT0 y pull-ups de botones).
    in temp, PORTD
    andi temp, 0x1F
    out PORTD, temp
    clr temp
    out PORTA, temp

    ; Saltar a la rutina correspondiente
    ldi ZL, low(TABLA_EJERCICIOS)
    ldi ZH, high(TABLA_EJERCICIOS)
    add ZL, cmd
    clr temp
    adc ZH, temp
    ijmp

COMANDO_INVALIDO:
    ; El maestro normalmente solo envia valores validos.
    ; Si llega uno incorrecto, se vuelve a esperar un comando.
    rjmp ESPERA

TABLA_EJERCICIOS:
    rjmp EJERCICIO_1
    rjmp EJERCICIO_2
    rjmp EJERCICIO_3
    rjmp EJERCICIO_4
    rjmp EJERCICIO_5
    rjmp EJERCICIO_6
    rjmp EJERCICIO_7
    rjmp EJERCICIO_8
    rjmp EJERCICIO_9

; ============================================================
; EJERCICIO 1: leer DIP en PB y mostrar el complemento en PA
; ============================================================
EJERCICIO_1:
    ldi temp, 0xFF
    out DDRA, temp
    clr temp
    out DDRB, temp
    ldi temp, 0xFF
    out PORTB, temp
EJERCICIO_1_CICLO:
    in temp, PINB
    com temp
    out PORTA, temp

    ; Revisar UART en cada vuelta para permitir cambiar de ejercicio
    sbis UCSRA, RXC
    rjmp EJERCICIO_1_CICLO
    rjmp PROCESAR_COMANDO

; ============================================================
; EJERCICIO 2: pendulo de ocho LEDs con cinco velocidades
; ============================================================
EJERCICIO_2:
    cbi DDRD, 3
    sbi PORTD, 3
    ldi temp, 0xFF
    out DDRA, temp
    ; Estado inicial del pendulo
    ldi velocidad, 1
    ldi patron, 0b00000001
    clr direccion                 ; 0 = hacia PA7, 1 = hacia PA0

EJERCICIO_2_CICLO:
    ; Mostrar el LED actual
    out PORTA, patron

    ; --------------------------------------------------------
    ; Revisar pulsador en PD3 (activo en nivel bajo)
    ; --------------------------------------------------------
    sbis PIND, 3                  ; Si PD3 esta alto, no esta pulsado
    rjmp BOTON_DETECTADO
    rjmp PREPARAR_RETARDO

BOTON_DETECTADO:
    ; Antirrebote aproximado de 10 ms, sin dejar de revisar UART
    ldi cuenta_media, 20
ANTIRREBOTE_EXTERNO:
    ldi cuenta_lenta, 255
ANTIRREBOTE_INTERNO:
    sbis UCSRA, RXC
    rjmp ANTIRREBOTE_CONTINUAR
    rjmp PROCESAR_COMANDO
ANTIRREBOTE_CONTINUAR:
    dec cuenta_lenta
    brne ANTIRREBOTE_INTERNO
    dec cuenta_media
    brne ANTIRREBOTE_EXTERNO

    ; Confirmar que el pulsador sigue presionado
    sbis PIND, 3
    rjmp BOTON_VALIDO
    rjmp PREPARAR_RETARDO

BOTON_VALIDO:
    ; Aumentar velocidad y regresar a 1 despues de 5
    inc velocidad
    cpi velocidad, 6
    brlo ESPERAR_LIBERACION
    ldi velocidad, 1

ESPERAR_LIBERACION:
    ; No repetir el cambio mientras el pulsador siga presionado
    sbis UCSRA, RXC
    rjmp REVISAR_LIBERACION
    rjmp PROCESAR_COMANDO

REVISAR_LIBERACION:
    sbis PIND, 3                  ; Si esta alto, ya se libero
    rjmp ESPERAR_LIBERACION

    ; --------------------------------------------------------
    ; Seleccionar duracion del retardo segun velocidad
    ; Los valores conservan la escala del programa original.
    ; --------------------------------------------------------
PREPARAR_RETARDO:
    cpi velocidad, 1
    breq RETARDO_VEL1
    cpi velocidad, 2
    breq RETARDO_VEL2
    cpi velocidad, 3
    breq RETARDO_VEL3
    cpi velocidad, 4
    breq RETARDO_VEL4

    ; Velocidad 5 (mas rapida)
    ldi cuenta_rapida, 3
    rjmp INICIAR_RETARDO

RETARDO_VEL1:
    ldi cuenta_rapida, 40
    rjmp INICIAR_RETARDO

RETARDO_VEL2:
    ldi cuenta_rapida, 30
    rjmp INICIAR_RETARDO

RETARDO_VEL3:
    ldi cuenta_rapida, 20
    rjmp INICIAR_RETARDO

RETARDO_VEL4:
    ldi cuenta_rapida, 10

INICIAR_RETARDO:
    ldi cuenta_media, 2
RETARDO_MEDIO:
    ldi cuenta_lenta, 255
RETARDO_INTERNO:
    ; Leer PD3 continuamente: la velocidad cambia sin esperar al fin del retardo.
    sbis PIND, 3
    rjmp BOTON_DETECTADO
    ; Comprobar UART durante el retardo para poder cambiar de ejercicio
    sbis UCSRA, RXC
    rjmp RETARDO_CONTINUAR
    rjmp PROCESAR_COMANDO
RETARDO_CONTINUAR:
    dec cuenta_lenta
    brne RETARDO_INTERNO
    dec cuenta_media
    brne RETARDO_MEDIO
    dec cuenta_rapida
    brne INICIAR_RETARDO

    ; --------------------------------------------------------
    ; Mover el LED y cambiar direccion al llegar a cada extremo
    ; --------------------------------------------------------
    cpi direccion, 0
    brne PENDULO_REGRESO

PENDULO_AVANCE:
    ldi temp, 0b10000000
    cp patron, temp
    breq PENDULO_CAMBIO_IZQUIERDA
    lsl patron
    rjmp EJERCICIO_2_CICLO

PENDULO_CAMBIO_IZQUIERDA:
    ldi direccion, 1
    lsr patron
    rjmp EJERCICIO_2_CICLO

PENDULO_REGRESO:
    ldi temp, 0b00000001
    cp patron, temp
    breq PENDULO_CAMBIO_DERECHA
    lsr patron
    rjmp EJERCICIO_2_CICLO

PENDULO_CAMBIO_DERECHA:
    clr direccion
    lsl patron
    rjmp EJERCICIO_2_CICLO

; ============================================================
; EJERCICIO 3: contador ciclico 0..9 en display de 7 segmentos
; Display de ANODO COMUN: los patrones vienen del main.asm original.
; PD3 comparte el pulsador del ejercicio 2.
; El retardo y el antirrebote revisan UART para permitir cambiar de ejercicio.
; ============================================================
EJERCICIO_3:
    cbi DDRD, 3
    sbi PORTD, 3
    ldi temp, 0xFF
    out DDRA, temp
    clr cmd                       ; cmd se reutiliza como contador 0..9
    ldi velocidad, 1              ; velocidad inicial

EJ3_MOSTRAR:
    cpi cmd, 0
    breq EJ3_CERO
    cpi cmd, 1
    breq EJ3_UNO
    cpi cmd, 2
    breq EJ3_DOS
    cpi cmd, 3
    breq EJ3_TRES
    cpi cmd, 4
    breq EJ3_CUATRO
    cpi cmd, 5
    breq EJ3_CINCO
    cpi cmd, 6
    breq EJ3_SEIS
    cpi cmd, 7
    breq EJ3_SIETE
    cpi cmd, 8
    breq EJ3_OCHO
    rjmp EJ3_NUEVE

EJ3_CERO:
    ldi temp, 0xC0
    rjmp EJ3_SALIDA
EJ3_UNO:
    ldi temp, 0xF9
    rjmp EJ3_SALIDA
EJ3_DOS:
    ldi temp, 0xA4
    rjmp EJ3_SALIDA
EJ3_TRES:
    ldi temp, 0xB0
    rjmp EJ3_SALIDA
EJ3_CUATRO:
    ldi temp, 0x99
    rjmp EJ3_SALIDA
EJ3_CINCO:
    ldi temp, 0x92
    rjmp EJ3_SALIDA
EJ3_SEIS:
    ldi temp, 0x82
    rjmp EJ3_SALIDA
EJ3_SIETE:
    ldi temp, 0xF8
    rjmp EJ3_SALIDA
EJ3_OCHO:
    ldi temp, 0x80
    rjmp EJ3_SALIDA
EJ3_NUEVE:
    ldi temp, 0x90

EJ3_SALIDA:
    out PORTA, temp

    ; Seleccionar retardo segun velocidad (misma escala del ejercicio original)
    cpi velocidad, 1
    breq EJ3_VEL1
    cpi velocidad, 2
    breq EJ3_VEL2
    cpi velocidad, 3
    breq EJ3_VEL3
    cpi velocidad, 4
    breq EJ3_VEL4
    rjmp EJ3_VEL5

EJ3_VEL1:
    ldi r21, 10
    ldi r22, 255
    rjmp EJ3_INICIAR_RETARDO
EJ3_VEL2:
    ldi r21, 7
    ldi r22, 255
    rjmp EJ3_INICIAR_RETARDO
EJ3_VEL3:
    ldi r21, 4
    ldi r22, 255
    rjmp EJ3_INICIAR_RETARDO
EJ3_VEL4:
    ldi r21, 2
    ldi r22, 255
    rjmp EJ3_INICIAR_RETARDO
EJ3_VEL5:
    ldi r21, 1
    ldi r22, 120

EJ3_INICIAR_RETARDO:
    mov r19, r22
EJ3_CICLO_MEDIO:
    ldi r18, 255
EJ3_CICLO_INTERNO:
    ; Muestrear PD3 durante el retardo, no solo al terminar el numero.
    sbis PIND, 3
    rjmp EJ3_BOTON_DETECTADO
    ; Si llega una seleccion nueva, abandonar el ejercicio inmediatamente
    sbis UCSRA, RXC
    rjmp EJ3_CONTAR_RETARDO
    rjmp PROCESAR_COMANDO
EJ3_CONTAR_RETARDO:
    dec r18
    brne EJ3_CICLO_INTERNO
    dec r19
    brne EJ3_CICLO_MEDIO
    dec r21
    brne EJ3_INICIAR_RETARDO

    ; Revisar el pulsador PD3 (activo en bajo)
    sbis PIND, 3
    rjmp EJ3_BOTON_DETECTADO
    rjmp EJ3_SIGUIENTE_NUMERO

EJ3_BOTON_DETECTADO:
    ; Antirrebote. UART sigue teniendo prioridad.
    ldi r18, 100
EJ3_ANTI1:
    ldi r19, 255
EJ3_ANTI2:
    sbis UCSRA, RXC
    rjmp EJ3_ANTI_CONTINUAR
    rjmp PROCESAR_COMANDO
EJ3_ANTI_CONTINUAR:
    dec r19
    brne EJ3_ANTI2
    dec r18
    brne EJ3_ANTI1

    ; Confirmar que el boton continua presionado
    sbis PIND, 3
    rjmp EJ3_BOTON_VALIDO
    rjmp EJ3_SIGUIENTE_NUMERO

EJ3_BOTON_VALIDO:
    inc velocidad
    cpi velocidad, 6
    brlo EJ3_ESPERAR_LIBERACION
    ldi velocidad, 1

EJ3_ESPERAR_LIBERACION:
    sbis UCSRA, RXC
    rjmp EJ3_COMPROBAR_LIBERACION
    rjmp PROCESAR_COMANDO
EJ3_COMPROBAR_LIBERACION:
    sbis PIND, 3
    rjmp EJ3_ESPERAR_LIBERACION

EJ3_SIGUIENTE_NUMERO:
    inc cmd
    cpi cmd, 10
    brsh EJ3_REINICIAR_CONTADOR
    rjmp EJ3_MOSTRAR

EJ3_REINICIAR_CONTADOR:
    clr cmd
    rjmp EJ3_MOSTRAR

; ============================================================
; EJERCICIO 4: contador 0..9 con interrupcion externa INT0
; PD2 = pulsador de interrupcion (a GND)
; PD3 = pulsador de velocidad (a GND)
; Al activar INT0, muestra A, B, C, D, E y F, y regresa al conteo.
; Velocidades mas diferenciadas, iguales a las del ejercicio 3.
; ============================================================
EJERCICIO_4:
    cbi DDRD, 3
    sbi PORTD, 3
    ldi temp, 0xFF
    out DDRA, temp
    clr cmd                       ; contador numerico 0..9
    ldi velocidad, 1
    ldi temp, (1<<INTF0)
    out GIFR, temp                ; limpiar bandera anterior
    in temp, GICR
    ori temp, 0x40             ; habilitar INT0 (bit 6 de GICR)
    out GICR, temp
    sei

EJ4_MOSTRAR:
    ; Una nueva seleccion del maestro tiene prioridad
    sbis UCSRA, RXC
    rjmp EJ4_DECODIFICAR
    rjmp PROCESAR_COMANDO

EJ4_DECODIFICAR:
    cpi cmd, 0
    breq EJ4_CERO
    cpi cmd, 1
    breq EJ4_UNO
    cpi cmd, 2
    breq EJ4_DOS
    cpi cmd, 3
    breq EJ4_TRES
    cpi cmd, 4
    breq EJ4_CUATRO
    cpi cmd, 5
    breq EJ4_CINCO
    cpi cmd, 6
    breq EJ4_SEIS
    cpi cmd, 7
    breq EJ4_SIETE
    cpi cmd, 8
    breq EJ4_OCHO
    rjmp EJ4_NUEVE

EJ4_CERO:
    ldi temp, 0xC0
    rjmp EJ4_SALIDA
EJ4_UNO:
    ldi temp, 0xF9
    rjmp EJ4_SALIDA
EJ4_DOS:
    ldi temp, 0xA4
    rjmp EJ4_SALIDA
EJ4_TRES:
    ldi temp, 0xB0
    rjmp EJ4_SALIDA
EJ4_CUATRO:
    ldi temp, 0x99
    rjmp EJ4_SALIDA
EJ4_CINCO:
    ldi temp, 0x92
    rjmp EJ4_SALIDA
EJ4_SEIS:
    ldi temp, 0x82
    rjmp EJ4_SALIDA
EJ4_SIETE:
    ldi temp, 0xF8
    rjmp EJ4_SALIDA
EJ4_OCHO:
    ldi temp, 0x80
    rjmp EJ4_SALIDA
EJ4_NUEVE:
    ldi temp, 0x90

EJ4_SALIDA:
    out PORTA, temp

    ; Retardo segun velocidad; se revisa UART durante el retardo.
    cpi velocidad, 1
    breq EJ4_VEL1
    cpi velocidad, 2
    breq EJ4_VEL2
    cpi velocidad, 3
    breq EJ4_VEL3
    cpi velocidad, 4
    breq EJ4_VEL4
    rjmp EJ4_VEL5
EJ4_VEL1:
    ldi r21, 10
    ldi r22, 255
    rjmp EJ4_INICIAR_RETARDO
EJ4_VEL2:
    ldi r21, 7
    ldi r22, 255
    rjmp EJ4_INICIAR_RETARDO
EJ4_VEL3:
    ldi r21, 4
    ldi r22, 255
    rjmp EJ4_INICIAR_RETARDO
EJ4_VEL4:
    ldi r21, 2
    ldi r22, 255
    rjmp EJ4_INICIAR_RETARDO
EJ4_VEL5:
    ldi r21, 1
    ldi r22, 120

EJ4_INICIAR_RETARDO:
    mov r24, r22                ; conservar cantidad de ciclos medios
EJ4_REINICIAR_MEDIO:
    ldi r18, 255
EJ4_CICLO_INTERNO:
    ; Muestrear PD3 durante el retardo para respuesta inmediata.
    sbis PIND, 3
    rjmp EJ4_BOTON_DETECTADO
    sbis UCSRA, RXC
    rjmp EJ4_CONTINUAR_RETARDO
    rjmp PROCESAR_COMANDO
EJ4_CONTINUAR_RETARDO:
    dec r18
    brne EJ4_CICLO_INTERNO
    dec r22
    brne EJ4_REINICIAR_INTERNO
    dec r21
    brne EJ4_REINICIAR_CUENTA_MEDIA
    rjmp EJ4_REVISAR_BOTON
EJ4_REINICIAR_INTERNO:
    ldi r18, 255
    rjmp EJ4_CICLO_INTERNO
EJ4_REINICIAR_CUENTA_MEDIA:
    mov r22, r24
    rjmp EJ4_REINICIAR_MEDIO

EJ4_REVISAR_BOTON:
    ; PD3: pulsador de velocidad compartido con ejercicios 2 y 3
    sbis PIND, 3
    rjmp EJ4_BOTON_DETECTADO
    rjmp EJ4_SIGUIENTE_NUMERO
EJ4_BOTON_DETECTADO:
    ldi r18, 20
EJ4_ANTI_EXTERNO:
    ldi r19, 255
EJ4_ANTI_INTERNO:
    sbis UCSRA, RXC
    rjmp EJ4_ANTI_CONTINUAR
    rjmp PROCESAR_COMANDO
EJ4_ANTI_CONTINUAR:
    dec r19
    brne EJ4_ANTI_INTERNO
    dec r18
    brne EJ4_ANTI_EXTERNO
    sbis PIND, 3
    rjmp EJ4_BOTON_VALIDO
    rjmp EJ4_SIGUIENTE_NUMERO
EJ4_BOTON_VALIDO:
    inc velocidad
    cpi velocidad, 6
    brlo EJ4_ESPERAR_LIBERACION
    ldi velocidad, 1
EJ4_ESPERAR_LIBERACION:
    sbis UCSRA, RXC
    rjmp EJ4_COMPROBAR_LIBERACION
    rjmp PROCESAR_COMANDO
EJ4_COMPROBAR_LIBERACION:
    sbis PIND, 3
    rjmp EJ4_ESPERAR_LIBERACION

EJ4_SIGUIENTE_NUMERO:
    inc cmd
    cpi cmd, 10
    brsh EJ4_REINICIAR_CONTADOR
    rjmp EJ4_MOSTRAR
EJ4_REINICIAR_CONTADOR:
    clr cmd
    rjmp EJ4_MOSTRAR

; ============================================================
; ISR INT0: muestra A..F al presionar el pulsador conectado a PD2.
; UART puede interrumpir la secuencia para cambiar de ejercicio.
; PD3 sigue permitiendo cambiar la velocidad durante la secuencia.
; ============================================================
ISR_INT0:
    push r16
    in r16, SREG
    push r16
    push r17
    push r18
    push r19
    push r21
    push r22
    push r23
    push r24
    push r25

    ; Evitar reentrada mientras se atiende esta interrupcion
    in temp, GICR
    andi temp, 0xBF             ; deshabilitar INT0 sin usar CBI sobre GICR
    out GICR, temp
    clr r23                       ; indice de letra A..F

ISR_LETRAS:
    cpi r23, 0
    breq ISR_LETRA_A
    cpi r23, 1
    breq ISR_LETRA_B
    cpi r23, 2
    breq ISR_LETRA_C
    cpi r23, 3
    breq ISR_LETRA_D
    cpi r23, 4
    breq ISR_LETRA_E
    rjmp ISR_LETRA_F
ISR_LETRA_A:
    ldi r16, 0x88
    rjmp ISR_MOSTRAR_LETRA
ISR_LETRA_B:
    ldi r16, 0x83
    rjmp ISR_MOSTRAR_LETRA
ISR_LETRA_C:
    ldi r16, 0xC6
    rjmp ISR_MOSTRAR_LETRA
ISR_LETRA_D:
    ldi r16, 0xA1
    rjmp ISR_MOSTRAR_LETRA
ISR_LETRA_E:
    ldi r16, 0x86
    rjmp ISR_MOSTRAR_LETRA
ISR_LETRA_F:
    ldi r16, 0x8E

ISR_MOSTRAR_LETRA:
    out PORTA, r16

    ; Retardo de la letra segun la misma velocidad 1..5
    cpi velocidad, 1
    breq ISR_VEL1
    cpi velocidad, 2
    breq ISR_VEL2
    cpi velocidad, 3
    breq ISR_VEL3
    cpi velocidad, 4
    breq ISR_VEL4
    rjmp ISR_VEL5
ISR_VEL1:
    ldi r21, 10
    ldi r22, 255
    rjmp ISR_INICIAR_RETARDO
ISR_VEL2:
    ldi r21, 7
    ldi r22, 255
    rjmp ISR_INICIAR_RETARDO
ISR_VEL3:
    ldi r21, 4
    ldi r22, 255
    rjmp ISR_INICIAR_RETARDO
ISR_VEL4:
    ldi r21, 2
    ldi r22, 255
    rjmp ISR_INICIAR_RETARDO
ISR_VEL5:
    ldi r21, 1
    ldi r22, 120
ISR_INICIAR_RETARDO:
    mov r24, r22
ISR_REINICIAR_MEDIO:
    ldi r18, 255
ISR_RETARDO_INTERNO:
    ; Revisar PD3 durante cada tramo de la secuencia A..F.
    sbis PIND, 3
    rjmp ISR_BOTON_VEL
    ; Si el maestro envia otra seleccion, salir de la ISR
    sbis UCSRA, RXC
    rjmp ISR_CONTINUAR_RETARDO
    rjmp ISR_SALIR_POR_UART
ISR_CONTINUAR_RETARDO:
    dec r18
    brne ISR_RETARDO_INTERNO
    dec r22
    brne ISR_REINICIAR_INTERNO
    dec r21
    brne ISR_REINICIAR_CUENTA_MEDIA
    rjmp ISR_REVISAR_BOTON_VEL
ISR_REINICIAR_INTERNO:
    ldi r18, 255
    rjmp ISR_RETARDO_INTERNO
ISR_REINICIAR_CUENTA_MEDIA:
    mov r22, r24
    rjmp ISR_REINICIAR_MEDIO

ISR_REVISAR_BOTON_VEL:
    ; Permitir cambiar velocidad con PD3 incluso dentro de la ISR
    sbis PIND, 3
    rjmp ISR_BOTON_VEL
    rjmp ISR_SIGUIENTE_LETRA
ISR_BOTON_VEL:
    ldi r18, 20
ISR_BOTON_ANTI1:
    ldi r19, 255
ISR_BOTON_ANTI2:
    sbis UCSRA, RXC
    rjmp ISR_BOTON_ANTI_CONT
    rjmp ISR_SALIR_POR_UART
ISR_BOTON_ANTI_CONT:
    dec r19
    brne ISR_BOTON_ANTI2
    dec r18
    brne ISR_BOTON_ANTI1
    sbis PIND, 3
    rjmp ISR_BOTON_VALIDO
    rjmp ISR_SIGUIENTE_LETRA
ISR_BOTON_VALIDO:
    inc velocidad
    cpi velocidad, 6
    brlo ISR_ESPERAR_BOTON
    ldi velocidad, 1
ISR_ESPERAR_BOTON:
    sbis UCSRA, RXC
    rjmp ISR_COMPROBAR_BOTON
    rjmp ISR_SALIR_POR_UART
ISR_COMPROBAR_BOTON:
    sbis PIND, 3
    rjmp ISR_ESPERAR_BOTON

ISR_SIGUIENTE_LETRA:
    inc r23
    cpi r23, 6
    brsh ISR_FIN_LETRAS
    rjmp ISR_LETRAS

ISR_FIN_LETRAS:
    ; Esperar que suelten el pulsador de interrupcion PD2
ISR_ESPERAR_LIBERAR:
    sbis PIND, PD2
    rjmp ISR_ESPERAR_LIBERAR
    ; Antirrebote de liberacion
    ldi r18, 20
ISR_LIBERAR_ANTI1:
    ldi r19, 255
ISR_LIBERAR_ANTI2:
    dec r19
    brne ISR_LIBERAR_ANTI2
    dec r18
    brne ISR_LIBERAR_ANTI1
    sbis PIND, PD2
    rjmp ISR_ESPERAR_LIBERAR

    ldi r16, (1<<INTF0)
    out GIFR, r16
    in temp, GICR
    ori temp, 0x40             ; volver a habilitar INT0
    out GICR, temp
    rjmp ISR_RESTAURAR

ISR_SALIR_POR_UART:
    ; No reactivar INT0: el programa principal procesara el comando UART
    in temp, GICR
    andi temp, 0xBF             ; deshabilitar INT0 sin usar CBI sobre GICR
    out GICR, temp
ISR_RESTAURAR:
    pop r25
    pop r24
    pop r23
    pop r22
    pop r21
    pop r19
    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

EJERCICIO_5:
    ; Los ejercicios 5 y 9 se ejecutan en el maestro.
    rjmp ESPERA

; ============================================================
; EJERCICIO 6: display individual, numeros 0..9 / letras A..F
; PA = segmentos de anodo comun
; PD3 = velocidad, PD4 = cambio de modo, PD7 = LED de modo
; ============================================================
EJERCICIO_6:
    sbi DDRD, 7
    cbi PORTD, 7
    cbi DDRD, 3
    sbi PORTD, 3
    cbi DDRD, 4
    sbi PORTD, 4
    ldi temp, 0xFF
    out DDRA, temp
    ; PC completo queda libre para el DIP 2 de los ejercicios 7 y 8.
    ; El LED indicador de modo se utiliza en PD7.
    cbi PORTD, 7
    clr cmd                       ; indice de numero/letra
    clr r23                       ; 0=numeros, 1=letras
    ldi velocidad, 1

EJ6_CICLO:
    sbis UCSRA, RXC
    rjmp EJ6_SELECCIONAR
    rjmp PROCESAR_COMANDO

EJ6_SELECCIONAR:
    tst r23
    brne EJ6_MODO_LETRAS
    ; Numeros 0..9 (patrones de anodo comun)
    cpi cmd, 0
    breq EJ6_CERO
    cpi cmd, 1
    breq EJ6_UNO
    cpi cmd, 2
    breq EJ6_DOS
    cpi cmd, 3
    breq EJ6_TRES
    cpi cmd, 4
    breq EJ6_CUATRO
    cpi cmd, 5
    breq EJ6_CINCO
    cpi cmd, 6
    breq EJ6_SEIS
    cpi cmd, 7
    breq EJ6_SIETE
    cpi cmd, 8
    breq EJ6_OCHO
    rjmp EJ6_NUEVE

EJ6_MODO_LETRAS:
    cpi cmd, 0
    breq EJ6_LETRA_A
    cpi cmd, 1
    breq EJ6_LETRA_B
    cpi cmd, 2
    breq EJ6_LETRA_C
    cpi cmd, 3
    breq EJ6_LETRA_D
    cpi cmd, 4
    breq EJ6_LETRA_E
    rjmp EJ6_LETRA_F

EJ6_CERO:     ldi temp, 0xC0  ; 0
              rjmp EJ6_MOSTRAR
EJ6_UNO:      ldi temp, 0xF9  ; 1
              rjmp EJ6_MOSTRAR
EJ6_DOS:      ldi temp, 0xA4  ; 2
              rjmp EJ6_MOSTRAR
EJ6_TRES:     ldi temp, 0xB0  ; 3
              rjmp EJ6_MOSTRAR
EJ6_CUATRO:   ldi temp, 0x99  ; 4
              rjmp EJ6_MOSTRAR
EJ6_CINCO:    ldi temp, 0x92  ; 5
              rjmp EJ6_MOSTRAR
EJ6_SEIS:     ldi temp, 0x82  ; 6
              rjmp EJ6_MOSTRAR
EJ6_SIETE:    ldi temp, 0xF8  ; 7
              rjmp EJ6_MOSTRAR
EJ6_OCHO:     ldi temp, 0x80  ; 8
              rjmp EJ6_MOSTRAR
EJ6_NUEVE:    ldi temp, 0x90  ; 9
              rjmp EJ6_MOSTRAR
EJ6_LETRA_A:  ldi temp, 0x88  ; A
              rjmp EJ6_MOSTRAR
EJ6_LETRA_B:  ldi temp, 0x83  ; b
              rjmp EJ6_MOSTRAR
EJ6_LETRA_C:  ldi temp, 0xC6  ; C
              rjmp EJ6_MOSTRAR
EJ6_LETRA_D:  ldi temp, 0xA1  ; d
              rjmp EJ6_MOSTRAR
EJ6_LETRA_E:  ldi temp, 0x86  ; E
              rjmp EJ6_MOSTRAR
EJ6_LETRA_F:  ldi temp, 0x8E  ; F

EJ6_MOSTRAR:
    out PORTA, temp

    ; Boton de modo PD4 (activo en bajo)
    sbis PIND, 4
    rjmp EJ6_BOTON_MODO
    rjmp EJ6_REVISAR_VELOCIDAD

EJ6_BOTON_MODO:
    ldi r18, 30
EJ6_MODO_ANTI:
    ldi r19, 255
EJ6_MODO_ANTI2:
    sbis UCSRA, RXC
    rjmp EJ6_MODO_CONT
    rjmp PROCESAR_COMANDO
EJ6_MODO_CONT:
    dec r19
    brne EJ6_MODO_ANTI2
    dec r18
    brne EJ6_MODO_ANTI
    sbis PIND, 4
    rjmp EJ6_MODO_VALIDO
    rjmp EJ6_REVISAR_VELOCIDAD
EJ6_MODO_VALIDO:
    ldi temp, 1
    eor r23, temp
    clr cmd
    tst r23
    breq EJ6_LED_APAGAR
    sbi PORTD, 7
    rjmp EJ6_ESPERAR_MODO
EJ6_LED_APAGAR:
    cbi PORTD, 7
EJ6_ESPERAR_MODO:
    sbis UCSRA, RXC
    rjmp EJ6_MODO_LIBERACION
    rjmp PROCESAR_COMANDO
EJ6_MODO_LIBERACION:
    sbis PIND, 4
    rjmp EJ6_ESPERAR_MODO

EJ6_REVISAR_VELOCIDAD:
    sbis PIND, 3
    rjmp EJ6_BOTON_VEL
    rjmp EJ6_RETARDO
EJ6_BOTON_VEL:
    ldi r18, 30
EJ6_VEL_ANTI:
    ldi r19, 255
EJ6_VEL_ANTI2:
    sbis UCSRA, RXC
    rjmp EJ6_VEL_CONT
    rjmp PROCESAR_COMANDO
EJ6_VEL_CONT:
    dec r19
    brne EJ6_VEL_ANTI2
    dec r18
    brne EJ6_VEL_ANTI
    sbis PIND, 3
    rjmp EJ6_VEL_VALIDO
    rjmp EJ6_RETARDO
EJ6_VEL_VALIDO:
    inc velocidad
    cpi velocidad, 6
    brlo EJ6_ESPERAR_VEL
    ldi velocidad, 1
EJ6_ESPERAR_VEL:
    sbis UCSRA, RXC
    rjmp EJ6_VEL_LIBERACION
    rjmp PROCESAR_COMANDO
EJ6_VEL_LIBERACION:
    sbis PIND, 3
    rjmp EJ6_ESPERAR_VEL

EJ6_RETARDO:
    ; Diferencias amplias entre las cinco velocidades
    cpi velocidad, 1
    breq EJ6_D1
    cpi velocidad, 2
    breq EJ6_D2
    cpi velocidad, 3
    breq EJ6_D3
    cpi velocidad, 4
    breq EJ6_D4
    ldi r21, 1
    rjmp EJ6_DINICIO
EJ6_D1: ldi r21, 10
        rjmp EJ6_DINICIO
EJ6_D2: ldi r21, 7
        rjmp EJ6_DINICIO
EJ6_D3: ldi r21, 4
        rjmp EJ6_DINICIO
EJ6_D4: ldi r21, 2
EJ6_DINICIO:
    ldi r22, 255
EJ6_DLOOP:
    ldi r18, 255
EJ6_DLOOP2:
    ; Revisar ambos botones continuamente durante el retardo.
    sbis PIND, 4
    rjmp EJ6_BOTON_MODO
    sbis PIND, 3
    rjmp EJ6_BOTON_VEL
    sbis UCSRA, RXC
    rjmp EJ6_DCONT
    rjmp PROCESAR_COMANDO
EJ6_DCONT:
    dec r18
    brne EJ6_DLOOP2
    dec r22
    brne EJ6_DLOOP
    dec r21
    brne EJ6_DINICIO

    inc cmd
    tst r23
    breq EJ6_LIMITE_NUM
    cpi cmd, 6
    brsh EJ6_REINICIAR_LETRA
    rjmp EJ6_CICLO
EJ6_REINICIAR_LETRA:
    clr cmd
    rjmp EJ6_CICLO
EJ6_LIMITE_NUM:
    cpi cmd, 10
    brsh EJ6_REINICIAR_NUM
    rjmp EJ6_CICLO
EJ6_REINICIAR_NUM:
    clr cmd
    rjmp EJ6_CICLO

; ============================================================
; EJERCICIO 7: comparar dos DIP de 8 bits
; PB y PC = entradas DIP con pull-up; PA = salida del mayor
; PD5 = indicador A; PD7 = indicador B (PD6 reservado para buzzer)
; ============================================================
EJERCICIO_7:
    ldi temp, 0xFF
    out DDRA, temp             ; PA = salida del mayor
    clr temp
    out DDRB, temp             ; PB = primer DIP
    out DDRC, temp             ; PC = segundo DIP
    ldi temp, 0xFF
    out PORTB, temp
    out PORTC, temp
    in temp, PORTD
    andi temp, 0x5F
    out PORTD, temp
EJ7_CICLO:
    in r16, PINB
    in r17, PINC
    com r16
    com r17
    cp r16, r17
    breq EJ7_EMPATE
    brsh EJ7_GANA_A
EJ7_GANA_B:
    mov r18, r17
    in temp, PORTD
    andi temp, 0x5F
    ori temp, 0x80             ; PD7 indicador B
    out PORTD, temp
    rjmp EJ7_MOSTRAR
EJ7_GANA_A:
    mov r18, r16
    in temp, PORTD
    andi temp, 0x5F
    ori temp, 0x20             ; PD5 indicador A
    out PORTD, temp
    rjmp EJ7_MOSTRAR
EJ7_EMPATE:
    mov r18, r16
    in temp, PORTD
    andi temp, 0x5F
    ori temp, 0xA0             ; PD5 y PD7: ambos indicadores
    out PORTD, temp
EJ7_MOSTRAR:
    out PORTA, r18
    sbis UCSRA, RXC
    rjmp EJ7_CICLO
    rjmp PROCESAR_COMANDO

; ============================================================
; EJERCICIO 8: suma de dos DIP de 8 bits y alarma por overflow
; PB/PC = entradas DIP; PA = suma; PD5 LED; PD6 transistor buzzer
; ============================================================
EJERCICIO_8:
    ldi temp, 0xFF
    out DDRA, temp             ; PA = salida de la suma
    clr temp
    out DDRB, temp             ; PB = primer DIP
    out DDRC, temp             ; PC = segundo DIP
    ldi temp, 0xFF
    out PORTB, temp
    out PORTC, temp
    in temp, PORTD
    andi temp, 0x9F
    out PORTD, temp
EJ8_CICLO:
    in r16, PINB
    in r17, PINC
    com r16
    com r17
    mov r18, r16
    add r18, r17
    out PORTA, r18
    brcs EJ8_OVERFLOW
    in temp, PORTD
    andi temp, 0x9F
    out PORTD, temp
    sbis UCSRA, RXC
    rjmp EJ8_CICLO
    rjmp PROCESAR_COMANDO
EJ8_OVERFLOW:
    ldi r23, 5
EJ8_PARPADEO:
    in temp, PORTD
    andi temp, 0x9F
    ori temp, 0x60             ; LED PD5 + buzzer transistor PD6
    out PORTD, temp
    rcall EJ8_RETARDO
    sbis UCSRA, RXC
    rjmp EJ8_COMPROBAR
    rjmp PROCESAR_COMANDO
EJ8_COMPROBAR:
    in r16, PINB
    in r17, PINC
    com r16
    com r17
    mov r18, r16
    add r18, r17
    out PORTA, r18
    brcs EJ8_SIGUE_OVERFLOW
    in temp, PORTD
    andi temp, 0x9F
    out PORTD, temp
    rjmp EJ8_CICLO
EJ8_SIGUE_OVERFLOW:
    in temp, PORTD
    andi temp, 0x9F
    out PORTD, temp
    rcall EJ8_RETARDO
    sbis UCSRA, RXC
    rjmp EJ8_SIGUIENTE_PARPADEO
    rjmp PROCESAR_COMANDO
EJ8_SIGUIENTE_PARPADEO:
    dec r23
    brne EJ8_PARPADEO
    rjmp EJ8_CICLO

EJ8_RETARDO:
    ldi r20, 3
EJ8_R1:
    ldi r21, 100
EJ8_R2:
    ldi r22, 255
EJ8_R3:
    dec r22
    brne EJ8_R3
    dec r21
    brne EJ8_R2
    dec r20
    brne EJ8_R1
    ret

; ============================================================
; EJERCICIO 9: se ejecuta en el maestro, compartiendo display con 5
; ============================================================
EJERCICIO_9:
    rjmp ESPERA