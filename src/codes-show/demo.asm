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
includelib /data/workspace/masm32/lib/os.lib
void typedef dword
print proto stdcall :void

.const
g REAL4 1.2
__cone_flt_0 REAL4 1.0

.data
hello db "hello world!",0,0,-11,0dh,0ah
a dd 1
d dd 9
fmt db "Windows Ver:%d.%d"

.data?
fuck dd ?
b db ?
output db 128 dup(?)
__cone_itmp dd ?

.code
adds proc stdcall uses ebx esi edi, x:DWORD, y:DWORD
    mov eax, x
    add eax, y
    ret
adds endp

start proc uses ebx esi edi
    local x:DWORD, y:DWORD
    local result:DWORD
    local z:REAL4
    invoke adds, x, y
    mov result, eax
    mov x, 10
    mov eax, x
    sub eax, 10
    mov y, eax
    mov eax, x
    mov ebx, y
    xor edx, edx
    div ebx
    mov z, eax
    fld z
    fld __cone_flt_0
    fmulp st(1), st(0)
    fstp z
    invoke wsprintf, offset output, offset fmt, x, y
    invoke print, offset hello
    invoke print, offset output
    invoke print, addr z
    invoke ExitProcess, 0
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
