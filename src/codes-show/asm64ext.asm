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
    db 48h,0Fh,0A4h,0D2h,20h
    db 0FCh
    db 0F3h,0A4h
    db 0CBh
    db 0F3h,48h,0A5h
    db 66h,0F3h,0A5h
    db 0F3h,48h,0ABh
    db 0F3h,0A6h
    db 0F2h,0AEh
    db 0A4h
    db 0A5h
    db 0AAh
    db 0ADh
    db 48h,0A7h
    db 48h,0AFh
    db 6Dh
    db 6Eh
    db 0F8h
    db 0F9h
    db 0FAh
    db 0FBh
    db 0FDh
    db 0F5h
    db 9Fh
    db 9Eh
    db 0D7h
    db 0F1h
    db 0Fh,0A2h
    db 0Fh,31h
    db 0Fh,01h,0F9h
    db 0Fh,33h
    db 0Fh,34h
    db 0Fh,35h
    db 0Fh,01h,0F8h
    db 0F3h,90h
    db 0Fh,08h
    db 0Fh,09h
    db 0Fh,01h,0C8h
    db 0Fh,01h,0C9h
    db 0CAh,08h,00h
    db 0C3h
    db 0C2h,10h,00h
    db 0CFh
    db 66h,0CFh
    db 48h,0CFh
    db 0C8h,10h,00h,00h
    db 0Fh,0A4h,0D8h,04h
    db 48h,0Fh,0A5h,0D8h
    db 48h,0Fh,0ACh,0D2h,20h
    db 0Fh,0ACh,0D8h,04h
    db 48h,0Fh,0ADh,0D8h
    db 48h,0Fh,0BCh,0C3h
    db 0Fh,0BDh,0C1h
    db 0F3h,48h,0Fh,0B8h,0C3h
    db 0F3h,48h,0Fh,0BDh,0C3h
    db 0F3h,48h,0Fh,0BCh,0C3h
    db 0F3h,0Fh,0B8h,03h
    db 48h,0Fh,0C1h,0D8h
    db 0Fh,0C1h,0C8h
    db 48h,0Fh,0B1h,0D8h
    db 0Fh,0C7h,08h
    db 48h,0Fh,0C7h,08h
    db 0F0h,48h,0Fh,0C1h,18h
    db 0F0h,48h,83h,00h,01h
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
