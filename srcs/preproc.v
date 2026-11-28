module main

// cone 0.9.f —— 源码级预处理（编译期确定，不生成任何 MASM / LLVM 伪指令）
//
//   defsym NAME                         登记一个编译期符号
//   ifdef NAME{ ... } elsedef{ ... }    符号已定义走 then，否则走 else
//   ifndef NAME{ ... } elsedef{ ... }   符号未定义走 then
//   enum [名字]{ A, B=10, C }           展开成等价的 equ 声明序列
//
// 符号来源：命令行 -D[NAME] ∪ 源码 defsym NAME ∪ defined NAME(...) 宏定义
//           ∪ 内置 CONE_X64 / CONE_X86。
// equ / enum / def / struct 等**不**自动成为符号（避免自指循环）；
// 要用它们判断请写 defsym。整段在 lex / expand_imports 之后、parse 之前完成。

fn pp_add_sym_v(mut syms []string, name string) {
	if !(name in syms) {
		syms << name
	}
}

fn pp_collect_syms_v(toks []Token, x64_mode bool, cli_syms []string) []string {
	mut syms := []string{}
	for s2 in cli_syms {
		pp_add_sym_v(mut syms, s2)
	}
	if x64_mode {
		pp_add_sym_v(mut syms, 'CONE_X64')
	} else {
		pp_add_sym_v(mut syms, 'CONE_X86')
	}
	mut i := 0
	for i + 1 < toks.len {
		k := toks[i].kind
		if (k == TokenKind.kw_defsym || k == TokenKind.kw_defined || k == TokenKind.kw_enum)
			&& toks[i + 1].kind == TokenKind.ident {
			pp_add_sym_v(mut syms, toks[i + 1].lit)
		}
		i++
	}
	return syms
}

// asm_body 是单个 token，内部花括号不参与配对；只有 lbrace / rbrace 计数。
fn pp_match_rbrace_v(seq []Token, i int) !int {
	mut depth := 0
	mut j := i
	for j < seq.len {
		if seq[j].kind == TokenKind.lbrace {
			depth++
		} else if seq[j].kind == TokenKind.rbrace {
			depth--
			if depth == 0 {
				return j
			}
		}
		j++
	}
	return error('第 ${seq[i].line} 行: ifdef / ifndef / elsedef 块缺少右花括号 }')
}

fn pp_slice_v(seq []Token, a int, b int) []Token {
	mut out := []Token{}
	mut q := a
	for q < b {
		out << seq[q]
		q++
	}
	return out
}

fn pp_filter_v(seq []Token, syms []string, x64_mode bool) ![]Token {
	mut out := []Token{}
	mut i := 0
	for i < seq.len {
		t := seq[i]
		if t.kind == TokenKind.kw_defsym {
			i++
			if i < seq.len && seq[i].kind == TokenKind.ident { i++ }
			continue
		}
		if t.kind == TokenKind.kw_ifdef || t.kind == TokenKind.kw_ifndef {
			if i + 1 >= seq.len || seq[i + 1].kind != TokenKind.ident {
				return error('第 ${t.line} 行: ${t.lit} 后需要一个符号名')
			}
			name := seq[i + 1].lit
			i += 2
			if i >= seq.len || seq[i].kind != TokenKind.lbrace {
				return error('第 ${t.line} 行: ${t.lit} ${name} 后需要 { ... }')
			}
			j := pp_match_rbrace_v(seq, i) or { return error(err.msg()) }
			then_a := i + 1
			then_b := j
			mut k2 := j + 1
			mut els_a := 0
			mut els_b := 0
			if k2 < seq.len && seq[k2].kind == TokenKind.kw_elsedef {
				k2++
				if k2 >= seq.len || seq[k2].kind != TokenKind.lbrace {
					return error('第 ${t.line} 行: elsedef 后需要 { ... }')
				}
				j2 := pp_match_rbrace_v(seq, k2) or { return error(err.msg()) }
				els_a = k2 + 1
				els_b = j2
				k2 = j2 + 1
			}
			mut cond := false
			if t.kind == TokenKind.kw_ifdef {
				cond = name in syms
			} else {
				cond = !(name in syms)
			}
			if cond {
				inner := pp_filter_v(pp_slice_v(seq, then_a, then_b), syms, x64_mode) or {
					return error(err.msg())
				}
				for q in inner { out << q }
			} else {
				inner := pp_filter_v(pp_slice_v(seq, els_a, els_b), syms, x64_mode) or {
					return error(err.msg())
				}
				for q in inner { out << q }
			}
			i = k2
			continue
		}
		if t.kind == TokenKind.kw_elsedef {
			return error('第 ${t.line} 行: elsedef 没有配对的 ifdef / ifndef')
		}
		out << t
		i++
	}
	return out
}

fn pp_tok_v(kind TokenKind, lit string, model Token) Token {
	return mk_token(kind, lit, model.line, model.col, model.file)
}

// enum [名字]{ A, B=10, C } -> `A equ 0` / `B equ 10` / `C equ B+1` token 序列。
// 不带 = 时首项为 0，其余为「上一项 + 1」；表达式里的 equ 名由 analyzer 迭代折叠。
fn pp_enum_v(seq []Token) ![]Token {
	mut out := []Token{}
	mut i := 0
	for i < seq.len {
		t := seq[i]
		if t.kind != TokenKind.kw_enum {
			out << t
			i++
			continue
		}
		i++
		if i < seq.len && seq[i].kind == TokenKind.ident { i++ }
		if i >= seq.len || seq[i].kind != TokenKind.lbrace {
			return error('第 ${t.line} 行: enum 后需要 { ... }')
		}
		i++
		mut prev := ''
		mut first := true
		for {
			if i >= seq.len {
				return error('第 ${t.line} 行: enum 缺少右花括号 }')
			}
			if seq[i].kind == TokenKind.rbrace { i++; break }
			if seq[i].kind == TokenKind.comma { i++; continue }
			if seq[i].kind != TokenKind.ident {
				return error('第 ${t.line} 行: enum 成员名必须是标识符，得到 ${seq[i].lit}')
			}
			nt := seq[i]
			i++
			mut expr := []Token{}
			if i < seq.len && seq[i].kind == TokenKind.assign {
				i++
				mut depth := 0
				for i < seq.len {
					k2 := seq[i].kind
					if k2 == TokenKind.lparen || k2 == TokenKind.lbracket {
						depth++
					} else if k2 == TokenKind.rparen || k2 == TokenKind.rbracket {
						if depth == 0 { break }
						depth--
					} else if depth == 0 && (k2 == TokenKind.comma || k2 == TokenKind.rbrace) {
						break
					}
					expr << seq[i]
					i++
				}
				if expr.len == 0 {
					return error('第 ${t.line} 行: enum 成员 ${nt.lit} 的 = 后需要常量表达式')
				}
			}
			out << pp_tok_v(TokenKind.ident, nt.lit, nt)
			out << pp_tok_v(TokenKind.kw_equ, 'equ', nt)
			if expr.len > 0 {
				for q in expr { out << q }
			} else if first {
				out << pp_tok_v(TokenKind.number, '0', nt)
			} else {
				out << pp_tok_v(TokenKind.ident, prev, nt)
				out << pp_tok_v(TokenKind.plus, '+', nt)
				out << pp_tok_v(TokenKind.number, '1', nt)
			}
			prev = nt.lit
			first = false
			if i < seq.len && seq[i].kind == TokenKind.comma { i++ }
		}
	}
	return out
}

fn preprocess_v(toks []Token, cli_syms []string, x64_mode bool) ![]Token {
	syms := pp_collect_syms_v(toks, x64_mode, cli_syms)
	seq := pp_filter_v(toks, syms, x64_mode) or { return error(err.msg()) }
	return pp_enum_v(seq)
}
