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
include /data/workspace/masm32/include/mylib.inc
includelib /data/workspace/masm32/lib/mylib.lib
includelib /data/workspace/masm32/lib/os.lib
CRLF equ 0dh,0ah
TEXT equ <1+2*3,0dh,0ah>
print equ <crt_printf>
putw proto stdcall :WORD
putb proto stdcall :BYTE
takesptr proto stdcall :DWORD

.data
hello db "hello world!",0
fmt db "abcdefghijk"

.data?
fuck dd ?
__cone_itmp dd ?

.code
getidx proc stdcall uses ebx esi edi
    mov eax, 2
    ret
getidx endp

getw proc stdcall uses ebx esi edi
    local w:WORD
    ret
getw endp

start proc uses ebx esi edi
    local r:DWORD
    local p:DWORD
    local w:WORD
    local b:BYTE
    local buf[64]:BYTE
    mov eax, 5
    mov ebx, eax
    mov ecx, dword ptr [fmt]
    mov ax, bx
    mov al, 5
    mov si, ds
    mov b, al
    mov w, ax
    invoke takesptr, eax
    movzx ebx, al
    invoke takesptr, ebx
    mov eax, offset hello
    add eax, 11
    mov ecx, offset fmt
    sub ecx, 4
    mov ebx, r
    add ebx, 1
    mov edx, eax
    imul edx, 2
    add eax, 1
    mov r, eax
    dec eax
    mov byte ptr [fmt+4], 65
    mov word ptr [fmt], ax
    movzx ebx, b
    mov byte ptr [fmt+4], bl
    mov ebx, r
    mov dword ptr [fmt], ebx
    movzx ebx, w
    mov word ptr [buf+eax*2+8], bx
    mov ebx, r
    invoke getidx
    mov dword ptr [fmt+eax*4+8], ebx
    mov eax, dword ptr [fmt]
    mov r, eax
    movzx eax, word ptr [fmt]
    mov w, ax
    mov ebx, dword ptr [fmt]
    invoke takesptr, ebx
    mov eax, offset hello
    mov p, eax
    mov eax, p
    mov byte ptr [eax], 65
    mov ebx, eax
    lea esi, buf
    invoke takesptr, ebx, esi
    invoke getidx
    mov ebx, eax
    invoke takesptr, ebx, addr buf
    invoke putw, w
    invoke putb, b
    invoke print, offset fmt
    invoke print, eax, offset fmt
    invoke MessageBox, 0, offset fmt, offset fmt, 0
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
