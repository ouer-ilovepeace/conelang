; cone 0.9.p - generated MASM32 assembly
.586
.model flat, stdcall
option casemap :none
option scoped
assume fs:nothing

include /data/workspace/masm32/include/windows.inc
include /data/workspace/masm32/include/kernel32.inc
includelib /data/workspace/masm32/lib/kernel32.lib
include /data/workspace/masm32/include/user32.inc
includelib /data/workspace/masm32/lib/user32.lib

.data?
fuck dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local val1:DWORD
    local val2:DWORD
    local val3:DWORD
    local val4:DWORD
    local val5:DWORD
    local val6:DWORD
    local val7:DWORD
    local f1:REAL4
    local f2:REAL4
    local f3:REAL4
    local val8:DWORD
    mov val1, 2
    mov val2, 20
    mov eax, val2
    mov ebx, 3
    xor edx, edx
    div ebx
    mov eax, edx
    mov val3, eax
    mov val4, 6
    mov val5, 2
    mov val6, 1
    mov val7, 3
    mov eax, dword ptr [__cone_flt_missing]
    mov f1, eax
    mov eax, val1
    mov ebx, val2
    xor edx, edx
    div ebx
    push eax
    mov eax, val2
    mov ebx, 3
    xor edx, edx
    div ebx
    mov eax, edx
    mov ebx, eax
    pop eax
    add eax, ebx
    mov f2, eax
    mov eax, val2
    mov ebx, 3
    xor edx, edx
    div ebx
    mov eax, edx
    mov f3, eax
    mov val8, -3
        mov eax, (BASE mod 3)
        mov ebx, val1
        mov ecx, 2
    invoke ExitProcess, val1
start endp

__cone_default_seh_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_default_seh_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_default_seh_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    invoke ExitProcess, fuck

__cone_default_entry:
    push 0
    push offset __cone_default_seh_handler
    push fs:[0]
    mov fs:[0], esp
    call start
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    ret

__cone_seh_ret_stub:
    ret

end __cone_default_entry
