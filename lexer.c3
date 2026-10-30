module c3::lexer;

import std::io, std::core::ascii;

faultdef INVALID_CHAR;

enum TokenType : ushort
{
	INVALID,

	// Operators
	AMP, BIT_OR, BIT_XOR, BIT_NOT, BANG, PLUS, MINUS, STAR, DIV, MOD,
	QUESTION, QUESTQUEST, ELVIS, BANGBANG, BUILTIN, SHR_OP, SHL_OP,
	PLUSPLUS, MINUSMINUS, CT_CONCAT_OP, CT_TERNARY,

	// Assignment
	EQ, SHR_ASSIGN, SHL_ASSIGN, PLUS_ASSIGN, MINUS_ASSIGN, MULT_ASSIGN,
	DIV_ASSIGN, MOD_ASSIGN, BIT_AND_ASSIGN, BIT_XOR_ASSIGN, BIT_OR_ASSIGN,
	CT_CONCAT_ASSIGN,

	// Comparison
	LESS, GREATER, AND, OR, LESS_EQ, GREATER_EQ, EQEQ, NOT_EQUAL, CT_AND_OP,
	CT_OR_OP,

	// Punctuation
	EOS, COLON, SCOPE, COMMA, DOT, DOTDOT, ELLIPSIS, AT, HASH,

	// Structure
	LBRACE, RBRACE, LBRACKET, RBRACKET, LPAREN, RPAREN, ARROW, IMPLIES,
	LVEC, RVEC,

	// Comments and Contracts
	CONTRACT, LINE_COMMENT, BLOCK_COMMENT,

	// Literals (Identifiers and Strings)
	STRING, CHAR_LITERAL, BYTES, INTEGER, REAL, IDENT, TYPE_IDENT,
	CONST_IDENT, AT_IDENT, AT_TYPE_IDENT, AT_CONST_IDENT, HASH_IDENT,
	HASH_TYPE_IDENT, HASH_CONST_IDENT, CT_IDENT, CT_TYPE_IDENT,
	CT_CONST_IDENT,

	// Base Types (base_type_no_generic)
	VOID, BOOL, CHAR, ICHAR, SHORT, USHORT, INT, UINT, LONG, ULONG, INT128,
	UINT128, FLOAT, DOUBLE, FLOAT16, BFLOAT, FLOAT128, IPTR, UPTR, ISZ,
	USZ, FAULT, ANY, TYPEID, UNTYPEDLIST,

	// Keywords
	ALIAS, ASM, ASSERT, ATTRDEF, ATTRMACRO, BITSTRUCT, CONST, CONSTDEF, CONSTSET, ENUM,
	FAULTDEF, FUNC, IMPORT, INTERFACE, MACRO, MODULE, STRUCT, UNION,
	TYPEDEF, BREAK, CASE, CATCH, CONTINUE, DEFAULT, DEFER, DO, ELSE,
	EXTERN, FALSE, FOR, FOREACH, FOREACH_R, IF, INLINE, LENGTHOF, NEXTCASE,
	NULL, RETURN, STATIC, SWITCH, TLOCAL, TRUE, TRY, VAR, WHILE,

	// Compile time keywords (C3 0.8)
	CT_ASSERT, CT_CASE, CT_DEFAULT, CT_DEFINED, CT_ECHO, CT_ELSE, CT_EMBED,
	CT_ENDFOR, CT_ENDFOREACH, CT_ENDIF, CT_ENDSWITCH, CT_ERROR, CT_EVAL,
	CT_EXEC, CT_EXPAND, CT_FEAT, CT_FEATURE, CT_FOR, CT_FOREACH, CT_IF,
	CT_INCLUDE, CT_REFLECT, CT_STRINGIFY, CT_SWITCH, CT_TYPEFROM, CT_TYPEOF,
	CT_VAARG, AT_INLINE, AT_PURE, AT_NOINLINE,

	EOL, EOF,
}

struct Token (Printable)
{
	TokenType type;
	String    text;
	sz       offset;
	sz       len;
	<* Line and byte column where the token starts, both 1-based. *>
	sz       ln, col;
	<* Newlines between the previous token and this one. *>
	sz       nl_before;
	<*
	 A string, char or bytes literal, block comment or contract that is never
	 closed. The token runs to the end of its line (`"…"`, `'…'`) or the input.
	*>
	bool     unterminated;
}

fn sz? Token.to_format(&self, Formatter *f) @dynamic
{
	sz n;
	n += f.printf("<%s>", self.type)!;
	if (self.text.len)
	{
		@pool() {
			n += f.printf(" %s", self.text.tescape(true))!;
		};
	}
	return n;
}

struct Lexer
{
	String input;
	bool emit_eol;
	sz  pos;
	sz  ln, col;
	sz  token_start;
	sz  token_ln, token_col;
	sz  token_nl;
	sz  nl_before;
	bool unterminated;
}

fn Lexer* Lexer.init(&self, String input, bool emit_eol = false)
{
	*self = { .input = input, .emit_eol = emit_eol, .pos = 0, .token_start = 0,
		.nl_before = 0, .ln = 1, .col = 1 };
	return self;
}

fn void Lexer.report_error(&self, String msg)
{
	io::eprintfn("LEXER ERROR at Ln: %d, Col: %d -- %s", self.ln, self.col, msg);
}

fn bool is_lf(char c) @inline => c == '\n';
fn bool is_ws(char c) @inline => @ok(" \t\r\n".index_of_char(c));
fn bool is_digit(char c) @inline => ascii::is_digit(c);
fn bool is_ident(char c) @inline => ascii::is_alnum(c) || c == '_';

fn char? Lexer.advance(&self)
{
	char c;

	if (self.at_end()) return io::EOF~;

	c = self.input[self.pos];
	self.pos++;

	self.col++;
	if (is_lf(c))
	{
		self.ln++;
		self.nl_before++;
		self.col = 1;
	}
	return c;
}

fn bool Lexer.at_end(&self) => self.pos >= self.input.len;

fn char Lexer.peek(&self, sz ahead = 0)
{
	if (self.pos + ahead >= self.input.len) return 0;
	return self.input[self.pos + ahead];
}

fn bool Lexer.must(&self, String s)
{
	sz n = s.len;
	if (self.pos+n-1 < self.input.len && self.input[self.pos:n] == s)
	{
		while (n--) (void)self.advance();
		return true;
	}
	return false;
}

fn String Lexer.lexeme(&self)
{
	sz len = self.pos - self.token_start;
	return self.input[self.token_start:len];
}

<*
 Emit token from lexer.
*>
fn Token Lexer.emit_token(&self, TokenType type)
{
	String lexeme = self.lexeme();
	Token tok = {
		.type         = type,
		.offset       = self.token_start,
		.len          = lexeme.len,
		.ln           = self.token_ln,
		.col          = self.token_col,
		.text         = lexeme,
		.nl_before    = self.token_nl,
		.unterminated = self.unterminated,
	};
	self.unterminated = false;
	return tok;
}

<*
 Lex the next token.
*>
fn Token? Lexer.next(&self)
{
	char c;
	TokenType type;

	// Newlines inside the previous token belong to it, not to the gap before this one.
	self.nl_before = 0;
	self.scan_whitespace()!;

	self.token_start = self.pos;
	self.token_ln = self.ln;
	self.token_col = self.col;
	self.token_nl = self.nl_before;
	self.unterminated = false;
	if (self.at_end()) return io::EOF~;

	switch (c = self.peek())
	{
		case ';': self.advance()!; return self.emit_token(EOS);
		case ',': self.advance()!; return self.emit_token(COMMA);
		case '~': self.advance()!; return self.emit_token(BIT_NOT);
		case '^':
			switch
			{
				case self.must("^="): type = BIT_XOR_ASSIGN;
				case self.must("^"):  type = BIT_XOR;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '*':
			switch
			{
				case self.must("*="): type = MULT_ASSIGN;
				case self.must("*"):  type = STAR;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '%':
			switch
			{
				case self.must("%="): type = MOD_ASSIGN;
				case self.must("%"):  type = MOD;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '.':
			switch
			{
				case self.must("..."): type = ELLIPSIS;
				case self.must(".."):  type = DOTDOT;
				case self.must("."):   type = DOT;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '+':
			switch
			{
				case self.must("+++="): type = CT_CONCAT_ASSIGN;
				case self.must("+++"):  type = CT_CONCAT_OP;
				case self.must("++"):   type = PLUSPLUS;
				case self.must("+="):   type = PLUS_ASSIGN;
				case self.must("+"):    type = PLUS;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '-':
			switch
			{
				case self.must("--"): type = MINUSMINUS;
				case self.must("-="): type = MINUS_ASSIGN;
				case self.must("->"): type = ARROW;
				case self.must("-"):  type = MINUS;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case ':':
			switch
			{
				case self.must("::"):  type = SCOPE;
				case self.must(":"):   type = COLON;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '!':
			switch
			{
				case self.must("!!"):  type = BANGBANG;
				case self.must("!="):  type = NOT_EQUAL;
				case self.must("!"):   type = BANG;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '?':
			switch
			{
				case self.must("???"): type = CT_TERNARY;
				case self.must("??"):  type = QUESTQUEST;
				case self.must("?:"):  type = ELVIS;
				case self.must("?"):   type = QUESTION;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '|':
			switch
			{
				case self.must("|||"): type = CT_OR_OP;
				case self.must("||"):  type = OR;
				case self.must("|="):  type = BIT_OR_ASSIGN;
				case self.must("|"):   type = BIT_OR;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '&':
			switch
			{
				case self.must("&&&"): type = CT_AND_OP;
				case self.must("&&"):  type = AND;
				case self.must("&="):  type = BIT_AND_ASSIGN;
				case self.must("&"):   type = AMP;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '=':
			switch
			{
				case self.must("=>"):  type = IMPLIES;
				case self.must("=="):  type = EQEQ;
				case self.must("="):   type = EQ;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '>':
			switch
			{
				case self.must(">>="): type = SHR_ASSIGN;
				case self.must(">>"):  type = SHR_OP;
				case self.must(">="):  type = GREATER_EQ;
				case self.must(">]"):  type = RVEC;
				case self.must(">"):   type = GREATER;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case '[':
			switch
			{
				case self.must("[<"):  type = LVEC;
				case self.must("["):   type = LBRACKET;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case ']': self.advance()!; return self.emit_token(RBRACKET);
		case '{': self.advance()!; return self.emit_token(LBRACE);
		case '}': self.advance()!; return self.emit_token(RBRACE);
		case '(': self.advance()!; return self.emit_token(LPAREN);
		case ')': self.advance()!; return self.emit_token(RPAREN);

		case '/':
			switch
			{
				case self.must("//"): self.scan_line_comment()!;  type = LINE_COMMENT;
				case self.must("/*"): self.scan_block_comment()!; type = BLOCK_COMMENT;
				case self.must("/="): type = DIV_ASSIGN;
				case self.must("/") : type = DIV;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case '<':
			switch
			{
				case self.must("<*"):  self.scan_contract()!; type = CONTRACT;
				case self.must("<<="): type = SHL_ASSIGN;
				case self.must("<<"):  type = SHL_OP;
				case self.must("<="):  type = LESS_EQ;
				case self.must("<") :  type = LESS;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case '$':
			switch
			{
				case self.must("$$"): return self.emit_token(BUILTIN);
				case self.must("$"):  return self.lex_compile_time()!;
				default: return INVALID_CHAR~;
			}

		case '@':
		case '#':
			// A shebang is only a comment on the first line.
			if (self.pos == 0 && self.must("#!"))
			{
				self.scan_line_comment()!;
				return self.emit_token(LINE_COMMENT);
			}
			self.advance()!;
			// On its own (`@` in `@[...]`, `#` in `#[...]`) it is punctuation.
			if (!is_ident(self.peek())) return self.emit_token(c == '@' ? AT : HASH);
			return self.lex_at_or_hash_ident()!;

		case 'b':
		case 'x':
			switch
			{
				case self.must("b64\""): self.scan_until('"');
				case self.must("b64'"):  self.scan_until('\'');
				case self.must("b64`"):  self.scan_until('`');
				case self.must("x\""):   self.scan_until('"');
				case self.must("x'"):    self.scan_until('\'');
				case self.must("x`"):    self.scan_until('`');
				default: return self.lex_ident()!;
			}
			return self.emit_token(BYTES);

		case '\'':
			self.scan_string();
			return self.emit_token(CHAR_LITERAL);
		case '"':
		case '`':
			self.scan_string();
			return self.emit_token(STRING);

		case '\n':
			self.advance()!;
			return self.emit_token(EOL);

		default:
			if (is_digit(c)) return self.lex_number()!;
			if (is_ident(c)) return self.lex_ident()!;
			// Not the start of any token. Take the whole UTF-8 character, so a
			// multi-byte one (a pasted smart quote) is one INVALID token, not several.
			self.advance()!;
			while (!self.at_end() && (self.peek() & 0xC0) == 0x80) self.advance()!;
			return self.emit_token(INVALID);
	}
}

fn void? Lexer.scan_whitespace(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ws(c))
	{
		if (self.emit_eol && c == '\n') break;
		self.advance()!;
	}
}

<*
 Scan up to and including `until`; bytes literals may span lines. Unterminated
 when the input ends first.
*>
fn void Lexer.scan_until(&self, char until)
{
	while (!self.at_end())
	{
		if (until == self.advance()!!) return;
	}
	self.unterminated = true;
}

<*
 Scan a string or char literal starting at its opening quote. `"…"` and `'…'`
 end at their line: one that reaches a newline (or the end of the input) has
 lost its closing quote, and stops there instead of swallowing the code that
 follows. A raw `` `…` `` string may span lines, and a doubled backtick in it
 is a literal backtick.
*>
fn void Lexer.scan_string(&self)
{
	char quote = self.peek();
	(void)self.advance(); // Opening quote
	while (!self.at_end())
	{
		char c = self.peek();
		if (quote == '`')
		{
			(void)self.advance();
			if (c != '`') continue;
			if (self.peek() != '`') return;
			(void)self.advance(); // `` is an escaped backtick
			continue;
		}
		if (c == '\n') break;
		(void)self.advance();
		if (c == quote) return;
		// An escape takes the next character with it, but never the line end.
		if (c == '\\' && !self.at_end() && self.peek() != '\n') (void)self.advance();
	}
	self.unterminated = true;
}

fn void? Lexer.scan_line_comment(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && (c != '\n' && c != '\r'))
	{
		self.advance()!;
	}
}

fn void? Lexer.scan_block_comment(&self)
{
	sz depth = 1;
	while (!self.at_end() && depth != 0)
	{
		switch
		{
			case self.must("/*"): depth++;
			case self.must("*/"): depth--;
			default: self.advance()!;
		}
	}
	if (depth != 0) self.unterminated = true;
}

fn void? Lexer.scan_contract(&self)
{
	while (!self.at_end())
	{
		if (self.must("*>")) return;
		self.advance()!;
	}
	self.unterminated = true;
}

fn Token? Lexer.lex_number(&self)
{
	char c, prev;
	int i = 0;
	bool hex = self.peek() == '0' && (self.peek(1) == 'x' || self.peek(1) == 'X');
	while (!self.at_end() && (c = self.peek())
		&& (is_digit(c) || c == '-' || (i > 0 && (ascii::is_xdigit(c) || ascii::is_bdigit(c) || ascii::is_odigit(c)
			|| "+.eEpPbBxXoOuUlLifdDF_".contains_char(c))))
	)
	{
		// A sign belongs to the number only after its exponent marker: `e` in a
		// decimal literal, `p` in a hex one (where `e` is a digit: 0xFE-1).
		if ("+-".contains_char(c) && !(hex ? "pP" : "eE").contains_char(prev)) break;
		if (c == '.' && c == self.peek(1)) break;
		self.advance()!;
		prev = c;
		i++;
	}

	return self.emit_token(number::classify(self.lexeme()));
}

fn Token? Lexer.lex_ident(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	String str = self.lexeme();
	switch (str)
	{
		// Top-Level Explicit Keywords
		case "alias":     return self.emit_token(ALIAS);
		case "attrdef":   return self.emit_token(ATTRDEF);
		case "attrmacro": return self.emit_token(ATTRMACRO);
		case "bitstruct": return self.emit_token(BITSTRUCT);
		case "const":     return self.emit_token(CONST);
		case "constdef":  return self.emit_token(CONSTDEF);
		case "constset":  return self.emit_token(CONSTSET);
		case "enum":      return self.emit_token(ENUM);
		case "faultdef":  return self.emit_token(FAULTDEF);
		case "fn":        return self.emit_token(FUNC);
		case "import":    return self.emit_token(IMPORT);
		case "interface": return self.emit_token(INTERFACE);
		case "macro":     return self.emit_token(MACRO);
		case "module":    return self.emit_token(MODULE);
		case "typedef":   return self.emit_token(TYPEDEF);
		case "struct":    return self.emit_token(STRUCT);
		case "union":     return self.emit_token(UNION);

		// Explicit Keywords
		case "any":       return self.emit_token(ANY);
		case "asm":       return self.emit_token(ASM);
		case "assert":    return self.emit_token(ASSERT);
		case "break":     return self.emit_token(BREAK);
		case "case":      return self.emit_token(CASE);
		case "catch":     return self.emit_token(CATCH);
		case "continue":  return self.emit_token(CONTINUE);
		case "default":   return self.emit_token(DEFAULT);
		case "defer":     return self.emit_token(DEFER);
		case "do":        return self.emit_token(DO);
		case "else":      return self.emit_token(ELSE);
		case "false":     return self.emit_token(FALSE);
		case "for":       return self.emit_token(FOR);
		case "foreach":   return self.emit_token(FOREACH);
		case "foreach_r": return self.emit_token(FOREACH_R);
		case "if":        return self.emit_token(IF);
		case "lengthof":  return self.emit_token(LENGTHOF);
		case "nextcase":  return self.emit_token(NEXTCASE);
		case "null":      return self.emit_token(NULL);
		case "return":    return self.emit_token(RETURN);
		case "static":    return self.emit_token(STATIC);
		case "switch":    return self.emit_token(SWITCH);
		case "true":      return self.emit_token(TRUE);
		case "try":       return self.emit_token(TRY);
		case "var":       return self.emit_token(VAR);
		case "while":     return self.emit_token(WHILE);

		case "extern":    return self.emit_token(EXTERN);
		case "inline":    return self.emit_token(INLINE);
		case "tlocal":    return self.emit_token(TLOCAL);

		// Base Types
		case "void":      return self.emit_token(VOID);
		case "bool":      return self.emit_token(BOOL);
		case "char":      return self.emit_token(CHAR);
		case "ichar":     return self.emit_token(ICHAR);
		case "short":     return self.emit_token(SHORT);
		case "ushort":    return self.emit_token(USHORT);
		case "int":       return self.emit_token(INT);
		case "uint":      return self.emit_token(UINT);
		case "long":      return self.emit_token(LONG);
		case "ulong":     return self.emit_token(ULONG);
		case "int128":    return self.emit_token(INT128);
		case "uint128":   return self.emit_token(UINT128);
		case "iptr":      return self.emit_token(IPTR);
		case "uptr":      return self.emit_token(UPTR);
		case "sz":        return self.emit_token(ISZ);
		case "usz":       return self.emit_token(USZ);
		case "float":     return self.emit_token(FLOAT);
		case "double":    return self.emit_token(DOUBLE);
		case "float16":   return self.emit_token(FLOAT16);
		case "bfloat":    return self.emit_token(BFLOAT);
		case "float128":  return self.emit_token(FLOAT128);
		case "fault":     return self.emit_token(FAULT);
		case "typeid":    return self.emit_token(TYPEID);
		case "untypedlist": return self.emit_token(UNTYPEDLIST);

		default:
			return self.emit_token(ident::classify(str));
	}
}

fn Token? Lexer.lex_compile_time(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	String str = self.lexeme();
	switch (str)
	{
		// Compile time keywords (C3 0.8)
		case "$assert":     return self.emit_token(CT_ASSERT);
		case "$case":       return self.emit_token(CT_CASE);
		case "$default":    return self.emit_token(CT_DEFAULT);
		case "$defined":    return self.emit_token(CT_DEFINED);
		case "$echo":       return self.emit_token(CT_ECHO);
		case "$else":       return self.emit_token(CT_ELSE);
		case "$embed":      return self.emit_token(CT_EMBED);
		case "$endfor":     return self.emit_token(CT_ENDFOR);
		case "$endforeach": return self.emit_token(CT_ENDFOREACH);
		case "$endif":      return self.emit_token(CT_ENDIF);
		case "$endswitch":  return self.emit_token(CT_ENDSWITCH);
		case "$error":      return self.emit_token(CT_ERROR);
		case "$eval":       return self.emit_token(CT_EVAL);
		case "$exec":       return self.emit_token(CT_EXEC);
		case "$expand":     return self.emit_token(CT_EXPAND);
		case "$feat":       return self.emit_token(CT_FEAT);
		case "$feature":    return self.emit_token(CT_FEATURE);
		case "$for":        return self.emit_token(CT_FOR);
		case "$foreach":    return self.emit_token(CT_FOREACH);
		case "$if":         return self.emit_token(CT_IF);
		case "$include":    return self.emit_token(CT_INCLUDE);
		case "$reflect":    return self.emit_token(CT_REFLECT);
		case "$stringify":  return self.emit_token(CT_STRINGIFY);
		case "$switch":     return self.emit_token(CT_SWITCH);
		case "$Typefrom":   return self.emit_token(CT_TYPEFROM);
		case "$Typeof":     return self.emit_token(CT_TYPEOF);
		case "$vaarg":      return self.emit_token(CT_VAARG);

		default:
			return self.emit_token(ident::classify(str));
	}
}

fn Token? Lexer.lex_at_or_hash_ident(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	String str = self.lexeme();
	switch (str)
	{
		case "@inline":   return self.emit_token(AT_INLINE);
		case "@pure":     return self.emit_token(AT_PURE);
		case "@noinline": return self.emit_token(AT_NOINLINE);
		default: return self.emit_token(ident::classify(str));
	}
}

struct ContractLexer
{
	Splitter splitter;
	Lexer    lexer;
	bool     lexer_init;
	<* intro is only available after the entire contract is lexed *>
	String   intro;
}

<*
 @require contract.len >= 4 : "Contract must contain at least 4 chars"
*>
fn ContractLexer* ContractLexer.init(&self, String contract)
{
	*self = {
		.splitter   = contract[2:^4].tokenize_all("\n", true),
		.lexer      = {},
		.lexer_init = false,
	};
	return self;
}

fn Token? ContractLexer.next(&self)
{
	if (!self.lexer_init)
	{
		sz pos;
		pos = self.splitter.current;
		while (try next_line = self.splitter.next())
		{
			if (next_line.trim().starts_with("@"))
			{
				self.intro = self.splitter.string[:pos];
				self.lexer.init(self.splitter.string[pos..], emit_eol: true);
				self.lexer_init = true;
				break;
			}
			pos = self.splitter.current;
		}
	}
	return self.lexer.next();
}

fn void test_contract_lexer() @test
{
	ContractLexer dl;
	dl.init(`<*
		 Check if a character is in a set.

		 @param c : "the character to check"


		 @param [in] set : "String containing the characters"
		 @pure
		 @return "True if a character is in the set"
		 *>`);

	TokenType[] want = {
		AT_IDENT, IDENT, COLON, STRING, EOL, EOL, EOL,
		AT_IDENT, LBRACKET, IDENT, RBRACKET, IDENT, COLON, STRING, EOL,
		AT_PURE, EOL,
		AT_IDENT, STRING, EOL,
	};

	while (try tok = dl.next() && want.len)
	{
		assert(tok.type == want[0], "Token type mismatch: got=%s, but want=%s", tok.type, want[0]);
		want = want[1..];
	}
	assert(dl.intro.trim() == "Check if a character is in a set.");
}

<*
 Lex `input` and return its tokens (temp-allocated).
*>
fn Token[] lex_all(String input) @private
{
	Token[] out = mem::temp_array(Token, input.len + 1);
	sz n = 0;
	Lexer lex;
	lex.init(input);
	while (try tok = lex.next()) out[n++] = tok;
	assert(lex.at_end(), "the lexer must reach the end of the input");
	return out[:n];
}

fn void test_unterminated_string_stops_at_line_end() @test
{
	Token[] toks = lex_all("a = \"abc;\nint x;");
	assert(toks[2].type == STRING && toks[2].unterminated);
	assert(toks[2].text == "\"abc;", "got %s", toks[2].text);
	assert(toks[3].type == INT && toks[3].ln == 2 && toks[3].col == 1, "the next line lexes normally");
}

fn void test_unterminated_literals_at_eof_are_tokens() @test
{
	foreach (src : (String[]){ "\"abc", "'a", "`abc", "\"abc\\", "x\"00", "/* x", "<* x" })
	{
		Token[] toks = lex_all(src);
		assert(toks.len == 1 && toks[0].unterminated && toks[0].text == src, "for %s", src);
	}
}

fn void test_closed_literals_are_terminated() @test
{
	foreach (src : (String[]){ "\"a\\\"b\"", "'a'", "`a``b`", "x\"00\n11\"", "/* /* */ */", "<* x *>" })
	{
		Token[] toks = lex_all(src);
		assert(toks.len == 1 && !toks[0].unterminated && toks[0].text == src, "for %s", src);
	}
}

fn void test_escape_never_takes_the_newline() @test
{
	Token[] toks = lex_all("\"a\\\nb\"");
	assert(toks[0].type == STRING && toks[0].unterminated && toks[0].text == "\"a\\");
}

fn void test_invalid_utf8_char_is_one_token() @test
{
	Token[] toks = lex_all("x = \xe2\x80\x9cy;");
	assert(toks[2].type == INVALID && toks[2].len == 3);
	assert(toks[3].type == IDENT && toks[3].text == "y");
}

fn void test_hex_e_is_not_an_exponent() @test
{
	Token[] toks = lex_all("0xFE-1 1e-5");
	assert(toks.len == 4, "got %d tokens", toks.len);
	assert(toks[0].type == INTEGER && toks[1].type == MINUS && toks[2].type == INTEGER);
	assert(toks[3].type == REAL && toks[3].text == "1e-5");
}

fn void test_compile_time_keywords_08() @test
{
	Token[] toks = lex_all("$Typeof $Typefrom $feat $feature $reflect $embed $expand $typeof $sizeof");
	TokenType[] want = { CT_TYPEOF, CT_TYPEFROM, CT_FEAT, CT_FEATURE, CT_REFLECT, CT_EMBED, CT_EXPAND, CT_IDENT, CT_IDENT };
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_type_keywords_08() @test
{
	Token[] toks = lex_all("bfloat untypedlist bfloat16 isz sz attrmacro");
	TokenType[] want = { BFLOAT, UNTYPEDLIST, IDENT, IDENT, ISZ, ATTRMACRO };
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_bare_at_and_hash() @test
{
	Token[] toks = lex_all("@ # @foo #bar");
	TokenType[] want = { AT, HASH, AT_IDENT, HASH_IDENT };
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_shebang_only_on_first_line() @test
{
	assert(lex_all("#!/usr/bin/env c3\nx")[0].type == LINE_COMMENT);
	Token[] toks = lex_all("a #!b");
	assert(toks[1].type == HASH && toks[2].type == BANG);
}

fn void test_token_position_is_its_start() @test
{
	Token[] toks = lex_all("a\n  /* x\n y */ b");
	assert(toks[1].ln == 2 && toks[1].col == 3, "comment starts at 2:3, got %d:%d", toks[1].ln, toks[1].col);
	assert(toks[1].nl_before == 1);
	assert(toks[2].ln == 3 && toks[2].nl_before == 0, "newlines inside the comment are not before `b`");
}

module c3::lexer::number;

<*
 Number literal states, following c3c: an `_` must sit between two digits, a
 base prefix needs at least one digit, integer suffixes are `u`, `l`, `ul`,
 `ll` and `ull` (any case), and reals take an optional `f`/`d` (any case).
*>
enum NumberState : char (TokenType type) @private
{
	ERROR      { INVALID },
	INIT       { INVALID },
	INTEGER    { INTEGER },
	ZERO       { INTEGER },
	HEXSTART   { INVALID },  // "0x" with no digit yet
	HEXINT     { INTEGER },
	OCTSTART   { INVALID },
	OCTINT     { INTEGER },
	BINSTART   { INVALID },
	BININT     { INTEGER },
	INT_US     { INVALID },  // "_" inside a decimal integer
	HEX_US     { INVALID },
	OCT_US     { INVALID },
	BIN_US     { INVALID },
	SUFFIX_U   { INTEGER },  // u
	SUFFIX_L   { INTEGER },  // l
	SUFFIX_UL  { INTEGER },  // ul
	SUFFIX_END { INTEGER },  // ll, ull
	REAL       { REAL },     // after a real suffix
	DOT        { REAL },     // INT "." (c3c accepts `1.`)
	INTDEC     { REAL },     // INT "." INT
	DEC_US     { INVALID },  // "_" inside the fraction
	EDIGITS    { REAL },     // Exponent digits
	HEXDEC     { INVALID },  // Hexadecimal "decimal": HEXINT "." HEXINT
	HEXDEC_US  { INVALID },
	EXPONENT   { INVALID },  // E-notation [eEpP]
	EXPSIGN    { INVALID },  // Exponent sign: + or -
}

const NumberState[char::max+1][*] TRANSITIONS @private = {
	[NumberState.INIT] = {
		['1'..'9'] = INTEGER,
		['0']      = ZERO,
		['+']      = INIT,
		['-']      = INIT,
	},
	[NumberState.INTEGER] = {
		['0'..'9'] = INTEGER,
		['_']      = INT_US,
		['e']      = EXPONENT,  ['E'] = EXPONENT,
		['d']      = REAL,      ['f'] = REAL,
		['D']      = REAL,      ['F'] = REAL,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
		['.']      = DOT,
	},
	[NumberState.ZERO] = {
		['0'..'9'] = INTEGER,
		['_']      = INT_US,
		['b']      = BINSTART,  ['B'] = BINSTART,
		['o']      = OCTSTART,  ['O'] = OCTSTART,
		['x']      = HEXSTART,  ['X'] = HEXSTART,
		['e']      = EXPONENT,  ['E'] = EXPONENT,
		['d']      = REAL,      ['f'] = REAL,
		['D']      = REAL,      ['F'] = REAL,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
		['.']      = DOT,
	},
	[NumberState.INT_US] = {
		['0'..'9'] = INTEGER,
		['.']      = DOT,
	},
	[NumberState.HEXSTART] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
	},
	[NumberState.HEXINT] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
		['_']      = HEX_US,
		['p']      = EXPONENT,  ['P'] = EXPONENT,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
		['.']      = HEXDEC,
	},
	[NumberState.HEX_US] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
	},
	[NumberState.OCTSTART] = {
		['0'..'7'] = OCTINT,
	},
	[NumberState.OCTINT] = {
		['0'..'7'] = OCTINT,
		['_']      = OCT_US,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
	},
	[NumberState.OCT_US] = {
		['0'..'7'] = OCTINT,
	},
	[NumberState.BINSTART] = {
		['0'..'1'] = BININT,
	},
	[NumberState.BININT] = {
		['0'..'1'] = BININT,
		['_']      = BIN_US,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
	},
	[NumberState.BIN_US] = {
		['0'..'1'] = BININT,
	},
	[NumberState.SUFFIX_U] = {
		['l']      = SUFFIX_UL, ['L'] = SUFFIX_UL,
	},
	[NumberState.SUFFIX_L] = {
		['l']      = SUFFIX_END, ['L'] = SUFFIX_END,
	},
	[NumberState.SUFFIX_UL] = {
		['l']      = SUFFIX_END, ['L'] = SUFFIX_END,
	},
	[NumberState.DOT] = {
		['0'..'9'] = INTDEC,
		['e']      = EXPONENT, ['E'] = EXPONENT,
		['d']      = REAL,     ['f'] = REAL,
		['D']      = REAL,     ['F'] = REAL,
	},
	[NumberState.INTDEC] = {
		['0'..'9'] = INTDEC,
		['_']      = DEC_US,
		['e']      = EXPONENT, ['E'] = EXPONENT,
		['d']      = REAL,     ['f'] = REAL,
		['D']      = REAL,     ['F'] = REAL,
	},
	[NumberState.DEC_US] = {
		['0'..'9'] = INTDEC,
	},
	[NumberState.HEXDEC] = {
		['0'..'9'] = HEXDEC,
		['a'..'f'] = HEXDEC,
		['A'..'F'] = HEXDEC,
		['_']      = HEXDEC_US,
		['p']      = EXPONENT,  ['P'] = EXPONENT,
	},
	[NumberState.HEXDEC_US] = {
		['0'..'9'] = HEXDEC,
		['a'..'f'] = HEXDEC,
		['A'..'F'] = HEXDEC,
	},
	[NumberState.EXPONENT] = {
		['0'..'9'] = EDIGITS,
		['+']      = EXPSIGN,
		['-']      = EXPSIGN,
	},
	[NumberState.EDIGITS] = {
		['0'..'9'] = EDIGITS,
		['d']      = REAL, ['f'] = REAL,
		['D']      = REAL, ['F'] = REAL,
	},
	[NumberState.EXPSIGN] = {
		['0'..'9'] = EDIGITS,
	},
};

fn TokenType classify(String s)
{
	NumberState state = INIT;
	foreach (c: s) state = TRANSITIONS[state][c];
	return state.type;
}

fn void test_number_classify() @test
{
	assert(classify("+")          ==  INVALID);
	assert(classify("-")          ==  INVALID);
	assert(classify("0")          ==  INTEGER);
	assert(classify("-1")         ==  INTEGER);
	assert(classify("123")        ==  INTEGER);
	assert(classify("123ul")      ==  INTEGER);
	assert(classify("123i32")     ==  INVALID);
	assert(classify("0xdeadbeeF") ==  INTEGER);
	assert(classify("0xcafeUL")   ==  INTEGER);
	assert(classify("0b101UL")    ==  INTEGER);
	assert(classify("1xbeef")     ==  INVALID);
	assert(classify("0b1001.001") ==  INVALID);
	assert(classify("0b123")      ==  INVALID);
	assert(classify("0xbeeF.123p1") == REAL);
	assert(classify("0f")         ==   REAL);
	assert(classify("0.5f")       ==   REAL);
	assert(classify("123.0")      ==   REAL);
	assert(classify("123.0e-10")  ==   REAL);
	assert(classify("123f")       ==   REAL);
	assert(classify("123d")       ==   REAL);
	assert(classify("1.0F")       ==   REAL);
	assert(classify("2D")         ==   REAL);
	assert(classify("1.")         ==   REAL);
	assert(classify("1.e5")       ==   REAL);
	assert(classify("1_.5")       ==   REAL);
	assert(classify("0x1.p1")     ==   REAL);
	assert(classify("1uLL")       ==   INTEGER);
	assert(classify("1Ll")        ==   INTEGER);
	assert(classify("1_000")      ==   INTEGER);
	assert(classify("0x1_F")      ==   INTEGER);
	assert(classify("1lu")        ==   INVALID);
	assert(classify("1u8")        ==   INVALID);
	assert(classify("1__2")       ==   INVALID);
	assert(classify("1_")         ==   INVALID);
	assert(classify("0x")         ==   INVALID);
	assert(classify("0x_1")       ==   INVALID);
	assert(classify("0b_1")       ==   INVALID);
	assert(classify("1._5")       ==   INVALID);
	assert(classify("1e1_0")      ==   INVALID);
	assert(classify("1.0u")       ==   INVALID);
	assert(classify("1e")         ==   INVALID);
	assert(classify("0x1p")       ==   INVALID);
}

module c3::lexer::ident;

enum IdentState : char (bool accept) @private {
	ERROR_STATE { false },
	INIT_STATE  { false },
	IDENT_STATE { true },
	TYPE_STATE  { true },
	CONST_STATE { true },
}

const IdentState[char::max+1][*] TRANSITIONS @private = {
	[IdentState.INIT_STATE] = {
		['A'..'Z'] = CONST_STATE,
		['a'..'z'] = IDENT_STATE,
		['_']      = INIT_STATE,
		['$']      = INIT_STATE,
		['#']      = INIT_STATE,
		['@']      = INIT_STATE,
	},
	[IdentState.IDENT_STATE] = {
		['A'..'Z'] = IDENT_STATE,
		['a'..'z'] = IDENT_STATE,
		['0'..'9'] = IDENT_STATE,
		['_']      = IDENT_STATE,
	},
	[IdentState.TYPE_STATE] = {
		['A'..'Z'] = TYPE_STATE,
		['a'..'z'] = TYPE_STATE,
		['0'..'9'] = TYPE_STATE,
		['_']      = TYPE_STATE,
	},
	[IdentState.CONST_STATE] = {
		['A'..'Z'] = CONST_STATE,
		['a'..'z'] = TYPE_STATE,
		['0'..'9'] = CONST_STATE,
		['_']      = CONST_STATE,
	},
};

fn TokenType classify(String s)
{
	// Verify order of TokenTypes
	assert(TokenType.IDENT.ordinal + 1      == TokenType.TYPE_IDENT.ordinal);
	assert(TokenType.IDENT.ordinal + 2      == TokenType.CONST_IDENT.ordinal);
	assert(TokenType.CT_IDENT.ordinal + 1   == TokenType.CT_TYPE_IDENT.ordinal);
	assert(TokenType.CT_IDENT.ordinal + 2   == TokenType.CT_CONST_IDENT.ordinal);
	assert(TokenType.AT_IDENT.ordinal + 1   == TokenType.AT_TYPE_IDENT.ordinal);
	assert(TokenType.AT_IDENT.ordinal + 2   == TokenType.AT_CONST_IDENT.ordinal);
	assert(TokenType.HASH_IDENT.ordinal + 1 == TokenType.HASH_TYPE_IDENT.ordinal);
	assert(TokenType.HASH_IDENT.ordinal + 2 == TokenType.HASH_CONST_IDENT.ordinal);

	IdentState state = IdentState.INIT_STATE;
	foreach (c: s) state = TRANSITIONS[state][c];
	if (state.accept)
	{
		char offset = state.ordinal - IdentState.IDENT_STATE.ordinal;
		switch (s[0])
		{
		case '$': return TokenType::from_ordinal(offset + TokenType.CT_IDENT.ordinal);
		case '#': return TokenType::from_ordinal(offset + TokenType.HASH_IDENT.ordinal);
		case '@': return TokenType::from_ordinal(offset + TokenType.AT_IDENT.ordinal);
		default:  return TokenType::from_ordinal(offset + TokenType.IDENT.ordinal);
		}
	}
	return INVALID;
}

fn void test_ident_classify() @test
{
	assert(classify("AABB") == CONST_IDENT);
	assert(classify("Aabb") == TYPE_IDENT);
	assert(classify("aabb") == IDENT);
	assert(classify("aaBb") == IDENT);
	assert(classify("@AABB") == AT_CONST_IDENT);
	assert(classify("@Aabb") == AT_TYPE_IDENT);
	assert(classify("@aabb") == AT_IDENT);
	assert(classify("#AABB") == HASH_CONST_IDENT);
	assert(classify("#Aabb") == HASH_TYPE_IDENT);
	assert(classify("#aabb") == HASH_IDENT);
	assert(classify("$AABB") == CT_CONST_IDENT);
	assert(classify("$Aabb") == CT_TYPE_IDENT);
	assert(classify("$aabb") == CT_IDENT);
}


