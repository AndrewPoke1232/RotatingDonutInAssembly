default rel
bits 64

section .data
    ; ANSI Escape Codes
    cls         db 27, "[2J", 0       ; Clear Screen
    home        db 27, "[H", 0        ; Move cursor to top-left
    
    ; Strings
    pause_msg   db 10, "Press ENTER to exit...", 0
    chars       db ".,-~:;=!*#$@", 0  ; Illumination characters (12 chars)

    ; Floating Point Constants (Double Precision)
    float_0     dq 0.0
    float_1     dq 1.0
    float_2     dq 2.0
    float_5     dq 5.0
    float_8     dq 8.0
    float_12    dq 12.0
    float_15    dq 15.0
    float_30    dq 30.0
    float_40    dq 40.0
    
    pi2         dq 6.283185307        ; 2 * Pi
    j_step      dq 0.07               ; Theta step
    i_step      dq 0.02               ; Phi step
    A_step      dq 0.04               ; X-axis rotation step
    B_step      dq 0.02               ; Z-axis rotation step

section .bss
    ; Global Rotation Angles
    A resq 1
    B resq 1
    
    ; Loop Variables
    i resq 1
    j resq 1

    ; Precomputed Trigonometry for the current frame/loop
    sinA resq 1
    cosA resq 1
    sinB resq 1
    cosB resq 1
    sinj resq 1
    cosj resq 1
    sini resq 1
    cosi resq 1

    ; Intermediate Math Variables
    h resq 1
    D resq 1
    t resq 1

    ; Integer Coordinates and Indices
    x_int resd 1
    y_int resd 1
    o_int resd 1
    N_int resd 1
    k     resd 1

    ; Buffers
    b resb 1760       ; Frame buffer (80 * 22 = 1760 bytes)
    z resq 1760       ; Z-buffer (1760 doubles = 14080 bytes)

section .text
    global main
    extern printf
    extern Sleep
    extern exit
    extern getchar
    extern sin
    extern cos
    extern memset
    extern putchar

main:
    ; --- Stack Alignment (Crucial for Windows x64) ---
    sub rsp, 40          ; Reserve shadow space + align

    ; 1. Clear the screen once at the start
    lea rcx,[cls]
    call printf

animation_loop:
    ; 2. Move cursor to top (prevents flickering)
    lea rcx, [home]
    call printf

    ; --- [DRAWING LOGIC START] ---
    
    ; Clear frame buffer: memset(b, 32, 1760) -> 32 is ASCII space ' '
    lea rcx, [b]
    mov rdx, 32
    mov r8, 1760
    call memset

    ; Clear Z-buffer: memset(z, 0, 1760 * 8) -> IEEE 754 double 0.0 is all zero bytes
    lea rcx, [z]
    xor rdx, rdx
    mov r8, 14080
    call memset

    ; Precompute sin and cos for angles A and B
    movsd xmm0, [A]
    call sin
    movsd[sinA], xmm0

    movsd xmm0, [A]
    call cos
    movsd [cosA], xmm0

    movsd xmm0, [B]
    call sin
    movsd [sinB], xmm0

    movsd xmm0, [B]
    call cos
    movsd [cosB], xmm0

    ; Initialize j = 0.0
    movsd xmm0, [float_0]
    movsd [j], xmm0

loop_j:
    movsd xmm0, [j]
    ucomisd xmm0,[pi2]
    jae end_loop_j

    ; Precompute sin(j) and cos(j)
    movsd xmm0, [j]
    call sin
    movsd [sinj], xmm0

    movsd xmm0, [j]
    call cos
    movsd [cosj], xmm0

    ; Initialize i = 0.0
    movsd xmm0,[float_0]
    movsd [i], xmm0

loop_i:
    movsd xmm0, [i]
    ucomisd xmm0, [pi2]
    jae end_loop_i

    ; Compute sin(i) and cos(i)
    movsd xmm0, [i]
    call sin
    movsd [sini], xmm0

    movsd xmm0,[i]
    call cos
    movsd [cosi], xmm0

    ; --- Mathematics Core ---
    
    ; h = cos(j) + 2
    movsd xmm0, [cosj]
    addsd xmm0, [float_2]
    movsd [h], xmm0

    ; D = 1 / (sin(i) * h * sin(A) + sin(j) * cos(A) + 5)
    movsd xmm0, [sini]
    mulsd xmm0, [h]
    mulsd xmm0, [sinA]
    movsd xmm1, [sinj]
    mulsd xmm1, [cosA]
    addsd xmm0, xmm1
    addsd xmm0, [float_5]
    movsd xmm1, [float_1]
    divsd xmm1, xmm0
    movsd[D], xmm1

    ; t = sin(i) * h * cos(A) - sin(j) * sin(A)
    movsd xmm0, [sini]
    mulsd xmm0, [h]
    mulsd xmm0, [cosA]
    movsd xmm1, [sinj]
    mulsd xmm1, [sinA]
    subsd xmm0, xmm1
    movsd [t], xmm0

    ; x = 40 + 30 * D * (cos(i) * h * cos(B) - t * sin(B))
    movsd xmm0, [cosi]
    mulsd xmm0, [h]
    mulsd xmm0, [cosB]
    movsd xmm1, [t]
    mulsd xmm1, [sinB]
    subsd xmm0, xmm1
    mulsd xmm0, [D]
    mulsd xmm0, [float_30]
    addsd xmm0, [float_40]
    cvttsd2si eax, xmm0         ; Truncate float to int
    mov [x_int], eax

    ; y = 12 + 15 * D * (cos(i) * h * sin(B) + t * cos(B))
    movsd xmm0, [cosi]
    mulsd xmm0, [h]
    mulsd xmm0, [sinB]
    movsd xmm1, [t]
    mulsd xmm1, [cosB]
    addsd xmm0, xmm1
    mulsd xmm0, [D]
    mulsd xmm0, [float_15]
    addsd xmm0,[float_12]
    cvttsd2si eax, xmm0
    mov [y_int], eax

    ; o = x + 80 * y (1D array index)
    mov eax,[y_int]
    imul eax, 80
    add eax, [x_int]
    mov [o_int], eax

    ; N = 8 * ((sin(j)*sin(A) - sin(i)*cos(j)*cos(A))*cos(B) - sin(i)*cos(j)*sin(A) - sin(j)*cos(A) - cos(i)*cos(j)*sin(B))
    movsd xmm0, [sinj]
    mulsd xmm0, [sinA]
    movsd xmm1, [sini]
    mulsd xmm1, [cosj]
    mulsd xmm1, [cosA]
    subsd xmm0, xmm1
    mulsd xmm0, [cosB]
    movsd xmm2, [sini]
    mulsd xmm2, [cosj]
    mulsd xmm2, [sinA]
    movsd xmm3, [sinj]
    mulsd xmm3, [cosA]
    movsd xmm4, [cosi]
    mulsd xmm4, [cosj]
    mulsd xmm4, [sinB]
    subsd xmm0, xmm2
    subsd xmm0, xmm3
    subsd xmm0, xmm4
    mulsd xmm0, [float_8]
    cvttsd2si eax, xmm0
    mov [N_int], eax

    ; Bounds Checking: if (22 > y && y > 0 && x > 0 && 80 > x && D > z[o])
    mov eax, [y_int]
    cmp eax, 0
    jle skip_draw
    cmp eax, 22
    jge skip_draw

    mov eax, [x_int]
    cmp eax, 0
    jle skip_draw
    cmp eax, 80
    jge skip_draw

    ; Z-Buffer Check
    mov eax,[o_int]
    movsxd rcx, eax
    lea rdx, [z]
    movsd xmm0, [rdx + rcx*8]   ; Load current z[o]
    movsd xmm1, [D]             ; Load new D
    ucomisd xmm1, xmm0          ; Compare D with z[o]
    jbe skip_draw               ; Jump if D <= z[o]

    ; Update Z-buffer: z[o] = D
    movsd[rdx + rcx*8], xmm1

    ; Illumination Character Selection: b[o] = chars[N > 0 ? N : 0]
    mov eax, [N_int]
    cmp eax, 0
    jg check_N_max
    mov eax, 0                  ; Cap minimum at 0
    jmp set_char
check_N_max:
    cmp eax, 11
    jle set_char
    mov eax, 11                 ; Cap maximum at 11
set_char:
    lea rdx, [chars]
    mov al, [rdx + rax]
    movsxd rcx, [o_int]
    lea rdx, [b]
    mov[rdx + rcx], al

skip_draw:
    ; i += 0.02
    movsd xmm0, [i]
    addsd xmm0, [i_step]
    movsd [i], xmm0
    jmp loop_i

end_loop_i:
    ; j += 0.07
    movsd xmm0, [j]
    addsd xmm0,[j_step]
    movsd [j], xmm0
    jmp loop_j

end_loop_j:

    ; --- Render Frame Buffer to Console ---
    mov dword [k], 0
print_loop:
    mov eax, [k]
    cmp eax, 1760
    jge end_print_loop

    ; Print character at b[k]
    movsxd rax, dword[k]
    lea rdx, [b]
    movzx rcx, byte[rdx + rax]
    call putchar

    ; Check if we reached the end of the row (80 columns)
    mov eax, [k]
    inc eax
    mov ecx, 80
    cdq
    idiv ecx
    cmp edx, 0
    jne next_k

    ; Print newline
    mov rcx, 10
    call putchar

next_k:
    inc dword[k]
    jmp print_loop

end_print_loop:

    ; Increment global rotation angles
    movsd xmm0, [A]
    addsd xmm0, [A_step]
    movsd [A], xmm0

    movsd xmm0, [B]
    addsd xmm0, [B_step]
    movsd [B], xmm0

    ; ---[DRAWING LOGIC END] ---

    ; 3. Wait 30 milliseconds (prevents 100% CPU usage and stabilizes frame rate)
    mov rcx, 30
    call Sleep

    ; 4. Repeat Forever
    jmp animation_loop

    ; --- Clean Exit (Unreachable in infinite loop unless interrupted) ---
flush_buffer:
    call getchar
    cmp rax, 10      
    jne flush_buffer 

    lea rcx, [pause_msg]
    call printf
    call getchar     

    xor rcx, rcx
    add rsp, 40
    call exit