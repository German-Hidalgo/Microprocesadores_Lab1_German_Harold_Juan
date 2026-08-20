/* ====================================================================
   Proyecto: Sumador Multiplexado (Modificado para PB0, PB1, PB3-PB8)
   Target:   STM32F103 (Proteus / Blue Pill)
   Reloj:    HSI Interno (8 MHz)
   Descripción de Entradas/Salidas:
   - Entradas: PA0 - PA7  -> DIP Switch (Datos A y B)
   - Pulsador: PC13       -> Control de avance (Pull-Up)
   - Salidas:  PB0, PB1, PB3 - PB8 -> Resultado Suma (8 bits, salta PB2)
               PB13       -> LED D1 (Indicador Dato A capturado)
               PB14       -> LED D2 (Indicador Dato B capturado)
               PB15       -> LED D3 (Indicador Suma realizada)
   ==================================================================== */

    .syntax unified
    .cpu cortex-m3
    .thumb

    .text
    .align 2
    .global main
    .global Reset_Handler
    .type main, %function
    .type Reset_Handler, %function
    .thumb_func

/* --- Direcciones de Registros RCC, AFIO y GPIO --- */
.equ RCC_APB2ENR,     0x40021018

.equ AFIO_BASE,       0x40010000
.equ AFIO_MAPR,       (AFIO_BASE + 0x04)

.equ GPIOA_CRL,       0x40010800
.equ GPIOA_IDR,       0x40010808

.equ GPIOB_CRL,       0x40010C00
.equ GPIOB_CRH,       0x40010C04
.equ GPIOB_ODR,       0x40010C0C

.equ GPIOC_CRH,       0x40011004
.equ GPIOC_IDR,       0x40011008

Reset_Handler:
main:
    cpsid i                       @ Deshabilitar interrupciones durante la inicialización

    /* 1. Habilitar reloj para AFIO, GPIOA, GPIOB y GPIOC */
    LDR R0, =RCC_APB2ENR
    LDR R1, [R0]
    ORR R1, R1, #(1 << 0) | (1 << 2) | (1 << 3) | (1 << 4)
    STR R1, [R0]

    /* 2. Deshabilitar JTAG en AFIO_MAPR para liberar PB3 y PB4 como GPIOs */
    LDR R0, =AFIO_MAPR
    LDR R1, [R0]
    BIC R1, R1, #(0x7 << 24)
    ORR R1, R1, #(0x2 << 24)
    STR R1, [R0]

    /* 3. Configurar PA0-PA7 como Entradas Digitales Floating (0x44444444) */
    LDR R0, =GPIOA_CRL
    LDR R1, =0x44444444
    STR R1, [R0]

    /* 4. Configurar PB0, PB1 y PB3-PB7 como Salidas Push-Pull 2MHz
       (Nota: PB2 se deja como Input Floating '4' porque se salta) */
    LDR R0, =GPIOB_CRL
    LDR R1, =0x22224222           @ Modificado: PB2 = 4 (Entrada), los demás = 2 (Salida)
    STR R1, [R0]

    /* 5. Configurar PB8, PB13, PB14 y PB15 como Salidas Push-Pull 2MHz */
    LDR R0, =GPIOB_CRH
    LDR R1, =0x22200002           @ PB15, PB14, PB13 y PB8 en modo salida
    STR R1, [R0]

    /* 6. Configurar PC13 como Entrada Digital Normal (Pull-Up) */
    LDR R0, =GPIOC_CRH
    LDR R1, [R0]
    BIC R1, R1, #(0x0F << 20)
    ORR R1, R1, #(0x04 << 20)
    STR R1, [R0]

/* --- INICIO DE LA MÁQUINA DE ESTADOS --- */
inicio_proceso:
    /* REPOSO INICIAL: Limpiar todas las salidas del Puerto B */
    LDR R0, =GPIOB_ODR
    MOV R1, #0
    STR R1, [R0]

    /* ====================================================================
       CAPTURA DEL DATO A
       ==================================================================== */
    BL esperar_pulsacion

    LDR R0, =GPIOA_IDR
    LDR R4, [R0]
    AND R4, R4, #0xFF              @ R4 = Dato A

    LDR R0, =GPIOB_ODR
    LDR R1, =(1 << 13)            @ PB13 = 1 (Enciende LED D1)
    STR R1, [R0]


/* ====================================================================
   DESARROLLO IMPLEMENTADO PARA CLASE (CAPTURA B, SUMA Y REINICIO)
   ==================================================================== */

    /* --- 1. CAPTURA DEL DATO B --- */
    BL esperar_pulsacion              @ Espera la segunda pulsación en PC13

    LDR R0, =GPIOA_IDR
    LDR R5, [R0]
    AND R5, R5, #0xFF                 @ R5 = Dato B

    /* Apagar D1 (PB13) y encender D2 (PB14) sin perder estados */
    LDR R0, =GPIOB_ODR
    LDR R1, [R0]
    BIC R1, R1, #(1 << 13)            @ Apaga D1
    ORR R1, R1, #(1 << 14)            @ Enciende D2
    STR R1, [R0]


/* --- 2. CÁLCULO Y MUESTRA DE LA SUMA --- */
    BL esperar_pulsacion              @ Espera la tercera pulsación en PC13

    ADD R6, R4, R5                    @ R6 = Dato A + Dato B

    /* Corrección de mapeo para saltar estrictamente PB2:
       - Bits [1:0] van a PB0 y PB1.
       - Bits [7:2] se desplazan 1 bit a la izquierda para ocupar PB3..PB8. */
    AND R2, R6, #0x03                 @ R2 = bits 0 y 1
    AND R3, R6, #0xFC                 @ R3 = bits 2 al 7
    LSL R3, R3, #1                    @ Desplaza para saltar PB2 (caen en PB3..PB8)
    ORR R2, R2, R3                    @ R2 unifica el resultado mapeado

    /* Actualizar GPIOB ODR limpiando solo los pines de resultado (PB0-PB1 y PB3-PB8) */
    LDR R0, =GPIOB_ODR
    LDR R1, [R0]

    LDR R3, =0x01FA                   @ Máscara exacta: bits 0,1 y 3..8 en 1 (PB2 = 0)
    BIC R1, R1, R3                    @ Limpia únicamente los pines de resultado viejos
    ORR R1, R1, R2                    @ Inserta el nuevo resultado calculado

    /* Gestionar LEDs indicadores D2 y D3 */
    BIC R1, R1, #(1 << 14)            @ Apaga D2 (PB14)
    ORR R1, R1, #(1 << 15)            @ Enciende D3 (PB15)
    STR R1, [R0]

    /* --- 3. REINICIO DE LA SECUENCIA --- */
    BL esperar_pulsacion              @ Espera la cuarta pulsación en PC13
    B inicio_proceso                  @ Vuelve a empezar


/* Bucle infinito de seguridad en caso de fallo */
bucle_espera:
    B bucle_espera


/* ====================================================================
   SUBRUTINA: esperar_pulsacion
   Sincroniza la lectura del pulsador PC13 (detecta presionar y soltar)
   ==================================================================== */
esperar_pulsacion:
    LDR R0, =GPIOC_IDR

esperar_cero:
    LDR R1, [R0]
    TST R1, #(1 << 13)
    BNE esperar_cero              @ Espera mientras PC13 sea 1 (reposo)

    /* Antirrebote al presionar */
    LDR R2, =8000
delay1:
    SUBS R2, R2, #1
    BNE delay1

esperar_uno:
    LDR R1, [R0]
    TST R1, #(1 << 13)
    BEQ esperar_uno               @ Espera mientras PC13 sea 0 (presionado)

    /* Antirrebote al soltar */
    LDR R2, =8000
delay2:
    SUBS R2, R2, #1
    BNE delay2

    BX LR
