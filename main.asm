; =============================================================================
; DONUT v2.0.0 - Dynamic Resizing & Auto-Centering
; =============================================================================
default rel
bits 64

section .data
    cls         db 27, "[2J", 0       
    home        db 27, "[H", 0        
    pause_msg   db 10, "Press ENTER to exit...", 0
    chars       db ".,-~:;=!*#$@", 0  

    float_0     dq 0.0
    float_1     dq 1.0
    float_2     dq 2.0
    float_5     dq 5.0
    float_8     dq 8.0
    float_15    dq 15.0
    float_30    dq 30.0
    
    pi2         dq 6.283185307        
    j_step      dq 0.07               
    i_step      dq 0.02               
    A_step      dq 0.04               
    B_step      dq 0.02               

section .bss
    ; Windows API Variables
    hConsole resq 1
    csbi     resb 24          ; CONSOLE_SCREEN_BUFFER_INFO struct
    cols     resd 1
    rows     resd 1
    x_offset resd 1
    y_offset resd 1
    area     resd 1
    r        resd 1
    c        resd 1

    ; Math Variables
    A resq 1
    B resq 1
    i resq 1
    j resq 1
    sinA resq 1
    cosA resq 1
    sinB resq 1
    cosB resq 1
    sinj resq 1
    cosj resq 1
    sini resq 1
    cosi resq 1
    h resq 1
    D resq 1
    t resq 1
    x_int resd 1
    y_int resd 1
    o_int resd 1
    N_int resd 1

    ; Dynamic Buffers (Max 500x500 resolution to prevent overflow)
    b resb 250000       
    z resq 250000       

section .text
    global main
    extern printf, Sleep, exit, getchar, sin, cos, memset, putchar
    extern GetStdHandle, GetConsoleScreenBufferInfo

main:
    sub rsp, 40          

    ; Get Console Handle for resizing logic
    mov rcx, -11         ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [hConsole], rax

    lea rcx,[cls]
    call printf

animation_loop:
    lea rcx,[home]
    call printf

    ; --- [DYNAMIC RESIZING LOGIC] ---
    mov rcx, [hConsole]
    lea rdx, [csbi]
    call GetConsoleScreenBufferInfo

    ; Calculate cols = srWindow.Right - srWindow.Left + 1
    movsx eax, word[csbi + 14]
    movsx ecx, word [csbi + 10]
    sub eax, ecx
    inc eax
    cmp eax, 0
    jg check_cols_max
    mov eax, 80          ; Fallback width
check_cols_max:
    cmp eax, 500
    jle set_cols
    mov eax, 500         ; Cap at 500
set_cols:
    mov [cols], eax

    ; Calculate rows = srWindow.Bottom - srWindow.Top + 1
    movsx eax, word [csbi + 16]
    movsx ecx, word [csbi + 12]
    sub eax, ecx
    inc eax
    cmp eax, 0
    jg check_rows_max
    mov eax, 22          ; Fallback height
check_rows_max:
    cmp eax, 500
    jle set_rows
    mov eax, 500         ; Cap at 500
set_rows:
    mov [rows], eax

    ; Calculate dynamic center offsets
    mov eax,[cols]
    shr eax, 1
    mov [x_offset], eax

    mov eax,[rows]
    shr eax, 1
    mov [y_offset], eax

    ; Calculate total area
    mov eax, [cols]
    imul eax, [rows]
    mov [area], eax

    ; Clear dynamic buffers
    lea rcx, [b]
    mov rdx, 32
    movsxd r8, dword [area]
    call memset

    lea rcx,[z]
    xor rdx, rdx
    movsxd r8, dword [area]
    shl r8, 3            ; Multiply by 8 for double precision
    call memset

    ; Precompute global angles
    movsd xmm0, [A]
    call sin
    movsd[sinA], xmm0
    movsd xmm0, [A]
    call cos
    movsd[cosA], xmm0
    movsd xmm0, [B]
    call sin
    movsd[sinB], xmm0
    movsd xmm0, [B]
    call cos
    movsd [cosB], xmm0

    movsd xmm0, [float_0]
    movsd [j], xmm0

loop_j:
    movsd xmm0, [j]
    ucomisd xmm0,[pi2]
    jae end_loop_j

    movsd xmm0, [j]
    call sin
    movsd [sinj], xmm0
    movsd xmm0, [j]
    call cos
    movsd [cosj], xmm0

    movsd xmm0,[float_0]
    movsd [i], xmm0

loop_i:
    movsd xmm0, [i]
    ucomisd xmm0, [pi2]
    jae end_loop_i

    movsd xmm0,[i]
    call sin
    movsd [sini], xmm0
    movsd xmm0,[i]
    call cos
    movsd [cosi], xmm0

    ; h = cos(j) + 2
    movsd xmm0, [cosj]
    addsd xmm0,[float_2]
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

    ; x = x_offset + 30 * D * (cos(i) * h * cos(B) - t * sin(B))
    movsd xmm0, [cosi]
    mulsd xmm0, [h]
    mulsd xmm0, [cosB]
    movsd xmm1, [t]
    mulsd xmm1, [sinB]
    subsd xmm0, xmm1
    mulsd xmm0, [D]
    mulsd xmm0, [float_30]
    cvttsd2si eax, xmm0         
    add eax, [x_offset]
    mov[x_int], eax

    ; y = y_offset + 15 * D * (cos(i) * h * sin(B) + t * cos(B))
    movsd xmm0,[cosi]
    mulsd xmm0, [h]
    mulsd xmm0,[sinB]
    movsd xmm1, [t]
    mulsd xmm1,[cosB]
    addsd xmm0, xmm1
    mulsd xmm0,[D]
    mulsd xmm0, [float_15]
    cvttsd2si eax, xmm0
    add eax, [y_offset]
    mov [y_int], eax

    ; o = x + cols * y
    mov eax,[y_int]
    imul eax, [cols]
    add eax, [x_int]
    mov [o_int], eax

    ; N = 8 * (...)
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

    ; Dynamic Bounds Checking
    mov eax, [y_int]
    cmp eax, 0
    jl skip_draw
    cmp eax, [rows]
    jge skip_draw

    mov eax, [x_int]
    cmp eax, 0
    jl skip_draw
    cmp eax, [cols]
    jge skip_draw

    ; Z-Buffer Check
    mov eax,[o_int]
    movsxd rcx, eax
    lea rdx, [z]
    movsd xmm0,[rdx + rcx*8]   
    movsd xmm1, [D]             
    ucomisd xmm1, xmm0          
    jbe skip_draw               

    movsd[rdx + rcx*8], xmm1

    ; Illumination
    mov eax,[N_int]
    cmp eax, 0
    jg check_N_max
    mov eax, 0                  
    jmp set_char
check_N_max:
    cmp eax, 11
    jle set_char
    mov eax, 11                 
set_char:
    lea rdx, [chars]
    mov al, [rdx + rax]
    movsxd rcx,[o_int]
    lea rdx, [b]
    mov[rdx + rcx], al

skip_draw:
    movsd xmm0, [i]
    addsd xmm0, [i_step]
    movsd [i], xmm0
    jmp loop_i

end_loop_i:
    movsd xmm0, [j]
    addsd xmm0,[j_step]
    movsd [j], xmm0
    jmp loop_j

end_loop_j:

    ; --- Render Dynamic Frame Buffer ---
    mov dword [r], 0
row_loop:
    mov eax, [r]
    cmp eax, [rows]
    jge end_row_loop

    mov dword [c], 0
col_loop:
    mov eax, [c]
    cmp eax, [cols]
    jge end_col_loop

    mov eax, [r]
    imul eax, [cols]
    add eax, [c]
    movsxd rax, eax
    lea rdx, [b]
    movzx rcx, byte[rdx + rax]
    call putchar

    inc dword [c]
    jmp col_loop

end_col_loop:
    ; Prevent terminal scrolling by skipping newline on the very last row
    mov eax, [r]
    mov ecx, [rows]
    dec ecx
    cmp eax, ecx
    jge skip_newline
    mov rcx, 10
    call putchar
skip_newline:
    inc dword [r]
    jmp row_loop

end_row_loop:

    ; Increment global rotation angles
    movsd xmm0, [A]
    addsd xmm0, [A_step]
    movsd [A], xmm0
    movsd xmm0, [B]
    addsd xmm0, [B_step]
    movsd [B], xmm0

    mov rcx, 30
    call Sleep
    jmp animation_loop

flush_buffer:
    call getchar
    cmp rax, 10      
    jne flush_buffer 
    lea rcx,[pause_msg]
    call printf
    call getchar     
    xor rcx, rcx
    add rsp, 40
    call exit