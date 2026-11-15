# Componentes del circuito
---


## Conexiones del microcontrolador PADRE

**Dada la siguiente imagen del microcontrolador ATMEGA 8515 hacer las conexiones**
![Imagen de microcontrolador ATMEGA 8515](Imagenes%20de%20componentes/Atmega8515%20Pines.jpg)

### Alimentación del componente
PIN 40 -> VOLTAJE(VCC)

PIN 20 -> GND

## Conexiones de Pantallas OLED
**Pantalla izquierda**
GND -> GND

VCC -> VCC

D0 -> PB7(PIN 8)

D1 -> PB5(PIN 6)

RES -> PB3(PIN 4)

DC -> PB2(PIN 3)

SC -> PB0(PIN 1) Diferencia con la otra pantalla


**Pantalla derecha**

GND -> GND

VCC -> VCC

D0 -> PB7(PIN 8)

D1 -> PB5(PIN 6)

RES -> PB3(PIN 4)

DC -> PB2(PIN 3)

SC -> PB1(PIN 2) Diferencia con la otra pantalla 

## Display de 4 dígitos de cátodo común
**Dados los siguientes pines del display hacer las conexiones**
![Imagen de display de 4 dígitos de cátodo común](Imagenes%20de%20componentes/Display%20de%204%20dígitos%20cátodo%20común.jpg)

**Dados los siguientes pines de transistores de 2N2222A hacer las conexiones**
![Imagen de display de 4 dígitos de cátodo común](Imagenes%20de%20componentes/Pines%20transistor%202N2222A.jpg)

**Conexiones de Transistores(4)**

PIN 1(EMISOR) -> GND

PIN 2(BASE) -> Resistencia de 1kΩ -> PUERTOS DE C (PIN 21 A 24 del microcontrolador); esto se hace conectando la resistencia a la base del transistor(1 pata), la segunda pata irá a una columna vacía, donde en esa línea se conectará a los puertos de C(una sola conexion por transistor)




---
---


## Conexiones del microcontrolador HIJO