module main

// cone 0.9.p —— asm64{} -> LLVM inline asm / module asm（V 实现）
//
// 与 Python 参考实现 llvmir.py 的 llvm_a64_* 同名同义：asm64{} 正文是
// masm64 语法的 x64 汇编指令，cone 不编码、不修改、不优化，只做语法桥接：
//   * type ptr / [...] / gs:[...] / fs:[...] / xxx:标号 / db dd dw dq dup
//   * MASM 伪指令 offset / option / proc / .if / cone 控制流 -> 报错
//   * 60h -> 0x60（LLVM MC 不认 MASM 的 h 后缀）
//   * %标识符 / %+标识符 -> cone 变量地址（函数体走 $N 操作数，顶层走符号）
//   * 标号加唯一前缀；sideeffect + 全 GPR clobber + memory 防止被优化掉

const a64x_clobbers = '~{rax},~{rbx},~{rcx},~{rdx},~{rsi},~{rdi},~{r8},~{r9},~{r10},~{r11},~{r12},~{r13},~{r14},~{r15},~{dirflag},~{fpsr},~{flags},~{memory}'

fn a64x_bad_directive(w string) bool {
	bad := ['offset', 'option', 'proc', 'endp', 'invoke', 'segment', 'ends',
		'assume', 'align', 'equ', 'macro', 'endm', 'include', 'includelib',
		'public', 'extrn', 'extern', 'struct', 'union', 'typedef', 'end',
		'exitm', 'local', 'uses', 'proto', 'model', '.if', '.else', '.elseif',
		'.endif', '.while', '.endw', '.repeat', '.until', '.break', '.continue',
		'if', 'elseif', 'else', 'for', 'match', 'default', 'while']
	return a64_lower(w) in bad
}

fn a64x_is_alpha(c u8) bool {
	return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
		|| c == 64 || c == 36 || c == 63
}

fn a64x_is_alnum(c u8) bool {
	return a64x_is_alpha(c) || (c >= 48 && c <= 57)
}

fn a64x_all_words(line string) []string {
	mut out := []string{}
	mut i := 0
	for i < line.len {
		c := line[i]
		if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 46 {
			mut j := i
			for j < line.len && (a64x_is_alnum(line[j]) || line[j] == 46) { j++ }
			out << a64_lower(line[i..j])
			i = j
		} else {
			i++
		}
	}
	return out
}

fn a64x_strip_refs(line string) string {
	// 剥掉 %变量 / %+变量 引用，避免把 cone 变量名误判成 MASM 伪指令
	mut out := ''
	mut i := 0
	for i < line.len {
		if line[i] == 37 {
			i++
			if i < line.len && line[i] == 43 { i++ }
			for i < line.len && a64x_is_alnum(line[i]) { i++ }
			out += ' '
		} else {
			out += line[i..i + 1]
			i++
		}
	}
	return out
}

fn a64x_first_word(line string) string {
	s := a64_trim(line)
	mut i := 0
	for i < s.len && s[i] != 32 && s[i] != 9 && s[i] != 58 {
		i++
	}
	return a64_lower(s[..i])
}

fn a64x_split_items_v(text string) []string {
	mut out := []string{}
	mut buf := ''
	mut depth := 0
	for i := 0; i < text.len; i++ {
		c := text[i]
		if c == 40 {
			depth++
			buf += '('
		} else if c == 41 {
			depth--
			buf += ')'
		} else if c == 44 && depth == 0 {
			out << a64_trim(buf)
			buf = ''
		} else {
			buf += text[i..i + 1]
		}
	}
	if a64_trim(buf).len > 0 { out << a64_trim(buf) }
	return out
}


fn a64x_data_mc(kind string) string {
	if kind == 'db' { return '.byte' }
	if kind == 'dw' { return '.word' }
	if kind == 'dd' { return '.long' }
	return '.quad'
}

fn a64x_data_line_v(kind string, rest string, ln int) ![]string {
	mut vals := []int{}
	for it in a64x_split_items_v(rest) {
		low := a64_lower(it)
		if low.contains('dup(') {
			di := it.index('dup') or { return error('asm64--db dup(...) 缺少重复次数') }
			nt := a64_num(a64_trim(it[..di])) or { return error('asm64--db dup(...) 重复次数不是编译期整数') }
			mut op := -1
			mut cl2 := -1
			for q := 0; q < it.len; q++ {
				if it[q] == 40 && op < 0 { op = q }
				if it[q] == 41 { cl2 = q }
			}
			if op < 0 || cl2 <= op { return error('asm64--db dup(...) 括号不配对') }
			mut inner := []int{}
			for x in a64x_split_items_v(it[op + 1..cl2]) {
				iv := a64_num(x) or { return error('asm64--db dup(...) 内容不是编译期整数') }
				inner << int(iv)
			}
			if inner.len == 0 { return error('asm64--db dup(...) 内容为空') }
			for q2 := 0; q2 < int(nt); q2++ {
				for v in inner { vals << v }
			}
		} else {
			iv2 := a64_num(it) or { return error('asm64--${kind} 数据项不是编译期整数') }
			vals << int(iv2)
		}
	}
	if vals.len == 0 { return error('asm64--${kind} 后没有数据项') }
	mut line := a64x_data_mc(kind) + ' '
	for i := 0; i < vals.len; i++ {
		if i > 0 { line += ', ' }
		line += vals[i].str()
	}
	return [line]
}

fn a64x_norm_hex_v(line string) string {
	mut out := ''
	mut i := 0
	for i < line.len {
		c := line[i]
		if c >= 48 && c <= 57 {
			mut j := i
			for j < line.len && a64_is_hex(line[j]) { j++ }
			if j < line.len && (line[j] == 104 || line[j] == 72) {
				mut boundary := true
				if j + 1 < line.len {
					nc := line[j + 1]
					if (nc >= 48 && nc <= 57) || (nc >= 65 && nc <= 90)
						|| (nc >= 97 && nc <= 122) || nc == 95 {
						boundary = false
					}
				}
				if boundary {
					out += '0x' + line[i..j]
					i = j + 1
					continue
				}
			}
			out += line[i..j]
			i = j
		} else {
			out += line[i..i + 1]
			i++
		}
	}
	return out
}

fn a64x_escape_v(line string) string {
	return line.replace('\\', '\\\\').replace('"', '\\"')
}

fn a64x_asm_string_v(lines []string) string {
	mut out := ''
	for i := 0; i < lines.len; i++ {
		if i > 0 { out += '\\n\\t' }
		out += a64x_escape_v(lines[i])
	}
	return out
}

fn a64x_template_v(text string, vars map[string]string, uid string, top bool,
	line0 int) !([]string, []string) {
	mut raw := []string{}
	for x in text.split('\n') { raw << a64_strip_comment(x) }
	mut labels := map[string]string{}
	for ln0 in raw {
		t := a64_trim(ln0)
		mut ci := -1
		for q := 0; q < t.len; q++ {
			if t[q] == 58 { ci = q; break }
		}
		if ci > 0 {
			nm := a64_trim(t[..ci])
			mut ok := true
			for q2 := 0; q2 < nm.len; q2++ {
				if !a64x_is_alnum(nm[q2]) { ok = false }
			}
			if ok && nm.len > 0 { labels[nm] = '__cone_a64_' + uid + '_' + nm }
		}
	}
	mut operands := []string{}
	mut lines := []string{}
	for ri := 0; ri < raw.len; ri++ {
		ln := a64_trim(raw[ri])
		if ln.len == 0 { continue }
		// cone 0.9.p：整行扫描（伪指令也可能出现在操作数位置，如 `mov eax, offset foo`）
		for w in a64x_all_words(a64x_strip_refs(ln)) {
			if a64x_bad_directive(w) {
				return error('asm64--不支持 MASM 伪指令 `${w}`')
			}
		}
		fw := a64x_first_word(ln)
		if fw == 'db' || fw == 'dw' || fw == 'dd' || fw == 'dq' {
			dl := a64x_data_line_v(fw, ln[fw.len..], line0 + ri) or { return error(err.msg()) }
			for d in dl { lines << d }
			continue
		}
		// 标号定义
		mut ci2 := -1
		for q3 := 0; q3 < ln.len; q3++ {
			if ln[q3] == 58 { ci2 = q3; break }
		}
		mut body := ln
		if ci2 > 0 && a64_trim(ln[..ci2]) in labels {
			lbl := a64_trim(ln[..ci2])
			lines << labels[lbl] + ':'
			body = a64_trim(ln[ci2 + 1..])
			if body.len == 0 { continue }
		}
		// 标号引用替换
		for lbl2, mapped in labels {
			body = body.replace(lbl2, mapped)
		}
		body = a64x_norm_hex_v(body)
		// %标识符 / %+标识符 -> $N 或符号；%% 是转义
		mut out := ''
		mut i := 0
		for i < body.len {
			if body[i] == 37 {
				if i + 1 < body.len && body[i + 1] == 37 {
					out += '%%'
					i += 2
					continue
				}
				mut j := i + 1
				if j < body.len && body[j] == 43 { j++ }
				if j < body.len && a64x_is_alpha(body[j]) {
					mut k := j
					for k < body.len && a64x_is_alnum(body[k]) { k++ }
					nm := body[j..k]
					if !(nm in vars) {
						return error('asm64--%${nm} 未声明')
					}
					val := vars[nm]
					if top {
						out += val
					} else {
						out += '$' + operands.len.str()
						operands << val
					}
					i = k
					continue
				}
			}
			out += body[i..i + 1]
			i++
		}
		lines << out
	}
	if lines.len == 0 { lines << 'nop' }
	return lines, operands
}
