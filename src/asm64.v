module main

// cone 0.9preview : asm64{} —— x64 指令 -> 机器码字节 编码器（MASM32 db 行）
// 与参考实现 _eq6.py 的 _a64code.py 逐函数对齐。

// ---------- 通用工具 ----------

fn a64_hx(b int) string {
	digs := '0123456789ABCDEF'
	v := b & 255
	hi := (v >> 4) & 15
	lo := v & 15
	mut h := digs[hi..hi + 1] + digs[lo..lo + 1]
	if hi >= 10 {
		h = '0' + h
	}
	return h + 'h'
}

fn a64_trim(s string) string {
	mut a := 0
	mut b := s.len
	for a < b && (s[a] == 32 || s[a] == 9 || s[a] == 13 || s[a] == 10) {
		a = a + 1
	}
	for b > a && (s[b - 1] == 32 || s[b - 1] == 9 || s[b - 1] == 13 || s[b - 1] == 10) {
		b = b - 1
	}
	return s[a..b]
}

fn a64_lower(s string) string {
	lows := 'abcdefghijklmnopqrstuvwxyz'
	mut r := ''
	mut i := 0
	for i < s.len {
		c := s[i]
		if c >= 65 && c <= 90 {
			k := int(c - 65)
			r = r + lows[k..k + 1]
		} else {
			r = r + s[i..i + 1]
		}
		i = i + 1
	}
	return r
}

fn a64_eq(a string, b string) bool {
	return a64_lower(a) == a64_lower(b)
}

fn a64_is_digit(c u8) bool {
	return c >= 48 && c <= 57
}

fn a64_is_hex(c u8) bool {
	return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
}

fn a64_digit(c u8) int {
	if c >= 48 && c <= 57 {
		return int(c - 48)
	}
	if c >= 65 && c <= 70 {
		return int(c - 55)
	}
	return int(c - 87)
}

fn a64_num(t0 string) !i64 {
	mut t := a64_trim(t0)
	mut neg := false
	if t.len > 0 && t[0] == 45 {
		neg = true
		t = t[1..]
	} else if t.len > 0 && t[0] == 43 {
		t = t[1..]
	}
	if t.len == 0 {
		return error('空数值')
	}
	mut base := i64(10)
	mut body := t
	if t.len > 1 && (t[t.len - 1] == 104 || t[t.len - 1] == 72) {
		base = 16
		body = t[..t.len - 1]
	} else if t.len > 2 && t[0] == 48 && (t[1] == 120 || t[1] == 88) {
		base = 16
		body = t[2..]
	}
	mut v := i64(0)
	mut i := 0
	for i < body.len {
		c := body[i]
		if base == 16 {
			if !a64_is_hex(c) {
				return error('非法十六进制数 ${t0}')
			}
			v = v * base + i64(a64_digit(c))
		} else {
			if !a64_is_digit(c) {
				return error('非法十进制数 ${t0}')
			}
			v = v * base + i64(a64_digit(c))
		}
		i = i + 1
	}
	if neg {
		return -v
	}
	return v
}

fn a64_find(s string, sub string) int {
	if sub.len == 0 || s.len < sub.len {
		return -1
	}
	mut i := 0
	for i + sub.len <= s.len {
		mut ok := true
		mut j := 0
		for j < sub.len {
			if s[i + j] != sub[j] {
				ok = false
				break
			}
			j = j + 1
		}
		if ok {
			return i
		}
		i = i + 1
	}
	return -1
}

fn a64_strip_comment(line string) string {
	mut q := 0
	mut i := 0
	for i < line.len {
		c := line[i]
		if q != 0 {
			if c == 92 {
				i = i + 2
				continue
			}
			if c == q {
				q = 0
			}
		} else {
			if c == 34 || c == 39 {
				q = int(c)
			} else if c == 59 {
				return line[..i]
			}
		}
		i = i + 1
	}
	return line
}

fn a64_expand(body string) []string {
	mut out := []string{}
	mut li := 0
	mut raw_lines := body.split('\n')
	for li < raw_lines.len {
		s := a64_trim(a64_strip_comment(raw_lines[li]))
		if s.len > 0 {
			mut buf := ''
			mut ci := 0
			for ci < s.len {
				c := s[ci]
				if c == 123 {
					if buf.len > 0 {
						apv := a64_trim(buf) + '{'
						out << apv
					} else {
						out << '{'
					}
					buf = ''
				} else if c == 125 {
					if a64_trim(buf).len > 0 {
						out << a64_trim(buf)
					}
					out << '}'
					buf = ''
				} else {
					buf = buf + s[ci..ci + 1]
				}
				ci = ci + 1
			}
			if a64_trim(buf).len > 0 {
				out << a64_trim(buf)
			}
		}
		li = li + 1
	}
	return out
}

// ---------- 操作数 ----------

struct A64Operand {
mut:
	kind       int // 0 imm, 1 reg, 2 mem, 3 label
	text       string
	seg        int
	hint       int
	reg        int
	size       int
	imm        i64
	label      string
	base       int
	has_base   bool
	index      int
	has_index  bool
	scale      int
	disp       i64
}

struct A64Parts {
mut:
	seg       int
	p66       bool
	rex_w     bool
	rex_r     bool
	rex_x     bool
	rex_b     bool
	force_rex bool
	op        []int
	modrm     []int
	imm       []int
}

struct A64Result {
mut:
	bytes []int
	kind  int // 0 bytes, 1 jmp rel, 2 call rel, 3 jcc rel
	label string
	cc    int
}

fn a64_np(size int) A64Parts {
	return A64Parts{
		seg:       0
		p66:       size == 16
		rex_w:     size == 64
		op:        []int{}
		modrm:     []int{}
		imm:       []int{}
	}
}

fn a64_imm(v i64, n int) []int {
	mut out := []int{}
	mut x := v
	mut i := 0
	for i < n {
		out << int(x & 255)
		x = x >> 8
		i = i + 1
	}
	return out
}

fn a64_build(p A64Parts) []int {
	mut out := []int{}
	if p.seg != 0 {
		out << p.seg
	}
	if p.p66 {
		out << 0x66
	}
	// cone 0.9preview3：op 开头的 F0/F2/F3 前缀必须在 REX 之前（REX 要紧邻 opcode）。
	mut oi := 0
	for oi < p.op.len {
		is_pfx := p.op[oi] == 0xF0 || p.op[oi] == 0xF2 || p.op[oi] == 0xF3
		if !is_pfx {
			break
		}
		out << p.op[oi]
		oi = oi + 1
	}
	mut rv := 0x40
	if p.rex_w {
		rv = rv + 8
	}
	if p.rex_r {
		rv = rv + 4
	}
	if p.rex_x {
		rv = rv + 2
	}
	if p.rex_b {
		rv = rv + 1
	}
	if rv != 0x40 || p.force_rex {
		out << rv
	}
	for oi < p.op.len {
		out << p.op[oi]
		oi = oi + 1
	}
	for x in p.modrm {
		out << x
	}
	for x in p.imm {
		out << x
	}
	return out
}

struct A64Enc {
mut:
	regnum   map[string]int
	regsz    map[string]int
	items    []A64Item
	labels   map[string]int
	total    int
	lid      int
	prefix   string
	stack    []A64Frame
}

struct A64Item {
mut:
	text   string
	nbytes int
	start  int
	bytes  []int
	plabel string
	pat    int
}

struct A64Frame {
mut:
	kind        int // 1 if, 2 for, 3 match, 4 case
	end_lbl     string
	nxt         string
	has_nxt     bool
	cond_lbl    string
	discr       string
	pending     string
	has_pending bool
	match_end   string
}

fn a64_new_enc(prefix string) A64Enc {
	mut e := A64Enc{
		regnum: map[string]int{}
		regsz:  map[string]int{}
		items:  []A64Item{}
		labels: map[string]int{}
		prefix: prefix
		stack:  []A64Frame{}
	}
	g := ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi', 'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15']
	d := ['eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi', 'r8d', 'r9d', 'r10d', 'r11d', 'r12d', 'r13d', 'r14d', 'r15d']
	w := ['ax', 'cx', 'dx', 'bx', 'sp', 'bp', 'si', 'di', 'r8w', 'r9w', 'r10w', 'r11w', 'r12w', 'r13w', 'r14w', 'r15w']
	b := ['al', 'cl', 'dl', 'bl', 'spl', 'bpl', 'sil', 'dil', 'r8b', 'r9b', 'r10b', 'r11b', 'r12b', 'r13b', 'r14b', 'r15b']
	for i, n in g {
		e.regnum[n] = i
		e.regsz[n] = 64
	}
	for i, n in d {
		e.regnum[n] = i
		e.regsz[n] = 32
	}
	for i, n in w {
		e.regnum[n] = i
		e.regsz[n] = 16
	}
	for i, n in b {
		e.regnum[n] = i
		e.regsz[n] = 8
	}
	return e
}

fn (mut e A64Enc) reg_info(name string) (int, int, bool) {
	k := a64_lower(name)
	if k in e.regnum {
		return e.regnum[k], e.regsz[k], true
	}
	return 0, 0, false
}

fn a64_mem_tokens(inner string) []string {
	mut out := []string{}
	mut cur := ''
	mut i := 0
	for i < inner.len {
		c := inner[i]
		if (c == 43 || c == 45) && cur.len > 0 {
			out << cur
			cur = ''
		}
		cur = cur + inner[i..i + 1]
		i = i + 1
	}
	if cur.len > 0 {
		out << cur
	}
	return out
}

fn (mut e A64Enc) parse_mem(inner0 string, seg int) !A64Operand {
	inner := a64_trim(inner0)
	mut o := A64Operand{
		kind:  2
		seg:   seg
		scale: 1
	}
	toks := a64_mem_tokens(inner)
	for tk0 in toks {
		mut tk := a64_trim(tk0)
		mut sg := i64(1)
		if tk.len > 0 && tk[0] == 43 {
			tk = a64_trim(tk[1..])
		} else if tk.len > 0 && tk[0] == 45 {
			sg = -1
			tk = a64_trim(tk[1..])
		}
		if tk.len == 0 {
			continue
		}
		star := a64_find(tk, '*')
		if star >= 0 {
			a := a64_trim(tk[..star])
			bp := a64_trim(tk[star + 1..])
			mut idx := -1
			mut sc := i64(1)
			rn, _, ok := e.reg_info(a)
			if ok {
				idx = rn
				sc = a64_num(bp) or { return error('asm64 内存寻址比例项无法解析: ${tk}') }
			} else {
				rn2, _, ok2 := e.reg_info(bp)
				if ok2 {
					idx = rn2
					sc = a64_num(a) or { return error('asm64 内存寻址比例项无法解析: ${tk}') }
				} else {
					return error('asm64 内存寻址比例项无法解析: ${tk}')
				}
			}
			if sc != 1 && sc != 2 && sc != 4 && sc != 8 {
				return error('asm64 内存比例只能是 1/2/4/8: ${tk}')
			}
			o.has_index = true
			o.index = idx
			o.scale = int(sc)
		} else {
			rn, _, ok := e.reg_info(tk)
			if ok {
				o.has_base = true
				o.base = rn
			} else if a64_eq(tk, 'rip') {
				return error('asm64 不支持 [rip+...] 重定位')
			} else {
				v := a64_num(tk) or { return error('asm64 内存偏移必须是编译期数值: ${tk}') }
				o.disp = o.disp + sg * v
			}
		}
	}
	return o
}

fn (mut e A64Enc) parse_op(t0 string) !A64Operand {
	mut t := a64_trim(t0)
	mut o := A64Operand{
		kind:  0
		text:  t0
		scale: 1
	}
	// 段前缀
	segs := ['gs', 'fs', 'cs', 'ss', 'ds', 'es']
	segc := [0x65, 0x64, 0x2E, 0x36, 0x3E, 0x26]
	mut si := 0
	for si < segs.len {
		pre := segs[si] + ':'
		if t.len > pre.len && a64_eq(t[..pre.len], pre) {
			o.seg = segc[si]
			t = a64_trim(t[pre.len..])
			break
		}
		si = si + 1
	}
	// size ptr
	ptrs := ['byte ptr ', 'word ptr ', 'dword ptr ', 'qword ptr ']
	ptrsz := [8, 16, 32, 64]
	mut pi := 0
	for pi < ptrs.len {
		pre := ptrs[pi]
		if t.len > pre.len && a64_eq(t[..pre.len], pre) {
			o.hint = ptrsz[pi]
			t = a64_trim(t[pre.len..])
			break
		}
		pi = pi + 1
	}
	if t.len >= 2 && t[0] == 91 && t[t.len - 1] == 93 {
		return e.parse_mem(t[1..t.len - 1], o.seg)
	}
	rn, rs, ok := e.reg_info(t)
	if ok {
		o.kind = 1
		o.reg = rn
		o.size = rs
		return o
	}
	v := a64_num(t) or {
		o.kind = 3
		o.label = t
		return o
	}
	o.imm = v
	return o
}

fn (mut e A64Enc) modrm(rm A64Operand, regfield int, mut p A64Parts, size int) {
	if rm.kind == 1 {
		if (rm.reg >> 3) & 1 == 1 {
			p.rex_b = true
		}
		if (regfield >> 3) & 1 == 1 {
			p.rex_r = true
		}
		if size == 8 && (rm.reg == 4 || rm.reg == 5 || rm.reg == 6 || rm.reg == 7) {
			p.force_rex = true
		}
		if size == 8 && (regfield == 4 || regfield == 5 || regfield == 6 || regfield == 7) {
			p.force_rex = true
		}
		mv := 0xC0 | a64_shl(regfield & 7, 3) | (rm.reg & 7)
		p.modrm << mv
		return
	}
	p.seg = rm.seg
	mut base := rm.base
	mut index := rm.index
	mut scale := rm.scale
	disp := rm.disp
	if rm.has_base && (base >> 3) & 1 == 1 {
		p.rex_b = true
	}
	if rm.has_index && (index >> 3) & 1 == 1 {
		p.rex_x = true
	}
	mut mod := 0
	mut rm_bits := 0
	mut dm := []int{}
	mut db := []int{}
	if !rm.has_base {
		mod = 0
		rm_bits = 4
		if !rm.has_index {
			dm << 0x25
		} else {
			sc := a64_scale_bits(scale)
			sbv := a64_shl(sc, 6) | a64_shl(index & 7, 3) | 5
			dm << sbv
		}
		db = a64_imm(disp, 4)
	} else if rm.has_index || (base & 7) == 4 {
		if disp == 0 && (base & 7) != 5 {
			mod = 0
		} else if disp >= i64(-128) && disp <= i64(127) {
			mod = 1
			db = a64_imm(disp, 1)
		} else {
			mod = 2
			db = a64_imm(disp, 4)
		}
		sc := a64_scale_bits(scale)
		mut ib := 4
		if rm.has_index {
			ib = index & 7
		}
		sbv := a64_shl(sc, 6) | a64_shl(ib, 3) | (base & 7)
		dm << sbv
		rm_bits = 4
	} else {
		if disp == 0 && (base & 7) != 5 {
			mod = 0
		} else if disp >= i64(-128) && disp <= i64(127) {
			mod = 1
			db = a64_imm(disp, 1)
		} else {
			mod = 2
			db = a64_imm(disp, 4)
		}
		rm_bits = base & 7
	}
	if (regfield >> 3) & 1 == 1 {
		p.rex_r = true
	}
	mmv := a64_shl(mod, 6) | a64_shl(regfield & 7, 3) | rm_bits
	p.modrm << mmv
	for x in dm {
		p.modrm << x
	}
	for x in db {
		p.modrm << x
	}
}

// cone 0.9preview2：用无符号类型做左移，消除 V 0.5.2 对 int 左移的
// "shifting a value from a signed type int can change the sign" notice。
// 这里所有移位量都 <= 6、被移位值都已 &7 / <=3，结果恒在 0..255，语义完全等价。
fn a64_shl(v int, n int) int {
	return int(u32(v) << u32(n))
}

fn a64_scale_bits(scale int) int {
	if scale == 2 {
		return 1
	}
	if scale == 4 {
		return 2
	}
	if scale == 8 {
		return 3
	}
	return 0
}

fn (mut e A64Enc) size_of(ops []A64Operand) int {
	for o in ops {
		if o.kind == 1 {
			return o.size
		}
	}
	for o in ops {
		if o.hint != 0 {
			return o.hint
		}
	}
	return 32
}

fn a64_split(line string) (string, []string) {
	s := a64_trim(line)
	if s.len == 0 {
		return '', []string{}
	}
	mut sp := -1
	mut i := 0
	for i < s.len {
		if s[i] == 32 || s[i] == 9 {
			sp = i
			break
		}
		i = i + 1
	}
	if sp < 0 {
		return s, []string{}
	}
	m := s[..sp]
	rest := a64_trim(s[sp..])
	mut args := []string{}
	mut depth := 0
	mut cur := ''
	mut j := 0
	for j < rest.len {
		c := rest[j]
		if c == 91 {
			depth = depth + 1
		} else if c == 93 {
			depth = depth - 1
		}
		if c == 44 && depth == 0 {
			args << a64_trim(cur)
			cur = ''
		} else {
			cur = cur + rest[j..j + 1]
		}
		j = j + 1
	}
	if a64_trim(cur).len > 0 {
		args << a64_trim(cur)
	}
	return m, args
}

fn a64_jcc_code(m string) int {
	tbl := ['jo', 'jno', 'jb', 'jae', 'je', 'jne', 'jbe', 'ja', 'js', 'jns', 'jp', 'jnp', 'jl', 'jge', 'jle', 'jg']
	alias := ['jnae', 'jc', 'jnb', 'jnc', 'jz', 'jnz', 'jna', 'jnbe', 'jpe', 'jpo', 'jnge', 'jnl', 'jng', 'jnle']
	aliasc := [2, 2, 3, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15]
	mut i := 0
	for i < tbl.len {
		if m == tbl[i] {
			return i
		}
		i = i + 1
	}
	mut k := 0
	for k < alias.len {
		if m == alias[k] {
			return aliasc[k]
		}
		k = k + 1
	}
	return -1
}

fn (mut e A64Enc) encode(m0 string, args []string) !A64Result {
	mut m := a64_lower(m0)
	mut real_args := args.clone()
	// cone 0.9preview3：前缀助记符 rep / repe / repne / lock + 后续指令。
	// 例如 "rep movsb" 重写成 "movsb" + F3 前缀字节；args[0] 可能含空格，重新 a64_split。
	mut hint := 0
	if args.len > 0 {
		if m == 'lock' {
			hint = 0xF0
		} else if m == 'rep' || m == 'repe' || m == 'repz' {
			hint = 0xF3
		} else if m == 'repne' || m == 'repnz' {
			hint = 0xF2
		}
		if hint != 0 {
			mm, aa := a64_split(args.join(','))
			m = a64_lower(mm)
			real_args = aa.clone()
		}
	}
	mut ops := []A64Operand{}
	for a in real_args {
		ops << e.parse_op(a) or { return error(err.msg()) }
	}
	mut n := ops.len
	mut prefix := 0
	for n > 0 && ops[0].kind == 3 {
		pf := a64_lower(ops[0].label)
		if pf == 'lock' {
			prefix = 0xF0
		} else if pf == 'rep' || pf == 'repe' || pf == 'repz' {
			prefix = 0xF3
		} else if pf == 'repne' || pf == 'repnz' {
			prefix = 0xF2
		} else {
			break
		}
		ops = ops[1..].clone()
		n = n - 1
	}
	sz := e.size_of(ops)
	mut p := a64_np(sz)
	if prefix != 0 || hint != 0 {
		if prefix != 0 {
			p.op << prefix
		} else {
			p.op << hint
		}
	}
	mut r := A64Result{bytes: []int{}, kind: 0, label: '', cc: 0}

	// 无操作数指令
	if m == 'syscall' || m == 'sysret' || m == 'int3' || m == 'hlt' || m == 'ud2' || m == 'leave' || m == 'nop' || m == 'cqo' || m == 'cdq' || m == 'cwd' || m == 'cbw' || m == 'cwde' || m == 'pushf' || m == 'popf' {
		if m == 'syscall' {
			r.bytes = [0x0F, 0x05]
		} else if m == 'sysret' {
			r.bytes = [0x0F, 0x07]
		} else if m == 'int3' {
			r.bytes = [0xCC]
		} else if m == 'hlt' {
			r.bytes = [0xF4]
		} else if m == 'ud2' {
			r.bytes = [0x0F, 0x0B]
		} else if m == 'leave' {
			r.bytes = [0xC9]
		} else if m == 'nop' {
			r.bytes = [0x90]
		} else if m == 'cqo' {
			r.bytes = [0x48, 0x99]
		} else if m == 'cdq' {
			r.bytes = [0x99]
		} else if m == 'cwd' {
			r.bytes = [0x66, 0x99]
		} else if m == 'cbw' {
			r.bytes = [0x66, 0x98]
		} else if m == 'cwde' {
			r.bytes = [0x98]
		} else if m == 'pushf' {
			r.bytes = [0x9C]
		} else {
			r.bytes = [0x9D]
		}
		return r
	}
	if m == 'ret' {
		if n == 0 {
			r.bytes = [0xC3]
		} else {
			v := a64_num(args[0]) or { return error(err.msg()) }
			mut bb := [0xC2]
			for x in a64_imm(v, 2) {
				bb << x
			}
			r.bytes = bb
		}
		return r
	}
	if m == 'int' {
		v := a64_num(args[0]) or { return error(err.msg()) }
		r.bytes = [0xCD, int(v & 255)]
		return r
	}
	// 相对跳转 / 调用（cone 侧 patch rel32）
	if m == 'jmp' || m == 'call' || a64_jcc_code(m) >= 0 {
		a := ops[0]
		if a.kind == 3 {
			if m == 'jmp' {
				r.kind = 1
			} else if m == 'call' {
				r.kind = 2
			} else {
				r.kind = 3
				r.cc = a64_jcc_code(m)
			}
			r.label = a.label
			return r
		}
		if m == 'jmp' {
			p.rex_w = false
			p.op << 0xFF
			e.modrm(a, 4, mut p, sz)
		} else if m == 'call' {
			p.rex_w = false
			p.op << 0xFF
			e.modrm(a, 2, mut p, sz)
		} else {
			return error('asm64 ${m} 间接形态不支持')
		}
		r.bytes = a64_build(p)
		return r
	}
	// mov
	if m == 'mov' || m == 'movabs' {
		a := ops[0]
		b := ops[1]
		if b.kind == 0 {
			v := b.imm
			if a.kind == 1 {
				if sz == 8 {
					apv := 0xB0 + (a.reg & 7)
					p.op << apv
					if (a.reg >> 3) & 1 == 1 {
						p.rex_b = true
					}
					p.imm = a64_imm(v, 1)
				} else if sz == 16 {
					apv := 0xB8 + (a.reg & 7)
					p.op << apv
					if (a.reg >> 3) & 1 == 1 {
						p.rex_b = true
					}
					p.imm = a64_imm(v, 2)
				} else if sz == 64 && !(v >= i64(-2147483648) && v <= i64(2147483647)) {
					apv := 0xB8 + (a.reg & 7)
					p.op << apv
					if (a.reg >> 3) & 1 == 1 {
						p.rex_b = true
					}
					p.imm = a64_imm(v, 8)
				} else if sz == 64 {
					p.op << 0xC7
					e.modrm(a, 0, mut p, sz)
					p.imm = a64_imm(v, 4)
				} else {
					apv := 0xB8 + (a.reg & 7)
					p.op << apv
					if (a.reg >> 3) & 1 == 1 {
						p.rex_b = true
					}
					p.imm = a64_imm(v, 4)
				}
			} else {
				p.op << (if sz == 8 { 0xC6 } else { 0xC7 })
				e.modrm(a, 0, mut p, sz)
				if sz == 8 {
					p.imm = a64_imm(v, 1)
				} else if sz == 16 {
					p.imm = a64_imm(v, 2)
				} else {
					p.imm = a64_imm(v, 4)
				}
			}
			r.bytes = a64_build(p)
			return r
		}
		if b.kind == 3 {
			return error('asm64 mov 的立即数不支持标号 / 重定位: ${b.text}')
		}
		if a.kind == 1 && (b.kind == 1 || b.kind == 2) {
			p.op << (if sz == 8 { 0x8A } else { 0x8B })
			e.modrm(b, a.reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		if a.kind == 2 && b.kind == 1 {
			p.op << (if sz == 8 { 0x88 } else { 0x89 })
			e.modrm(a, b.reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		return error('asm64 mov 操作数形态不支持: ${args.join(',')}')
	}
	// lea
	if m == 'lea' {
		a := ops[0]
		b := ops[1]
		if a.kind != 1 || b.kind != 2 {
			return error('asm64 lea reg, [mem]')
		}
		p.op << 0x8D
		e.modrm(b, a.reg, mut p, sz)
		r.bytes = a64_build(p)
		return r
	}
	// ALU
	alu_names := ['add', 'or', 'adc', 'sbb', 'and', 'sub', 'xor', 'cmp']
	alu_rm := [0x01, 0x09, 0x11, 0x19, 0x21, 0x29, 0x31, 0x39]
	alu_reg := [0x03, 0x0B, 0x13, 0x1B, 0x23, 0x2B, 0x33, 0x3B]
	mut ai := 0
	mut alu_hit := -1
	for ai < alu_names.len {
		if m == alu_names[ai] {
			alu_hit = ai
			break
		}
		ai = ai + 1
	}
	if alu_hit >= 0 {
		rmop := alu_rm[alu_hit]
		regop := alu_reg[alu_hit]
		digit := alu_hit
		a := ops[0]
		b := ops[1]
		if b.kind == 0 {
			v := b.imm
			mut opc := 0x81
			if sz == 8 {
				opc = 0x80
			} else if v >= i64(-128) && v <= i64(127) {
				opc = 0x83
			}
			p.op << opc
			e.modrm(a, digit, mut p, sz)
			if opc == 0x83 || opc == 0x80 {
				p.imm = a64_imm(v, 1)
			} else if sz == 16 {
				p.imm = a64_imm(v, 2)
			} else {
				p.imm = a64_imm(v, 4)
			}
			r.bytes = a64_build(p)
			return r
		}
		if a.kind == 1 && b.kind == 1 {
			p.op << (if sz == 8 { rmop - 1 } else { rmop })
			e.modrm(a, b.reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		if a.kind == 1 && b.kind == 2 {
			p.op << (if sz == 8 { regop - 1 } else { regop })
			e.modrm(b, a.reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		if a.kind == 2 && b.kind == 1 {
			p.op << (if sz == 8 { rmop - 1 } else { rmop })
			e.modrm(a, b.reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		return error('asm64 ${m} 操作数形态不支持')
	}
	// test
	if m == 'test' {
		a := ops[0]
		b := ops[1]
		if b.kind == 0 {
			if sz == 8 {
				p.op << 0xA8
			} else if a.kind == 1 && a.reg == 0 {
				p.op << 0xA9
			} else {
				p.op << 0xF7
			}
			if p.op[p.op.len - 1] == 0xF7 {
				e.modrm(a, 0, mut p, sz)
				if sz == 16 {
					p.imm = a64_imm(b.imm, 2)
				} else {
					p.imm = a64_imm(b.imm, 4)
				}
			} else {
				if sz == 8 {
					p.imm = a64_imm(b.imm, 1)
				} else if sz == 16 {
					p.imm = a64_imm(b.imm, 2)
				} else {
					p.imm = a64_imm(b.imm, 4)
				}
			}
			r.bytes = a64_build(p)
			return r
		}
		p.op << (if sz == 8 { 0x84 } else { 0x85 })
		if a.kind == 1 && b.kind == 2 {
			e.modrm(b, a.reg, mut p, sz)
		} else {
			mut rf := 0
			if b.kind == 1 {
				rf = b.reg
			}
			e.modrm(a, rf, mut p, sz)
		}
		r.bytes = a64_build(p)
		return r
	}
	// xchg
	if m == 'xchg' {
		a := ops[0]
		b := ops[1]
		p.op << (if sz == 8 { 0x86 } else { 0x87 })
		if a.kind == 1 {
			e.modrm(b, a.reg, mut p, sz)
		} else {
			e.modrm(a, b.reg, mut p, sz)
		}
		r.bytes = a64_build(p)
		return r
	}
	// inc / dec / neg / not / mul / div / idiv / imul(1 op)
	grp_names := ['inc', 'dec', 'neg', 'not', 'mul', 'div', 'idiv']
	grp_op8 := [0xFE, 0xFE, 0xF6, 0xF6, 0xF6, 0xF6, 0xF6]
	grp_op := [0xFF, 0xFF, 0xF7, 0xF7, 0xF7, 0xF7, 0xF7]
	grp_d := [0, 1, 3, 2, 4, 6, 7]
	mut gi := 0
	mut grp_hit := -1
	for gi < grp_names.len {
		if m == grp_names[gi] {
			grp_hit = gi
			break
		}
		gi = gi + 1
	}
	if grp_hit >= 0 {
		p.op << (if sz == 8 { grp_op8[grp_hit] } else { grp_op[grp_hit] })
		e.modrm(ops[0], grp_d[grp_hit], mut p, sz)
		r.bytes = a64_build(p)
		return r
	}
	if m == 'imul' {
		if n == 1 {
			p.op << (if sz == 8 { 0xF6 } else { 0xF7 })
			e.modrm(ops[0], 5, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		if n == 2 {
			p.op << 0x0F
			p.op << 0xAF
			e.modrm(ops[1], ops[0].reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
		if n == 3 && ops[2].kind == 0 {
			v := ops[2].imm
			if v >= i64(-128) && v <= i64(127) {
				p.op << 0x6B
			} else {
				p.op << 0x69
			}
			e.modrm(ops[1], ops[0].reg, mut p, sz)
			if p.op[p.op.len - 1] == 0x6B {
				p.imm = a64_imm(v, 1)
			} else if sz == 16 {
				p.imm = a64_imm(v, 2)
			} else {
				p.imm = a64_imm(v, 4)
			}
			r.bytes = a64_build(p)
			return r
		}
		return error('asm64 imul 形态不支持')
	}
	// push / pop
	if m == 'push' || m == 'pop' {
		a := ops[0]
		p.rex_w = false
		if a.kind == 1 {
			mut b := 0x50
			if m == 'pop' {
				b = 0x58
			}
			apv := b + (a.reg & 7)
			p.op << apv
			if (a.reg >> 3) & 1 == 1 {
				p.rex_b = true
			}
			if sz == 16 {
				p.p66 = true
			}
			r.bytes = a64_build(p)
			return r
		}
		if m == 'push' && a.kind == 0 {
			v := a.imm
			if v >= i64(-128) && v <= i64(127) {
				p.op << 0x6A
				p.imm = a64_imm(v, 1)
			} else {
				p.op << 0x68
				p.imm = a64_imm(v, 4)
			}
			r.bytes = a64_build(p)
			return r
		}
		if m == 'push' {
			p.op << 0xFF
			e.modrm(a, 6, mut p, sz)
		} else {
			p.op << 0x8F
			e.modrm(a, 0, mut p, sz)
		}
		r.bytes = a64_build(p)
		return r
	}
	// 移位
	sh_names := ['rol', 'ror', 'rcl', 'rcr', 'shl', 'sal', 'shr', 'sar']
	sh_d := [0, 1, 2, 3, 4, 4, 5, 7]
	mut shi := 0
	mut sh_hit := -1
	for shi < sh_names.len {
		if m == sh_names[shi] {
			sh_hit = shi
			break
		}
		shi = shi + 1
	}
	if sh_hit >= 0 {
		d := sh_d[sh_hit]
		a := ops[0]
		if n == 1 || (n == 2 && ops[1].kind == 0 && ops[1].imm == 1) {
			p.op << (if sz == 8 { 0xD0 } else { 0xD1 })
			e.modrm(a, d, mut p, sz)
		} else if n == 2 && ops[1].kind == 1 && ops[1].reg == 1 && ops[1].size == 8 {
			p.op << (if sz == 8 { 0xD2 } else { 0xD3 })
			e.modrm(a, d, mut p, sz)
		} else if n == 2 && ops[1].kind == 0 {
			p.op << (if sz == 8 { 0xC0 } else { 0xC1 })
			e.modrm(a, d, mut p, sz)
			p.imm = a64_imm(ops[1].imm, 1)
		} else {
			return error('asm64 ${m} 形态不支持')
		}
		r.bytes = a64_build(p)
		return r
	}
	// movzx / movsx / movsxd
	if m == 'movzx' || m == 'movsx' || m == 'movsxd' {
		a := ops[0]
		b := ops[1]
		if m == 'movsxd' {
			p.op << 0x63
			e.modrm(b, a.reg, mut p, 64)
			r.bytes = a64_build(p)
			return r
		}
		mut srcsz := 8
		if b.kind == 1 {
			srcsz = b.size
		} else if b.hint != 0 {
			srcsz = b.hint
		}
		mut opc := 0xB6
		if srcsz == 16 {
			opc = 0xB7
		}
		if m == 'movsx' {
			opc = opc + 8
		}
		p.op << 0x0F
		p.op << opc
		e.modrm(b, a.reg, mut p, a.size)
		r.bytes = a64_build(p)
		return r
	}
	if m == 'bswap' {
		a := ops[0]
		p.op << 0x0F
		apv := 0xC8 + (a.reg & 7)
		p.op << apv
		if (a.reg >> 3) & 1 == 1 {
			p.rex_b = true
		}
		r.bytes = a64_build(p)
		return r
	}
	if m.len > 3 && m[..3] == 'set' {
		cc := a64_jcc_code(m[3..])
		if cc >= 0 {
			p.op << 0x0F
			opv := 0x90 + cc
			p.op << opv
			e.modrm(ops[0], 0, mut p, 8)
			r.bytes = a64_build(p)
			return r
		}
	}
	if m.len > 4 && m[..4] == 'cmov' {
		cc := a64_jcc_code(m[4..])
		if cc >= 0 {
			p.op << 0x0F
			opv := 0x40 + cc
			p.op << opv
			e.modrm(ops[1], ops[0].reg, mut p, sz)
			r.bytes = a64_build(p)
			return r
		}
	}
	if m == 'bt' || m == 'bts' || m == 'btr' || m == 'btc' {
		p.op << 0x0F
		if m == 'bt' {
			p.op << 0xA3
		} else if m == 'bts' {
			p.op << 0xAB
		} else if m == 'btr' {
			p.op << 0xB3
		} else {
			p.op << 0xBB
		}
		e.modrm(ops[0], ops[1].reg, mut p, sz)
		r.bytes = a64_build(p)
		return r
	}
	// ---- cone 0.9preview3：扩充常用 x64 指令 ----
	// (1) 字符串指令（可带 rep / repe / repne 前缀）：opcode / 66 / REX.W
	str_names := ['movsb', 'movsw', 'movsd', 'movsq', 'stosb', 'stosw', 'stosd', 'stosq',
		'lodsb', 'lodsw', 'lodsd', 'lodsq', 'cmpsb', 'cmpsw', 'cmpsd', 'cmpsq',
		'scasb', 'scasw', 'scasd', 'scasq', 'insb', 'insw', 'insd', 'outsb', 'outsw', 'outsd']
	str_opc := [0xA4, 0xA5, 0xA5, 0xA5, 0xAA, 0xAB, 0xAB, 0xAB,
		0xAC, 0xAD, 0xAD, 0xAD, 0xA6, 0xA7, 0xA7, 0xA7,
		0xAE, 0xAF, 0xAF, 0xAF, 0x6C, 0x6D, 0x6D, 0x6E, 0x6F, 0x6F]
	str_p66 := [0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0]
	str_rw := [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
	mut si := 0
	mut str_hit := false
	for si < str_names.len {
		if m == str_names[si] {
			str_hit = true
			break
		}
		si = si + 1
	}
	if str_hit && n == 0 {
		if str_p66[si] == 1 {
			p.p66 = true
		}
		if str_rw[si] == 1 {
			p.rex_w = true
		}
		p.op << str_opc[si]
		r.bytes = a64_build(p)
		return r
	}
	// (2) 标志位 / 单字节杂项
	flag_names := ['clc', 'stc', 'cli', 'sti', 'cld', 'std', 'cmc', 'lahf', 'sahf', 'xlatb', 'int1']
	flag_opc := [0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xF5, 0x9F, 0x9E, 0xD7, 0xF1]
	mut fi := 0
	mut flag_hit := false
	for fi < flag_names.len {
		if m == flag_names[fi] {
			flag_hit = true
			break
		}
		fi = fi + 1
	}
	if flag_hit && n == 0 {
		p.op << flag_opc[fi]
		r.bytes = a64_build(p)
		return r
	}
	// (3) 系统 / 0F 系列无操作数
	mut sysb := []int{}
	if m == 'cpuid' {
		sysb = [0x0F, 0xA2]
	} else if m == 'rdtsc' {
		sysb = [0x0F, 0x31]
	} else if m == 'rdpmc' {
		sysb = [0x0F, 0x33]
	} else if m == 'sysenter' {
		sysb = [0x0F, 0x34]
	} else if m == 'sysexit' {
		sysb = [0x0F, 0x35]
	} else if m == 'invd' {
		sysb = [0x0F, 0x08]
	} else if m == 'wbinvd' {
		sysb = [0x0F, 0x09]
	} else if m == 'rdtscp' {
		sysb = [0x0F, 0x01, 0xF9]
	} else if m == 'swapgs' {
		sysb = [0x0F, 0x01, 0xF8]
	} else if m == 'pause' {
		sysb = [0xF3, 0x90]
	} else if m == 'monitor' {
		sysb = [0x0F, 0x01, 0xC8]
	} else if m == 'mwait' {
		sysb = [0x0F, 0x01, 0xC9]
	}
	if sysb.len > 0 && n == 0 {
		for x in sysb {
			p.op << x
		}
		r.bytes = a64_build(p)
		return r
	}
	// (4) retf / retn / iret / enter
	if m == 'retf' || m == 'retn' {
		if n == 0 {
			if m == 'retf' {
				p.op << 0xCB
			} else {
				p.op << 0xC3
			}
		} else {
			if m == 'retf' {
				p.op << 0xCA
			} else {
				p.op << 0xC2
			}
			v := a64_num(real_args[0]) or { return error(err.msg()) }
			p.imm = a64_imm(v, 2)
		}
		r.bytes = a64_build(p)
		return r
	}
	if m == 'iret' || m == 'iretd' || m == 'iretq' {
		if m == 'iretd' {
			p.p66 = true
		}
		if m == 'iretq' {
			p.rex_w = true
		}
		p.op << 0xCF
		r.bytes = a64_build(p)
		return r
	}
	if m == 'enter' {
		if n != 2 {
			return error('asm64 enter 需要 2 个操作数（enter imm16,imm8）')
		}
		v0 := a64_num(real_args[0]) or { return error(err.msg()) }
		v1 := a64_num(real_args[1]) or { return error(err.msg()) }
		p.op << 0xC8
		mut ib := a64_imm(v0, 2)
		for x in a64_imm(v1, 1) {
			ib << x
		}
		p.imm = ib
		r.bytes = a64_build(p)
		return r
	}
	// (5) 双精度移位 shld / shrd（r/m, reg, imm8 | cl）
	if m == 'shld' || m == 'shrd' {
		if n != 3 {
			return error('asm64 ${m} 需要 3 个操作数')
		}
		a := ops[0]
		b := ops[1]
		c := ops[2]
		if b.kind != 1 {
			return error('asm64 ${m} 第二操作数必须是寄存器')
		}
		if c.kind == 0 {
			p.op << 0x0F
			if m == 'shld' {
				p.op << 0xA4
			} else {
				p.op << 0xAC
			}
			e.modrm(a, b.reg, mut p, sz)
			p.imm = a64_imm(c.imm, 1)
		} else if c.kind == 1 && c.reg == 1 && c.size == 8 {
			p.op << 0x0F
			if m == 'shld' {
				p.op << 0xA5
			} else {
				p.op << 0xAD
			}
			e.modrm(a, b.reg, mut p, sz)
		} else {
			return error('asm64 ${m} 第三操作数必须是 imm8 或 cl')
		}
		r.bytes = a64_build(p)
		return r
	}
	// (6) 位扫描 / popcnt / lzcnt / tzcnt
	mut bit_opc := 0
	mut bit_f3 := false
	if m == 'bsf' {
		bit_opc = 0xBC
	} else if m == 'bsr' {
		bit_opc = 0xBD
	} else if m == 'popcnt' {
		bit_opc = 0xB8
		bit_f3 = true
	} else if m == 'lzcnt' {
		bit_opc = 0xBD
		bit_f3 = true
	} else if m == 'tzcnt' {
		bit_opc = 0xBC
		bit_f3 = true
	}
	if bit_opc != 0 && n == 2 {
		if bit_f3 {
			p.op << 0xF3
		}
		p.op << 0x0F
		p.op << bit_opc
		e.modrm(ops[1], ops[0].reg, mut p, sz)
		r.bytes = a64_build(p)
		return r
	}
	// (7) xadd / cmpxchg / cmpxchg8b / cmpxchg16b
	if m == 'xadd' || m == 'cmpxchg' {
		if n != 2 {
			return error('asm64 ${m} 需要 2 个操作数')
		}
		mut opc := 0xC1
		if sz == 8 {
			if m == 'xadd' {
				opc = 0xC0
			} else {
				opc = 0xB0
			}
		} else if m == 'cmpxchg' {
			opc = 0xB1
		}
		p.op << 0x0F
		p.op << opc
		e.modrm(ops[0], ops[1].reg, mut p, sz)
		r.bytes = a64_build(p)
		return r
	}
	if m == 'cmpxchg8b' || m == 'cmpxchg16b' {
		if n != 1 {
			return error('asm64 ${m} 需要 1 个操作数')
		}
		if m == 'cmpxchg16b' {
			p.rex_w = true
		}
		p.op << 0x0F
		p.op << 0xC7
		if m == 'cmpxchg16b' {
			e.modrm(ops[0], 1, mut p, 64)
		} else {
			e.modrm(ops[0], 1, mut p, 32)
		}
		r.bytes = a64_build(p)
		return r
	}
	return error('asm64 不支持的 x64 指令: ${m0} ${args.join(',')}')
}

// ---------- asm64 body 编译器 ----------

fn (mut e A64Enc) newlbl() string {
	n := e.prefix + '_' + '${e.lid}'
	e.lid = e.lid + 1
	return n
}

fn (mut e A64Enc) add(text string, nbytes int, bs []int, plabel string, pat int) {
	e.items << A64Item{
		text:   text
		nbytes: nbytes
		start:  e.total
		bytes:  bs.clone()
		plabel: plabel
		pat:    pat
	}
	e.total = e.total + nbytes
}

fn (mut e A64Enc) label(name string) {
	e.add(name + ':', 0, []int{}, '', -1)
	e.labels[name] = e.total
}

fn (mut e A64Enc) dbline(bs []int) {
	mut parts := []string{}
	for x in bs {
		parts << a64_hx(x)
	}
	e.add('    db ' + parts.join(','), bs.len, bs, '', -1)
}

fn (mut e A64Enc) jmp(target string) {
	e.add('', 5, [0xE9, 0, 0, 0, 0], target, 1)
}

fn (mut e A64Enc) jcc(cc int, target string) {
	e.add('', 6, [0x0F, 0x80 + cc, 0, 0, 0, 0], target, 2)
}

fn (mut e A64Enc) instr(line string) ! {
	m, args := a64_split(line)
	r := e.encode(m, args) or { return error(err.msg()) }
	if r.kind == 1 {
		e.jmp(r.label)
	} else if r.kind == 2 {
		e.add('', 5, [0xE8, 0, 0, 0, 0], r.label, 1)
	} else if r.kind == 3 {
		e.jcc(r.cc, r.label)
	} else {
		e.dbline(r.bytes)
	}
}

fn a64_atom(t0 string) (string, string, string) {
	t := a64_trim(t0)
	ops := ['==', '!=', '>=', '<=', '>', '<']
	for op in ops {
		i := a64_find(t, op)
		if i > 0 {
			return a64_trim(t[..i]), op, a64_trim(t[i + op.len..])
		}
	}
	return t, '', ''
}

fn (mut e A64Enc) atom_jump(t0 string, target string, jump_true bool, signed bool) ! {
	mut t := a64_trim(t0)
	mut neg := false
	if t.len > 0 && t[0] == 33 {
		neg = true
		t = a64_trim(t[1..])
	}
	a, op, b := a64_atom(t)
	want_true := (jump_true != neg)
	if op.len > 0 {
		e.instr('cmp ' + a + ',' + b) or { return error(err.msg()) }
		cc := a64_cond_cc(op, want_true, signed)
		e.jcc(cc, target)
	} else {
		e.instr('test ' + a + ',' + a) or { return error(err.msg()) }
		if want_true {
			e.jcc(4, target)
		} else {
			e.jcc(5, target)
		}
	}
}

fn a64_cond_cc(op string, want_true bool, signed bool) int {
	tu := [4, 5, 7, 3, 2, 6]
	fu := [5, 4, 6, 2, 3, 7]
	ts := [4, 5, 15, 13, 12, 14]
	fs := [5, 4, 14, 12, 13, 15]
	mut idx := 0
	if op == '==' {
		idx = 0
	} else if op == '!=' {
		idx = 1
	} else if op == '>' {
		idx = 2
	} else if op == '>=' {
		idx = 3
	} else if op == '<' {
		idx = 4
	} else {
		idx = 5
	}
	if signed {
		if want_true {
			return ts[idx]
		}
		return fs[idx]
	}
	if want_true {
		return tu[idx]
	}
	return fu[idx]
}

fn a64_split_logic(text string, sep string) []string {
	mut out := []string{}
	mut rest := text
	for true {
		i := a64_find(rest, sep)
		if i < 0 {
			break
		}
		out << a64_trim(rest[..i])
		rest = rest[i + sep.len..]
	}
	if a64_trim(rest).len > 0 {
		out << a64_trim(rest)
	}
	return out
}

fn (mut e A64Enc) cond_false(cond0 string, false_lbl string) ! {
	mut c := a64_trim(cond0)
	mut signed := false
	if c.len > 7 && a64_eq(c[..7], 'signed ') {
		signed = true
		c = a64_trim(c[7..])
	} else if c.len > 9 && a64_eq(c[..9], 'unsigned ') {
		c = a64_trim(c[9..])
	}
	if a64_find(c, '||') >= 0 {
		true_lbl := e.newlbl()
		for t in a64_split_logic(c, '||') {
			e.atom_jump(t, true_lbl, true, signed) or { return error(err.msg()) }
		}
		e.jmp(false_lbl)
		e.label(true_lbl)
		return
	}
	for t in a64_split_logic(c, '&&') {
		e.atom_jump(t, false_lbl, false, signed) or { return error(err.msg()) }
	}
}

fn a64_data_line(line string) !(string, int) {
	mut kind := ''
	mut rest := ''
	for k in ['db', 'dw', 'dd', 'dq'] {
		if line.len > k.len + 1 && a64_eq(line[..k.len], k) && (line[k.len] == 32 || line[k.len] == 9) {
			kind = k
			rest = a64_trim(line[k.len..])
			break
		}
	}
	if kind.len == 0 {
		return error('not data')
	}
	mut sz := 4
	if kind == 'db' {
		sz = 1
	} else if kind == 'dw' {
		sz = 2
	} else if kind == 'dq' {
		sz = 8
	}
	mut out := []string{}
	mut total := 0
	for tok0 in rest.split(',') {
		tok := a64_trim(tok0)
		if tok.len == 0 {
			continue
		}
		di := a64_find(tok, 'dup(')
		if di > 0 && tok[tok.len - 1] == 41 {
			cnts := a64_trim(tok[..di])
			inner := a64_trim(tok[di + 4..tok.len - 1])
			cnt := int(a64_num(cnts) or { return error('asm64 ${kind} dup 次数非法: ${cnts}') })
			v := a64_num(inner) or { return error('asm64 ${kind} dup 初值非法: ${inner}') }
			mut bs := []string{}
			for x in a64_imm(v, sz) {
				bs << a64_hx(x)
			}
			apv := '${cnt}' + ' dup(' + bs.join(',') + ')'
			out << apv
			total = total + cnt * sz
			continue
		}
		if tok[0] == 34 || tok[0] == 39 {
			q := tok[0]
			mut body := tok[1..]
			if body.len > 0 && body[body.len - 1] == q {
				body = body[..body.len - 1]
			}
			mut i := 0
			for i < body.len {
				out << a64_hx(int(body[i]))
				total = total + 1
				i = i + 1
			}
			continue
		}
		v := a64_num(tok) or { return error('asm64 ${kind} 数据项必须是编译期数值: ${tok}') }
		for x in a64_imm(v, sz) {
			out << a64_hx(x)
		}
		total = total + sz
	}
	return '    db ' + out.join(','), total
}

fn a64_is_data(line string) bool {
	for k in ['db', 'dw', 'dd', 'dq'] {
		if line.len > k.len + 1 && a64_eq(line[..k.len], k) && (line[k.len] == 32 || line[k.len] == 9) {
			return true
		}
	}
	return false
}

fn (mut e A64Enc) do_line(line string) ! {
	if line == '}' {
		if e.stack.len == 0 {
			return error('asm64 里多余的 }')
		}
		fr := e.stack[e.stack.len - 1]
		e.stack = e.stack[..e.stack.len - 1]
		if fr.kind == 1 {
			if fr.has_nxt {
				e.label(fr.nxt)
			}
			e.label(fr.end_lbl)
		} else if fr.kind == 2 {
			e.jmp(fr.cond_lbl)
			e.label(fr.end_lbl)
		} else if fr.kind == 3 {
			if fr.has_pending {
				e.label(fr.pending)
			}
			e.label(fr.end_lbl)
		} else if fr.kind == 4 {
			e.jmp(fr.match_end)
		}
		return
	}
	// 块开头（以 { 结尾）
	if line.len > 0 && line[line.len - 1] == 123 {
		head := a64_trim(line[..line.len - 1])
		if head.len > 3 && head[..3] == 'if ' {
			end := e.newlbl()
			nxt := e.newlbl()
			e.cond_false(a64_trim(head[3..]), nxt) or { return error(err.msg()) }
			e.stack << A64Frame{kind: 1, end_lbl: end, nxt: nxt, has_nxt: true}
			return
		}
		if head.len > 7 && head[..7] == 'elseif ' {
			if e.stack.len == 0 || e.stack[e.stack.len - 1].kind != 1 {
				return error('asm64 elseif 必须紧跟 if')
			}
			mut fr := e.stack[e.stack.len - 1]
			e.jmp(fr.end_lbl)
			if fr.has_nxt {
				e.label(fr.nxt)
			}
			nxt2 := e.newlbl()
			e.cond_false(a64_trim(head[7..]), nxt2) or { return error(err.msg()) }
			fr.nxt = nxt2
			fr.has_nxt = true
			e.stack[e.stack.len - 1] = fr
			return
		}
		if head == 'else' {
			if e.stack.len == 0 || e.stack[e.stack.len - 1].kind != 1 {
				return error('asm64 else 必须紧跟 if / elseif')
			}
			mut fr := e.stack[e.stack.len - 1]
			e.jmp(fr.end_lbl)
			if fr.has_nxt {
				e.label(fr.nxt)
			}
			fr.has_nxt = false
			e.stack[e.stack.len - 1] = fr
			return
		}
		if head.len > 4 && head[..4] == 'for ' {
			cl := e.newlbl()
			end := e.newlbl()
			e.label(cl)
			e.cond_false(a64_trim(head[4..]), end) or { return error(err.msg()) }
			e.stack << A64Frame{kind: 2, cond_lbl: cl, end_lbl: end}
			return
		}
		if head == 'for' {
			cl := e.newlbl()
			end := e.newlbl()
			e.label(cl)
			e.stack << A64Frame{kind: 2, cond_lbl: cl, end_lbl: end}
			return
		}
		if head.len > 6 && head[..6] == 'match ' {
			e.stack << A64Frame{kind: 3, discr: a64_trim(head[6..]), end_lbl: e.newlbl()}
			return
		}
		// match 内的 case / default
		mut mfi := -1
		if e.stack.len > 0 && e.stack[e.stack.len - 1].kind == 3 {
			mfi = e.stack.len - 1
		}
		if mfi >= 0 {
			mut mf := e.stack[mfi]
			if head == 'default' {
				if mf.has_pending {
					e.label(mf.pending)
				}
				mf.has_pending = false
				e.stack[mfi] = mf
				e.stack << A64Frame{kind: 4, match_end: mf.end_lbl}
				return
			}
			if mf.has_pending {
				e.label(mf.pending)
			}
			e.instr('cmp ' + mf.discr + ',' + head) or { return error(err.msg()) }
			pend := e.newlbl()
			e.jcc(5, pend)
			mf.pending = pend
			mf.has_pending = true
			e.stack[mfi] = mf
			e.stack << A64Frame{kind: 4, match_end: mf.end_lbl}
			return
		}
		return error('asm64 不支持的块语句: ${line}')
	}
	if line == 'break' || line == 'continue' {
		mut fi := -1
		mut k := e.stack.len
		for k > 0 {
			k = k - 1
			if e.stack[k].kind == 2 {
				fi = k
				break
			}
		}
		if fi < 0 {
			return error('asm64 ${line} 只能在 for 循环体内')
		}
		if line == 'break' {
			e.jmp(e.stack[fi].end_lbl)
		} else {
			e.jmp(e.stack[fi].cond_lbl)
		}
		return
	}
	// 用户标号 name:
	if line.len > 1 && line[line.len - 1] == 58 {
		name := a64_trim(line[..line.len - 1])
		mut ok := true
		mut ni := 0
		for ni < name.len {
			c := name[ni]
			if !((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 63 || c == 64 || c == 36) {
				ok = false
			}
			ni = ni + 1
		}
		if ok && name.len > 0 {
			e.label(name)
			return
		}
	}
	// 数据定义
	if a64_is_data(line) {
		txt, nb := a64_data_line(line) or { return error(err.msg()) }
		e.add(txt, nb, []int{}, '', -1)
		return
	}
	e.instr(line) or { return error(err.msg()) }
}

fn (mut e A64Enc) compile(body string) ![]string {
	lines := a64_expand(body)
	mut i := 0
	for i < lines.len {
		line := lines[i]
		if line == '}' && e.stack.len > 0 && e.stack[e.stack.len - 1].kind == 1 && i + 1 < lines.len {
			nx := lines[i + 1]
			if (nx.len > 7 && nx[..7] == 'elseif ') || nx == 'else{' {
				i = i + 1
				continue
			}
		}
		e.do_line(line) or { return error(err.msg()) }
		i = i + 1
	}
	if e.stack.len > 0 {
		return error('asm64 块缺少右花括号 }')
	}
	mut out := []string{}
	for it0 in e.items {
		mut it := it0
		if it.plabel.len > 0 {
			if !(it.plabel in e.labels) {
				return error('asm64 未定义标号: ${it.plabel}')
			}
			rel := e.labels[it.plabel] - (it.start + it.nbytes)
			mut bs := it.bytes.clone()
			mut j := 0
			for j < 4 {
				bs[it.pat + j] = int((rel >> (8 * j)) & 255)
				j = j + 1
			}
			mut parts := []string{}
			for x in bs {
				parts << a64_hx(x)
			}
			it.text = '    db ' + parts.join(',')
		}
		if it.text.len > 0 {
			out << it.text
		}
	}
	return out
}

fn compile_asm64(body string, prefix string) ![]string {
	mut e := a64_new_enc(prefix)
	return e.compile(body)
}
