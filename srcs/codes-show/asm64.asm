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
    db 44h,8Bh,0D2h
    db 65h,48h,8Bh,34h,25h,60h,00h,00h,00h
    db 48h,83h,0C6h,18h
    db 48h,83h,0C6h,18h
    db 0Fh,05h
again:
    db 0FFh,0C0h
    db 83h,0F8h,0Ah
    db 0Fh,82h,0F5h,0FFh,0FFh,0FFh
    db 83h,0F8h,00h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C0h
    db 0E9h,11h,00h,00h,00h
__cone_a64_0_1:
    db 83h,0F8h,01h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C8h
    db 0E9h,01h,00h,00h,00h
__cone_a64_0_2:
    db 90h
__cone_a64_0_0:
__cone_a64_0_3:
    db 83h,0F9h,0Ah
    db 0Fh,83h,07h,00h,00h,00h
    db 0FFh,0C1h
    db 0E9h,0F0h,0FFh,0FFh,0FFh
__cone_a64_0_4:
    db 83h,0F8h,01h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C0h
    db 0E9h,16h,00h,00h,00h
__cone_a64_0_6:
    db 83h,0F8h,02h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C8h
    db 0E9h,06h,00h,00h,00h
__cone_a64_0_7:
    db 90h
    db 0E9h,00h,00h,00h,00h
__cone_a64_0_5:
start proc uses ebx esi edi
    db 65h,48h,8Bh,04h,25h,60h,00h,00h,00h
    db 44h,8Bh,0D2h
    db 48h,83h,0C6h,18h
    db 0Fh,05h
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
