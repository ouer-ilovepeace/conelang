module main

// ---------- 字符分类 ----------

fn is_alpha(c u8) bool {
	return (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

fn is_digit(c u8) bool {
	return c >= 48 && c <= 57
}

fn is_hex_digit(c u8) bool {
	return is_digit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
}

// MASM 风格标识符：首字符 字母 / _ / ? / @，后续再加数字
fn is_ident_start(c u8) bool {
	return is_alpha(c) || c == 95 || c == 63 || c == 64 // _ ? @
}

fn is_ident_cont(c u8) bool {
	return is_ident_start(c) || is_digit(c)
}

// cone 0.9.f：x64 下 $ 也作为普通标识符字符；x86 保持 $ 为独立立即数 token。
// 另外开一对 64 版函数，避免改动 analyzer / codegen / parser 里已有的单参调用。
fn is_ident_start64(c u8, x64_mode bool) bool {
	return is_ident_start(c) || (x64_mode && c == 36)
}

fn is_ident_cont64(c u8, x64_mode bool) bool {
	return is_ident_cont(c) || (x64_mode && c == 36)
}

fn is_hspace(c u8) bool {
	return c == 32 || c == 9 || c == 13
}

// lex: 阶段 1 —— 词法分析
//
//   * 换行只用于行号统计，【不是】语句终止符；语句边界由 token 结构决定。
//   * `;` 起至行尾为行注释，整段不进入 token 流。
//   * 字符串: "..." 与 '...' 等价；lit 保留含引号原文。收尾引号判定对反斜杠转义做感知，
//     但字节本身原样保留：数据定义仍是"引号内即字节流、无转义"，只有表达式位置的
//     字符常量才在 codegen 里展开 \r \n \t 等转义并默认补 0。
//   * cone 0.3 新增 == != > < >= <= && || !；equ 之后的 <...> 才是尖括号文本。
//   * cone 0.4 fix2：asm{...} 正文整体收成一个 asm_body token（原文含换行），
//     只做花括号配对，内部注释 / 字符串 / 指令 / %标识符 全部原样保留。
//   * 数值: 默认十进制，h/H 结尾为十六进制（0dh、0FFh）；含小数点并入数值。
//   * +/- 是独立 token，由 parser 拼回带符号数值。
//   * 标识符: 支持 ? @ _ 与大小写字母、数字；首字符不能是数字。
fn lex(src string, file string, x64_mode bool) ![]Token {
	mut toks := []Token{}
	// cone 0.83：kw_asm / kw_defined 之后的第一个 { ... } 整段原样收成 asm_body。
	mut want_asm_body := false
	mut i := 0
	mut line := 1
	mut col := 1

	for i < src.len {
		c := src[i]

		if c == 10 { // \n
			i = i + 1
			line = line + 1
			col = 1
			continue
		}
		if is_hspace(c) {
			i = i + 1
			col = col + 1
			continue
		}
		if c == 59 { // ;
			for i < src.len && src[i] != 10 {
				i = i + 1
				col = col + 1
			}
			continue
		}

		sl := line
		sc := col

		// cone 0.83：asm{} / defined 宏体的正文整段原样保留成单个 asm_body token。
		// 内部的 ; 注释、MASM 保留字、逗号、括号、%标识符 都不做词法解析，
		// 只有花括号配对（含字符串 / 注释感知）用来确定正文边界。
		// cone 0.9preview / 0.9.f：$ 在 x86 是特殊立即数（MASM32 当前地址）；
		// x64 下是普通标识符字符，交给下面的标识符分支收进 ident。
		if c == 36 && !x64_mode {
			toks << mk_token(TokenKind.dollar, '$', line, col, file)
			i = i + 1
			col = col + 1
			continue
		}
		if c == 123 && want_asm_body { // {
			want_asm_body = false
			bl := line
			bc := col
			i = i + 1
			col = col + 1
			bstart := i
			mut depth := 1
			for i < src.len && depth > 0 {
				ac := src[i]
				if ac == 10 {
					i = i + 1
					line = line + 1
					col = 1
					continue
				}
				if ac == 59 { // ; 行注释：整行不参与花括号配对，原文保留
					for i < src.len && src[i] != 10 {
						i = i + 1
						col = col + 1
					}
					continue
				}
				if ac == 34 || ac == 39 { // 单双引号内的 } 不参与配对
					quote_char := ac
					i = i + 1
					col = col + 1
					for i < src.len && src[i] != quote_char && src[i] != 10 {
						i = i + 1
						col = col + 1
					}
					if i < src.len && src[i] == quote_char {
						i = i + 1
						col = col + 1
					}
					continue
				}
				if ac == 123 { // {
					depth = depth + 1
					i = i + 1
					col = col + 1
					continue
				}
				if ac == 125 { // }
					depth = depth - 1
					if depth == 0 {
						break
					}
					i = i + 1
					col = col + 1
					continue
				}
				i = i + 1
				col = col + 1
			}
			if depth > 0 {
				return error('${file}:${bl}:${bc} asm{...} / defined 宏体 缺少右花括号 }')
			}
			body := src[bstart..i]
			toks << mk_token(TokenKind.asm_body, body, bl, bc, file)
			i = i + 1 // 跳过 }
			col = col + 1
			continue
		}

		// 标识符 / 关键字
		if is_ident_start64(c, x64_mode) {
			start := i
			for i < src.len && is_ident_cont64(src[i], x64_mode) {
				i = i + 1
				col = col + 1
			}
			lit := src[start..i]
			// cone 0.9.f：w"..." / W"..." 是宽字符串（UTF-16LE）。
			// 前缀必须与引号紧邻；单独的 w 仍是普通标识符 / 变量名。
			if (lit == 'w' || lit == 'W') && i < src.len && (src[i] == 34 || src[i] == 39) {
				q := src[i]
				i = i + 1
				col = col + 1
				for i < src.len && src[i] != 10 {
					if src[i] == 92 {
						i = i + 1
						col = col + 1
						if i < src.len && src[i] != 10 {
							i = i + 1
							col = col + 1
						}
						continue
					}
					if src[i] == q { break }
					i = i + 1
					col = col + 1
				}
				if i >= src.len || src[i] != q {
					return error('${file}:${line}:${col} 宽字符串字面量缺少收尾引号')
				}
				i = i + 1
				col = col + 1
				toks << mk_token(TokenKind.string_lit, src[start..i], sl, sc, file)
				continue
			}
			kw := keyword_of(lit, x64_mode)
			toks << mk_token(kw, lit, sl, sc, file)
			// cone 0.4 fix2：asm{...} 的正文整段原样保留成单个 asm_body token。
			// 内部的 ; 注释、MASM 保留字、逗号、括号、%标识符 都不做词法解析，
			// 只有花括号配对（含字符串 / 注释感知）用来确定正文边界。
			// cone 0.83：asm{} 与 defined 宏体的 { ... } 正文统一在遇到 { 时
			// 整段原样收成 asm_body token（内部不做词法解析，只有花括号配对生效）。
			if kw == TokenKind.kw_asm || kw == TokenKind.kw_defined || kw == TokenKind.kw_asm64 {
				want_asm_body = true
			}
			continue
		}

		// 数值字面量
		if is_digit(c) {
			start := i
			for i < src.len && is_hex_digit(src[i]) {
				i = i + 1
				col = col + 1
			}
			// 小数部分：仅当 . 后面确实是数字，避免吞掉 os.print 的点号
			if i + 1 < src.len && src[i] == 46 && is_digit(src[i + 1]) {
				i = i + 1
				col = col + 1
				for i < src.len && is_digit(src[i]) {
					i = i + 1
					col = col + 1
				}
			}
			if i < src.len && (src[i] == 104 || src[i] == 72) { // h / H
				i = i + 1
				col = col + 1
			}
			lit := src[start..i]
			toks << mk_token(TokenKind.number, lit, sl, sc, file)
			continue
		}

		// 字符串字面量：单双引号等价、lit 原样保留（含引号与反斜杠）。
		// cone 0.3：收尾引号判定对反斜杠转义做感知，避免字符常量里的 \" 提前收尾；
		// 但字符本身仍原样进 lit —— 数据定义 label:"..." 依旧是"引号内即字节流、无转义"，
		// 只有表达式位置的字符串（字符常量）才在 codegen 里展开转义。
		if c == 34 || c == 39 { // " 或 '
			q := c
			start := i
			i = i + 1
			col = col + 1
			for i < src.len && src[i] != 10 {
				if src[i] == 92 { // 反斜杠：连同后一个字符一起吞掉（不判定收尾）
					i = i + 1
					col = col + 1
					if i < src.len && src[i] != 10 {
						i = i + 1
						col = col + 1
					}
					continue
				}
				if src[i] == q {
					break
				}
				i = i + 1
				col = col + 1
			}
			if i >= src.len || src[i] != q {
				return error('${file}:${line}:${col} 字符串字面量缺少收尾引号')
			}
			i = i + 1
			col = col + 1
			lit := src[start..i]
			toks << mk_token(TokenKind.string_lit, lit, sl, sc, file)
			continue
		}

		// equ 的尖括号文本 <...>：只在 `equ` 关键字之后才是尖括号文本，
		// 整段原样保留，MASM 侧直接输出（内部不做词法解析）。
		// cone 0.3 支持比较运算后，其它位置的 < 一律是 lt / le。
		if c == 60 { // <
			mut prev_equ := false
			if toks.len > 0 {
				prev_equ = toks[toks.len - 1].kind == TokenKind.kw_equ
			}
			if prev_equ {
				start := i
				i = i + 1
				col = col + 1
				for i < src.len && src[i] != 62 && src[i] != 10 {
					i = i + 1
					col = col + 1
				}
				if i >= src.len || src[i] != 62 {
					return error('${file}:${line}:${col} equ 的尖括号 <...> 缺少右侧 >')
				}
				i = i + 1
				col = col + 1
				lit := src[start..i]
				toks << mk_token(TokenKind.equ_text, lit, sl, sc, file)
				continue
			}
			if i + 1 < src.len && src[i + 1] == 61 { // <=
				toks << mk_token(TokenKind.le, '<=', sl, sc, file)
				i = i + 2
				col = col + 2
			} else if i + 1 < src.len && src[i + 1] == 60 { // <<
				toks << mk_token(TokenKind.shl, '<<', sl, sc, file)
				i = i + 2
				col = col + 2
			} else {
				toks << mk_token(TokenKind.lt, '<', sl, sc, file)
				i = i + 1
				col = col + 1
			}
			continue
		}

		// cone 0.3：两字符比较 / 逻辑运算符优先判定
		if c == 61 && i + 1 < src.len && src[i + 1] == 61 { // ==
			toks << mk_token(TokenKind.eq_eq, '==', sl, sc, file)
			i = i + 2
			col = col + 2
			continue
		}
		if c == 33 { // ! / !=
			if i + 1 < src.len && src[i + 1] == 61 {
				toks << mk_token(TokenKind.not_eq, '!=', sl, sc, file)
				i = i + 2
				col = col + 2
			} else {
				toks << mk_token(TokenKind.bang, '!', sl, sc, file)
				i = i + 1
				col = col + 1
			}
			continue
		}
		if c == 62 { // > / >= / >>
			if i + 1 < src.len && src[i + 1] == 61 {
				toks << mk_token(TokenKind.ge, '>=', sl, sc, file)
				i = i + 2
				col = col + 2
			} else if i + 1 < src.len && src[i + 1] == 62 { // >>
				toks << mk_token(TokenKind.shr, '>>', sl, sc, file)
				i = i + 2
				col = col + 2
			} else {
				toks << mk_token(TokenKind.gt, '>', sl, sc, file)
				i = i + 1
				col = col + 1
			}
			continue
		}
		if c == 38 { // && / &
			if i + 1 < src.len && src[i + 1] == 38 {
				toks << mk_token(TokenKind.and_and, '&&', sl, sc, file)
				i = i + 2
				col = col + 2
				continue
			}
			toks << mk_token(TokenKind.amp, '&', sl, sc, file)
			i = i + 1
			col = col + 1
			continue
		}
		if c == 124 { // || / |
			if i + 1 < src.len && src[i + 1] == 124 {
				toks << mk_token(TokenKind.or_or, '||', sl, sc, file)
				i = i + 2
				col = col + 2
				continue
			}
			toks << mk_token(TokenKind.pipe, '|', sl, sc, file)
			i = i + 1
			col = col + 1
			continue
		}
		if c == 94 { // ^
			toks << mk_token(TokenKind.caret, '^', sl, sc, file)
			i = i + 1
			col = col + 1
			continue
		}
		if c == 126 { // ~
			toks << mk_token(TokenKind.tilde, '~', sl, sc, file)
			i = i + 1
			col = col + 1
			continue
		}
		if c == 43 && i + 1 < src.len && src[i + 1] == 43 { // ++
			toks << mk_token(TokenKind.plus_plus, '++', sl, sc, file)
			i = i + 2
			col = col + 2
			continue
		}
		if c == 45 && i + 1 < src.len && src[i + 1] == 45 { // --
			toks << mk_token(TokenKind.minus_minus, '--', sl, sc, file)
			i = i + 2
			col = col + 2
			continue
		}

		// 单字符标点 / 运算符
		mut kind := TokenKind.eof
		if c == 58 { // :
			kind = TokenKind.colon
		} else if c == 44 { // ,
			kind = TokenKind.comma
		} else if c == 40 { // (
			kind = TokenKind.lparen
		} else if c == 41 { // )
			kind = TokenKind.rparen
		} else if c == 123 { // {
			kind = TokenKind.lbrace
		} else if c == 125 { // }
			kind = TokenKind.rbrace
		} else if c == 91 { // [
			kind = TokenKind.lbracket
		} else if c == 93 { // ]
			kind = TokenKind.rbracket
		} else if c == 46 { // .
			kind = TokenKind.dot
		} else if c == 61 { // =
			kind = TokenKind.assign
		} else if c == 43 { // +
			kind = TokenKind.plus
		} else if c == 45 { // -
			kind = TokenKind.minus
		} else if c == 42 { // *
			kind = TokenKind.star
		} else if c == 47 { // /
			kind = TokenKind.slash
		} else if c == 37 { // % cone 0.9.1 取模
			kind = TokenKind.percent
		} else {
			return error('${file}:${line}:${col} 无法识别的字符（ASCII ${int(c)}）')
		}
		toks << mk_token(kind, src[i..i + 1], sl, sc, file)
		i = i + 1
		col = col + 1
	}

	toks << mk_token(TokenKind.eof, '<eof>', line, col, file)
	return toks
}
