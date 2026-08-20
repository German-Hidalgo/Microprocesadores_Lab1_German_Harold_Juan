/* ====================================================================
   Proyecto: Sumador Multiplexado (Modificado con Ruteo para PB9)
   Target:   STM32F103 (Proteus / Blue Pill)
   Reloj:    HSI Interno (8 MHz)
   Descripción de Entradas/Salidas:
   - Entradas: PA0 - PA7  -> DIP Switch (Datos A y B)
   - Pulsador: PC13       -> Control de avance (Pull-Up)
   - Salidas:  PB0 - PB7  -> Resultado Suma (8 bits)
               PB8        -> Acarreo / Carry Out (1 bit)
               PB9        -> Salto físico del bit 2 de la suma
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

    /* 4. Configurar PB0-PB7 como Salidas Push-Pull 2MHz (0x22222222) */
    LDR R0, =GPIOB_CRL
    LDR R1, =0x22222222
    STR R1, [R0]

    /* 5. Configurar PB8, PB9, PB13, PB14 y PB15 como Salidas Push-Pull 2MHz */
    LDR R0, =GPIOB_CRH
    LDR R1, =0x22200022           @ PB15, PB14, PB13, PB9 y PB8 en modo salida
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
   DESARROLLO DE LA LÓGICA DE CAPTURA B, SUMA Y REINICIO
   ==================================================================== */

    /* --- 1. CAPTURA DEL DATO B --- */
    BL esperar_pulsacion              @ Espera la segunda pulsación en PC13

    LDR R0, =GPIOA_IDR
    LDR R5, [R0]
    AND R5, R5, #0xFF                 @ R5 = Dato B

    /* Apagar D1 (PB13) y encender D2 (PB14) respetando estados previos */
    LDR R0, =GPIOB_ODR
    LDR R1, [R0]
    BIC R1, R1, #(1 << 13)            @ Apaga D1
    ORR R1, R1, #(1 << 14)            @ Enciende D2
    STR R1, [R0]


    /* --- 2. CÁLCULO Y MUESTRA DE LA SUMA --- */
    BL esperar_pulsacion              @ Espera la tercera pulsación en PC13

    ADD R6, R4, R5                    @ R6 = Dato A + Dato B

    /* Parche de ruteo para lidiar con el pin PB2 (salto al pin PB9) */
    AND R2, R6, #(1 << 2)             @ Aisla el bit 2 de la suma
    BIC R6, R6, #(1 << 2)             @ Borra el bit 2 de su posición original en R6
    LSL R2, R2, #7                    @ Desplaza el bit 2 del índice 2 al índice 9 (PB9)
    ORR R6, R6, R2                    @ Reintegra el bit movido dentro del registro de resultado

/* Apagar D2 (PB14), encender D3 (PB15) y actualizar salidas del Puerto B */
    LDR R0, =GPIOB_ODR
    LDR R1, [R0]

    LDR R3, =0x01FF                   @ Carga la máscara completa de resultados (PB0-PB8 y PB9)
    BIC R1, R1, R3                    @ Limpia los pines anteriores de forma segura
    ORR R1, R1, R6                    @ Inserta la suma con su bit ruteado

    BIC R1, R1, #(1 << 14)            @ Apaga D2
    ORR R1, R1, #(1 << 15)            @ Enciende D3
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
