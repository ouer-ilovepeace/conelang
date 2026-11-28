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
    db 83h,0F8h,00h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C0h
    db 0E9h,20h,00h,00h,00h
__cone_a64_0_1:
    db 83h,0F8h,01h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C8h
    db 0E9h,10h,00h,00h,00h
__cone_a64_0_2:
    db 83h,0F8h,02h
    db 0Fh,85h,06h,00h,00h,00h
    db 90h
    db 0E9h,01h,00h,00h,00h
__cone_a64_0_3:
    db 0F4h
__cone_a64_0_0:
    db 83h,0F8h,03h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C0h
    db 0E9h,01h,00h,00h,00h
__cone_a64_0_5:
    db 90h
__cone_a64_0_4:
    db 83h,0F9h,00h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C1h
    db 0E9h,11h,00h,00h,00h
__cone_a64_0_7:
    db 83h,0F9h,01h
    db 0Fh,85h,07h,00h,00h,00h
    db 0FFh,0C9h
    db 0E9h,01h,00h,00h,00h
__cone_a64_0_8:
    db 90h
__cone_a64_0_6:
    db 83h,0F8h,05h
    db 0Fh,86h,10h,00h,00h,00h
    db 83h,0FBh,0Ah
    db 0Fh,83h,07h,00h,00h,00h
    db 31h,0C0h
    db 0E9h,2Fh,00h,00h,00h
__cone_a64_0_10:
    db 83h,0FAh,00h
    db 0Fh,8Fh,0Eh,00h,00h,00h
    db 83h,0F9h,00h
    db 0Fh,84h,05h,00h,00h,00h
    db 0E9h,07h,00h,00h,00h
__cone_a64_0_12:
    db 0FFh,0C2h
    db 0E9h,11h,00h,00h,00h
__cone_a64_0_11:
    db 83h,0FEh,64h
    db 0Fh,82h,07h,00h,00h,00h
    db 0FFh,0CEh
    db 0E9h,01h,00h,00h,00h
__cone_a64_0_13:
    db 90h
__cone_a64_0_9:
__cone_a64_0_14:
    db 83h,0F9h,08h
    db 0Fh,83h,23h,00h,00h,00h
    db 83h,0F9h,02h
    db 0Fh,85h,05h,00h,00h,00h
    db 0E9h,0E9h,0FFh,0FFh,0FFh
__cone_a64_0_17:
__cone_a64_0_16:
    db 83h,0F9h,06h
    db 0Fh,85h,05h,00h,00h,00h
    db 0E9h,07h,00h,00h,00h
__cone_a64_0_19:
__cone_a64_0_18:
    db 0FFh,0C1h
    db 0E9h,0D4h,0FFh,0FFh,0FFh
__cone_a64_0_15:
start proc uses ebx esi edi
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
